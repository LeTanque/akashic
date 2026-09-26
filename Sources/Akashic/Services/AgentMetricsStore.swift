import Combine
import Foundation

/// Last ingested cloud-agent feed (`PUT /v1/agent-metrics`). In-memory only —
/// a payload older than ~7 minutes is treated as missing for display so CA
/// never shows a stale or invented zero. Lou’s Grok Bot routine can only
/// push about every 5 minutes; 7 minutes leaves slack between those beats.
@MainActor
final class AgentMetricsStore: ObservableObject {
    static let shared = AgentMetricsStore()
    /// Fresh window for CA / BOT. Longer than the ~5 minute push interval.
    static let staleAfter: TimeInterval = 7 * 60

    @Published private(set) var lastPayload: AgentMetricsPayload?

    func replace(_ payload: AgentMetricsPayload) {
        lastPayload = payload
    }

    func resetForTesting() {
        lastPayload = nil
    }

    /// `nil` means show `CA —`. A feed that recently sent `0` returns `0`.
    func displayedCloudAgentCount(at now: Date = Date()) -> Int? {
        guard let lastPayload, isFresh(lastPayload, at: now) else { return nil }
        return lastPayload.activeCloudAgents
    }

    func displayedBotCount(at now: Date = Date()) -> Int? {
        guard let lastPayload, isFresh(lastPayload, at: now) else { return nil }
        return lastPayload.activeBots
    }

    private func isFresh(_ payload: AgentMetricsPayload, at now: Date) -> Bool {
        now.timeIntervalSince(payload.updatedAt) < Self.staleAfter
    }
}

struct RunningCloudAgent: Codable, Equatable, Sendable {
    var id: String
    var title: String?
    var status: String?
}

struct AgentMetricsPayload: Equatable, Sendable {
    var activeCloudAgents: Int
    var runningCloudAgents: [RunningCloudAgent]
    var activeBots: Int?
    var updatedAt: Date

    enum ParseError: Error, Equatable {
        case invalidJSON
        case missingActiveCloudAgents
        case negativeActiveCloudAgents
        case missingUpdatedAt
        case invalidUpdatedAt
    }

    static func parse(_ data: Data) -> Result<AgentMetricsPayload, ParseError> {
        let decoder = JSONDecoder()
        guard let body = try? decoder.decode(AgentMetricsJSON.self, from: data) else {
            return .failure(.invalidJSON)
        }
        guard let active = body.activeCloudAgents else {
            return .failure(.missingActiveCloudAgents)
        }
        guard active >= 0 else {
            return .failure(.negativeActiveCloudAgents)
        }
        guard let rawUpdated = body.updatedAt else {
            return .failure(.missingUpdatedAt)
        }
        guard let updatedAt = ISO8601JSON.parse(rawUpdated) else {
            return .failure(.invalidUpdatedAt)
        }
        return .success(
            AgentMetricsPayload(
                activeCloudAgents: active,
                runningCloudAgents: body.runningCloudAgents ?? [],
                activeBots: body.activeBots,
                updatedAt: updatedAt
            )
        )
    }

    fileprivate struct AgentMetricsJSON: Decodable {
        var activeCloudAgents: Int?
        var runningCloudAgents: [RunningCloudAgent]?
        var activeBots: Int?
        var updatedAt: String?
    }
}

extension AgentMetricsPayload: Encodable {
    enum CodingKeys: String, CodingKey {
        case activeCloudAgents
        case runningCloudAgents
        case activeBots
        case updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeCloudAgents, forKey: .activeCloudAgents)
        try container.encode(runningCloudAgents, forKey: .runningCloudAgents)
        try container.encode(activeBots, forKey: .activeBots)
        try container.encode(ISO8601JSON.format(updatedAt), forKey: .updatedAt)
    }
}

extension AgentMetricsPayload.ParseError {
    var message: String {
        switch self {
        case .invalidJSON:
            return "invalid JSON body"
        case .missingActiveCloudAgents:
            return "activeCloudAgents required (int ≥ 0)"
        case .negativeActiveCloudAgents:
            return "activeCloudAgents must be ≥ 0"
        case .missingUpdatedAt:
            return "updatedAt required (ISO-8601)"
        case .invalidUpdatedAt:
            return "updatedAt must be ISO-8601"
        }
    }
}

enum ISO8601JSON {
    static func parse(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    static func format(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }
}
