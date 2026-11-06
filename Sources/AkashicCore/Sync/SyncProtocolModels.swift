import Foundation

// MARK: - Phase 4 HTTP API (JSON shapes only — no networking)

/// Error envelope from the sync relay.
public struct SyncAPIErrorEnvelope: Codable, Sendable, Equatable {
    public var error: SyncAPIErrorBody

    enum CodingKeys: String, CodingKey {
        case error
    }
}

public struct SyncAPIErrorBody: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
}

public struct SyncRegisterAccountRequest: Codable, Sendable, Equatable {
    public var username: String
    public var authToken: String
    public var recoveryAuthToken: String?
    public var totpSecret: String
    public var deviceId: UUID
    public var deviceName: String
    public var devicePlatform: String
    public var escrowPasswordWrap: JSONValue?
    public var escrowRecoveryWrap: JSONValue?

    enum CodingKeys: String, CodingKey {
        case username
        case authToken = "auth_token"
        case recoveryAuthToken = "recovery_auth_token"
        case totpSecret = "totp_secret"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case devicePlatform = "device_platform"
        case escrowPasswordWrap = "escrow_password_wrap"
        case escrowRecoveryWrap = "escrow_recovery_wrap"
    }
}

public struct SyncRegisterAccountResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var deviceStatus: String

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case deviceStatus = "device_status"
    }
}

public struct SyncLoginRequest: Codable, Sendable, Equatable {
    public var username: String
    public var authToken: String
    public var totpCode: String
    public var deviceId: UUID
    public var deviceName: String
    public var devicePlatform: String

    enum CodingKeys: String, CodingKey {
        case username
        case authToken = "auth_token"
        case totpCode = "totp_code"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case devicePlatform = "device_platform"
    }
}

public struct SyncTokenPair: Codable, Sendable, Equatable {
    public var accessToken: String
    public var accessExpiresAt: String
    public var refreshToken: String
    public var refreshExpiresAt: String
    public var sessionId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessExpiresAt = "access_expires_at"
        case refreshToken = "refresh_token"
        case refreshExpiresAt = "refresh_expires_at"
        case sessionId = "session_id"
    }
}

public struct SyncLoginResponse: Codable, Sendable, Equatable {
    public var accountId: String
    public var deviceStatus: String
    public var tokens: SyncTokenPair

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case deviceStatus = "device_status"
        case tokens
    }
}

/// Login response when device approval is pending (HTTP 423).
public struct SyncLoginPendingBody: Codable, Sendable, Equatable {
    public var error: SyncAPIErrorBody
    public var accountId: String
    public var deviceStatus: String

    enum CodingKeys: String, CodingKey {
        case error
        case accountId = "account_id"
        case deviceStatus = "device_status"
    }
}

public struct SyncRefreshRequest: Codable, Sendable, Equatable {
    public var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

public struct SyncRefreshResponse: Codable, Sendable, Equatable {
    public var tokens: SyncTokenPair
}

public struct SyncDeviceInfo: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var platform: String
    public var status: String
    public var createdAt: String
    public var lastSigninAt: String?
    public var lastSigninIP: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case platform
        case status
        case createdAt = "created_at"
        case lastSigninAt = "last_signin_at"
        case lastSigninIP = "last_signin_ip"
    }
}

public struct SyncListDevicesResponse: Codable, Sendable, Equatable {
    public var devices: [SyncDeviceInfo]
}

public struct SyncRecoverApproveRequest: Codable, Sendable, Equatable {
    public var username: String
    public var recoveryAuthToken: String
    public var totpCode: String

    enum CodingKeys: String, CodingKey {
        case username
        case recoveryAuthToken = "recovery_auth_token"
        case totpCode = "totp_code"
    }
}

public struct SyncPushBatchRequest: Codable, Sendable, Equatable {
    public var batchId: UUID
    public var originDeviceId: UUID
    public var batchHLC: HybridLogicalClock
    public var ciphertextB64: String

    enum CodingKeys: String, CodingKey {
        case batchId = "batch_id"
        case originDeviceId = "origin_device_id"
        case batchHLC = "batch_hlc"
        case ciphertextB64 = "ciphertext_b64"
    }
}

public struct SyncPushBatchResponse: Codable, Sendable, Equatable {
    public var seq: Int64
    public var duplicate: Bool
}

public struct SyncPulledBatch: Codable, Sendable, Equatable {
    public var seq: Int64
    public var batchId: UUID
    public var originDeviceId: UUID
    public var batchHLC: HybridLogicalClock
    public var ciphertextB64: String
    public var sizeBytes: Int
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case seq
        case batchId = "batch_id"
        case originDeviceId = "origin_device_id"
        case batchHLC = "batch_hlc"
        case ciphertextB64 = "ciphertext_b64"
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
    }
}

public struct SyncPullResponse: Codable, Sendable, Equatable {
    public var batches: [SyncPulledBatch]
    public var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case batches
        case hasMore = "has_more"
    }
}

public struct SyncAckRequest: Codable, Sendable, Equatable {
    public var lastAckSeq: Int64

    enum CodingKeys: String, CodingKey {
        case lastAckSeq = "last_ack_seq"
    }
}

public struct SyncEscrowPutRequest: Codable, Sendable, Equatable {
    public var passwordWrap: JSONValue
    public var recoveryWrap: JSONValue

    enum CodingKeys: String, CodingKey {
        case passwordWrap = "password_wrap"
        case recoveryWrap = "recovery_wrap"
    }
}

public struct SyncEscrowGetResponse: Codable, Sendable, Equatable {
    public var passwordWrap: JSONValue
    public var recoveryWrap: JSONValue

    enum CodingKeys: String, CodingKey {
        case passwordWrap = "password_wrap"
        case recoveryWrap = "recovery_wrap"
    }
}

public struct SyncTLSPinResponse: Codable, Sendable, Equatable {
    public var spkiSha256B64url: String
    public var pinFormat: String

    enum CodingKeys: String, CodingKey {
        case spkiSha256B64url = "spki_sha256_b64url"
        case pinFormat = "pin_format"
    }
}

public struct SyncStatusOK: Codable, Sendable, Equatable {
    public var status: String
}

// MARK: - Escrow JSON placeholders

/// Loose JSON value for opaque escrow blobs (`encode(to:)` / `init(from:)`).
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}
