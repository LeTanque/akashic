import Foundation

/// `GetCurrentPeriodUsage` — included spend remaining (MetricsWidget `CursorUsageClient` semantics)
/// plus raw `planUsage` for CM/OM fallback.
enum CursorPlanUsageClient {
    struct Response: Sendable {
        var planUsage: [String: Any]
        /// USD still available in the included pool this period; `nil` when unknown.
        var includedRemainingUSD: Double?
        /// USD beyond included (`bonusSpend`), when present and > 0.
        var bonusSpendUSD: Double?
    }

    static func fetch(accessToken: String) async -> Response? {
        var request = URLRequest(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let planUsage = json["planUsage"] as? [String: Any] ?? [:]
        let included = cents(planUsage["includedSpend"])
        let extraSpend = cents(planUsage["bonusSpend"])
        let limit = cents(planUsage["limit"])
        let remaining = cents(planUsage["remaining"])

        var includedRemaining: Double?
        if let limit, limit > 0 {
            includedRemaining = includedRemaining(
                limit: limit,
                includedSpend: included,
                apiRemaining: remaining
            )
        }

        let bonus: Double? = {
            guard let extraSpend, extraSpend > 0 else { return nil }
            return extraSpend
        }()

        return Response(
            planUsage: planUsage,
            includedRemainingUSD: includedRemaining,
            bonusSpendUSD: bonus
        )
    }

    /// Included quota still available this period (USD). Prefers API `remaining` when it matches limit − used.
    private static func includedRemaining(
        limit: Double,
        includedSpend: Double?,
        apiRemaining: Double?
    ) -> Double {
        let fromIncluded = max(0, limit - (includedSpend ?? 0))
        guard let apiRemaining else { return fromIncluded }
        let tolerance = 0.02
        if abs(apiRemaining - fromIncluded) <= tolerance {
            return min(limit, max(0, apiRemaining))
        }
        if includedSpend == nil, apiRemaining >= 0, apiRemaining <= limit {
            return apiRemaining
        }
        return fromIncluded
    }

    private static func cents(_ value: Any?) -> Double? {
        guard let number = number(value) else { return nil }
        return number / 100.0
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
