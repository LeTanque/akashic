import Combine
import Foundation

/// Cursor Models / Other Models % used (Plan & Usage semantics), refreshed on a slow poll.
@MainActor
final class CursorQuotaMonitor: ObservableObject {
    @Published private(set) var snapshot = CursorQuotaSnapshot()

    private var cancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    /// Not every host tick — quota APIs are rate-limited and unrelated to CPU sampling.
    static let pollInterval: TimeInterval = 120

    func start() {
        guard cancellable == nil else { return }
        scheduleRefresh()
        cancellable = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let next = await CursorQuotaLoader.load()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.snapshot = next
            }
        }
    }
}

struct CursorQuotaSnapshot: Equatable, Sendable {
    /// `nil` → header shows `CM —` (no session or fetch failed).
    var cursorModelsUsedPercent: Double?
    var otherModelsUsedPercent: Double?
}

enum CursorQuotaLoader {
    static func load() async -> CursorQuotaSnapshot {
        guard let token = CursorStateDatabase.value(forKey: "cursorAuth/accessToken"), !token.isEmpty else {
            return CursorQuotaSnapshot(cursorModelsUsedPercent: nil, otherModelsUsedPercent: nil)
        }
        async let planUsage = CursorDashboardQuotaClient.fetchPlanUsage(accessToken: token)
        let quota = await CursorDashboardQuotaClient.fetch(
            accessToken: token,
            planUsageFallback: await planUsage
        )
        return CursorQuotaSnapshot(
            cursorModelsUsedPercent: quota.cursorModelsUsedPercent,
            otherModelsUsedPercent: quota.otherModelsUsedPercent
        )
    }
}
