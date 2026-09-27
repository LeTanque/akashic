import Foundation

/// Builds the dashboard session cookie Cursor's website expects (`WorkosCursorSessionToken`).
/// Same scheme as MetricsWidget: `{userId}%3A%3A{accessToken}` with `userId` from the JWT `sub` claim.
enum CursorSessionAuth {
    static func sessionCookie(accessToken: String) -> String? {
        guard let userID = userID(fromJWT: accessToken) else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }

    static func userID(fromJWT token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              !subject.isEmpty
        else { return nil }

        let parts = subject.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2, !parts[1].isEmpty { return parts[1] }
        return parts.first
    }
}
