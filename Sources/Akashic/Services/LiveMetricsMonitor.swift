import Combine
import Darwin
import Foundation

/// Process RSS, host memory, and aggregate CPU sampled about once a second.
@MainActor
final class LiveMetricsMonitor: ObservableObject {
    @Published private(set) var snapshot = LiveMetricsSnapshot()

    private var previousCPU: HostCPUTicks?
    private var cancellable: AnyCancellable?

    init() {
        sample()
    }

    func start() {
        guard cancellable == nil else { return }
        sample()
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sample()
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }

    func sample() {
        var next = snapshot
        if let rss = MachHostMetrics.appResidentBytes() {
            next.appRSS = rss
        }
        if let sys = MachHostMetrics.systemMemory() {
            next.sysUsed = sys.used
            next.sysTotal = sys.total
        }
        if let ticks = MachHostMetrics.cpuTicks() {
            if let previous = previousCPU, let percent = ticks.usagePercent(since: previous) {
                next.cpuPercent = percent
            }
            previousCPU = ticks
        }
        snapshot = next
    }
}

struct LiveMetricsSnapshot: Equatable, Sendable {
    var appRSS: UInt64 = 0
    var sysUsed: UInt64 = 0
    var sysTotal: UInt64 = 0
    /// Machine-wide 0–100 once two tick samples exist; `nil` until then.
    var cpuPercent: Double?
}

enum CompactBytes {
    private static let kilobyte = 1024.0
    private static let megabyte = kilobyte * 1024
    private static let gigabyte = megabyte * 1024

    /// `42M`, `1.2G`, `512K` — short labels for one header line.
    static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= gigabyte { return scaled(value / gigabyte, suffix: "G") }
        if value >= megabyte { return scaled(value / megabyte, suffix: "M") }
        return scaled(value / kilobyte, suffix: "K")
    }

    /// `18/36G` sharing the total's unit.
    static func usedOverTotal(used: UInt64, total: UInt64) -> String {
        let totalValue = Double(total)
        if totalValue >= gigabyte * 0.5 {
            return "\(Int((Double(used) / gigabyte).rounded()))/\(Int((totalValue / gigabyte).rounded()))G"
        }
        if totalValue >= megabyte {
            return "\(Int((Double(used) / megabyte).rounded()))/\(Int((totalValue / megabyte).rounded()))M"
        }
        return "\(format(used))/\(format(total))"
    }

    private static func scaled(_ value: Double, suffix: String) -> String {
        if value >= 10 {
            return "\(Int(value.rounded()))\(suffix)"
        }
        let tenths = (value * 10).rounded() / 10
        if tenths.rounded() == tenths {
            return "\(Int(tenths))\(suffix)"
        }
        return String(format: "%.1f%@", tenths, suffix)
    }
}

enum MetricsStripText {
    static let separator = "  ·  "
    static let empty = "—"

    struct Lines: Equatable {
        var full: String
        var compact: String
        var short: String
        var minimal: String
    }

    static func make(
        appRSS: UInt64,
        sysUsed: UInt64,
        sysTotal: UInt64,
        cpuPercent: Double?,
        cloudAgents: Int?,
        bots: Int?
    ) -> Lines {
        let app = "APP \(CompactBytes.format(appRSS))"
        let sys = "SYS \(CompactBytes.usedOverTotal(used: sysUsed, total: sysTotal))"
        let cpu: String = {
            if let cpuPercent {
                return "CPU \(Int(cpuPercent.rounded()))%"
            }
            return "CPU \(empty)"
        }()
        let ca: String = {
            if let cloudAgents {
                return "CA \(cloudAgents)"
            }
            return "CA \(empty)"
        }()
        let bot = bots.map { "BOT \($0)" }

        func join(_ parts: [String]) -> String {
            parts.joined(separator: separator)
        }

        var fullParts = [app, sys, cpu, ca]
        var compactParts = [app, cpu, ca]
        if let bot {
            fullParts.append(bot)
            compactParts.append(bot)
        }

        return Lines(
            full: join(fullParts),
            compact: join(compactParts),
            short: join([app, ca]),
            minimal: app
        )
    }
}

enum MachHostMetrics {
    static func appResidentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    static func systemMemory() -> (used: UInt64, total: UInt64)? {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_page_size)
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let used = min(usedPages * page, total)
        return (used, total)
    }

    static func cpuTicks() -> HostCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return HostCPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }
}

struct HostCPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }

    /// Aggregate across all cores, scaled to ~0–100 for the machine.
    func usagePercent(since previous: HostCPUTicks) -> Double? {
        let deltaTotal = delta(total, previous.total)
        let deltaBusy = delta(busy, previous.busy)
        guard deltaTotal > 0 else { return nil }
        let percent = (Double(deltaBusy) / Double(deltaTotal)) * 100
        return min(100, max(0, percent))
    }

    private func delta(_ now: UInt64, _ then: UInt64) -> UInt64 {
        if now >= then { return now - then }
        return now &+ (UInt64(UInt32.max) &- then) &+ 1
    }
}
