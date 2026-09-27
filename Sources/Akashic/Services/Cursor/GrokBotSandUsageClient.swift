import Foundation

/// Grok Bot weekly Sand allowance (`GetSandUsageStatus`), ported from MetricsWidget `GrokBotUsageClient`.
enum GrokBotSandUsageClient {
    /// Percent **used** this week; `nil` when session missing, no allowance, or fetch failed.
    static func fetchUsedPercent(accessToken: String) async -> Double? {
        var request = URLRequest(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
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

        if json["hasNonZeroIncludedLimit"] as? Bool == false {
            return nil
        }

        guard let used = number(json["usagePercent"]) else { return nil }
        return min(100, max(0, used))
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
