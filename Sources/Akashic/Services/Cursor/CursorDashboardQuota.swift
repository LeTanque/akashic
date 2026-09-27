import Foundation

/// Dashboard-style included quota pools (Cursor Models / Other Models).
///
/// Primary source: `GET https://cursor.com/api/usage-summary` (unofficial; same JSON the Plan & Usage page uses).
/// Auth: `WorkosCursorSessionToken` cookie derived from the IDE access token — see `CursorSessionAuth`.
/// Fallback: `planUsage.autoPercentUsed` / `apiPercentUsed` on
/// `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
struct CursorDashboardQuota: Sendable, Equatable {
    var cursorModelsUsedPercent: Double?
    var otherModelsUsedPercent: Double?
}

enum CursorDashboardQuotaClient {
    static func fetch(accessToken: String, planUsageFallback: [String: Any]) async -> CursorDashboardQuota {
        if let fromSummary = await fetchUsageSummary(accessToken: accessToken) {
            return fromSummary
        }
        return quotaFromPlanUsage(planUsageFallback)
    }

    private static func fetchUsageSummary(accessToken: String) async -> CursorDashboardQuota? {
        guard let cookie = CursorSessionAuth.sessionCookie(accessToken: accessToken) else { return nil }

        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let plan = (json["individualUsage"] as? [String: Any])?["plan"] as? [String: Any]
            ?? (json["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any]
        guard let plan else { return nil }

        let auto = percentUsed(plan["autoPercentUsed"])
        let api = percentUsed(plan["apiPercentUsed"])
        if auto == nil, api == nil { return nil }

        return CursorDashboardQuota(
            cursorModelsUsedPercent: auto,
            otherModelsUsedPercent: api
        )
    }

    private static func quotaFromPlanUsage(_ planUsage: [String: Any]) -> CursorDashboardQuota {
        CursorDashboardQuota(
            cursorModelsUsedPercent: percentUsed(planUsage["autoPercentUsed"]),
            otherModelsUsedPercent: percentUsed(planUsage["apiPercentUsed"])
        )
    }

    /// Wire values are percentages on a 0–100 scale (e.g. 21.4 → 21% used), not fractions.
    static func percentUsed(_ value: Any?) -> Double? {
        guard let raw = number(value) else { return nil }
        let used = raw > 0 && raw <= 1.5 ? raw * 100 : raw
        return min(max(used, 0), 100)
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
