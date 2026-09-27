import Combine
import Foundation

/// Cursor included spend, Models quota, and Grok Bot Sand — refreshed on a slow poll (~120s).
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
    /// Included spend still available (USD); `nil` → `$ —`.
    var cursorIncludedRemainingUSD: Double?
    /// Beyond-included spend when the API reports bonus usage.
    var cursorBonusSpendUSD: Double?
    /// `nil` → header shows `CM —`.
    var cursorModelsUsedPercent: Double?
    var otherModelsUsedPercent: Double?
    /// Grok Bot weekly Sand % used; `nil` → `BOT —`.
    var grokBotUsedPercent: Double?
}

enum CursorQuotaLoader {
    static func load() async -> CursorQuotaSnapshot {
        guard let token = CursorStateDatabase.value(forKey: "cursorAuth/accessToken"), !token.isEmpty else {
            return CursorQuotaSnapshot()
        }

        async let planTask = CursorPlanUsageClient.fetch(accessToken: token)
        async let sandTask = GrokBotSandUsageClient.fetchUsedPercent(accessToken: token)
        let plan = await planTask
        let sand = await sandTask

        let planUsage = plan?.planUsage ?? [:]
        let quota = await CursorDashboardQuotaClient.fetch(
            accessToken: token,
            planUsageFallback: planUsage
        )

        return CursorQuotaSnapshot(
            cursorIncludedRemainingUSD: plan?.includedRemainingUSD,
            cursorBonusSpendUSD: plan?.bonusSpendUSD,
            cursorModelsUsedPercent: quota.cursorModelsUsedPercent,
            otherModelsUsedPercent: quota.otherModelsUsedPercent,
            grokBotUsedPercent: sand
        )
    }
}
