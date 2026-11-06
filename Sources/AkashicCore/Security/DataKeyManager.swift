import CryptoKit
import Foundation
import Security

/// Random 256-bit DB key, wrapped by password KDF and recovery-code KDF. Password changes only re-wrap.
public enum DataKeyManager {
    public static let dataKeyByteCount = 32

    public static func randomDataKey() throws -> Data {
        try randomBytes(count: dataKeyByteCount)
    }

    /// Display form: six groups of five Base32 characters (30 payload characters plus dashes).
    public static func randomRecoveryCode() throws -> String {
        // 30 base32 chars = 150 bits; encode 19 bytes (152 bits) then take first 30 chars.
        let raw = try randomBytes(count: 19)
        let encoded = AkashicBase32.encode(raw)
        guard encoded.count >= 30 else { throw AkashicCryptoError.randomGenerationFailed }
        let trimmed = String(encoded.prefix(30))
        return formatRecoveryCode(display: trimmed)
    }

    public static func normalizeRecoveryCode(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func formatRecoveryCode(display: String) -> String {
        let cleaned = normalizeRecoveryCode(display)
        let chunks = stride(from: 0, to: cleaned.count, by: 5).map { i -> String in
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: min(5, cleaned.distance(from: start, to: cleaned.endIndex)))
            return String(cleaned[start ..< end])
        }
        return chunks.joined(separator: "-")
    }

    public static func generateMetadata(
        username: String,
        password: String,
        dataKey: Data? = nil,
        recoveryCodeDisplay: String? = nil
    ) throws -> (metadata: LocalSecurityMetadata, recoveryDisplay: String, totpSecretBase32: String, otpauthURI: String) {
        let dataKey = try dataKey ?? randomDataKey()
        let passwordSalt = try randomBytes(count: 16)
        let passwordWrapped = try wrapDataKey(dataKey, password: passwordData(from: password), salt: passwordSalt)

        let recoveryDisplay = try recoveryCodeDisplay ?? randomRecoveryCode()
        let recoveryNormalized = normalizeRecoveryCode(recoveryDisplay)
        guard recoveryNormalized.count == 30 else { throw AkashicCryptoError.invalidInput }

        let recoverySalt = try randomBytes(count: 16)
        let recoveryWrapped = try wrapDataKey(
            dataKey,
            password: Data(recoveryNormalized.utf8),
            salt: recoverySalt
        )

        let totpRaw = try randomBytes(count: 20)
        let totpBase32 = AkashicBase32.encode(Data(totpRaw))
        let sk = SymmetricKey(data: dataKey)
        let totpSealed = try AkashicSealedBlob.seal(plaintext: Data(totpRaw), using: sk)

        let otpauth = Self.otpauthURI(username: username, secretBase32: totpBase32)

        let metadata = LocalSecurityMetadata(
            formatVersion: LocalSecurityMetadata.currentFormatVersion,
            username: username,
            passwordSalt: passwordSalt,
            passwordIterations: AkashicPBKDF2.defaultIterationCount,
            passwordWrappedDataKey: passwordWrapped,
            recoverySalt: recoverySalt,
            recoveryIterations: AkashicPBKDF2.defaultIterationCount,
            recoveryWrappedDataKey: recoveryWrapped,
            totpSecretSealed: totpSealed
        )
        return (metadata, recoveryDisplay, totpBase32, otpauth)
    }

    public static func otpauthURI(username: String, secretBase32: String) -> String {
        let encUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encSecret = secretBase32.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secretBase32
        return "otpauth://totp/Akashic:\(encUser)?secret=\(encSecret)&issuer=Akashic&algorithm=SHA1&digits=6&period=30"
    }

    public static func unwrapDataKey(metadata: LocalSecurityMetadata, password: String) throws -> Data {
        try unwrap(
            wrapped: metadata.passwordWrappedDataKey,
            password: passwordData(from: password),
            salt: metadata.passwordSalt,
            iterations: metadata.passwordIterations
        )
    }

    public static func unwrapDataKey(metadata: LocalSecurityMetadata, recoveryCode: String) throws -> Data {
        let normalized = normalizeRecoveryCode(recoveryCode)
        return try unwrap(
            wrapped: metadata.recoveryWrappedDataKey,
            password: Data(normalized.utf8),
            salt: metadata.recoverySalt,
            iterations: metadata.recoveryIterations
        )
    }

    /// Password change: re-wrap only; DB file passphrase unchanged.
    public static func changePassword(
        metadata: LocalSecurityMetadata,
        oldPassword: String,
        newPassword: String
    ) throws -> LocalSecurityMetadata {
        let dataKey = try unwrapDataKey(metadata: metadata, password: oldPassword)
        let newSalt = try randomBytes(count: 16)
        let newWrapped = try wrapDataKey(dataKey, password: passwordData(from: newPassword), salt: newSalt)
        var updated = metadata
        updated.passwordSalt = newSalt
        updated.passwordIterations = AkashicPBKDF2.defaultIterationCount
        updated.passwordWrappedDataKey = newWrapped
        return updated
    }

    public static func openTOTPSecret(metadata: LocalSecurityMetadata, dataKey: Data) throws -> Data {
        let sk = SymmetricKey(data: dataKey)
        return try AkashicSealedBlob.open(combined: metadata.totpSecretSealed, using: sk)
    }

    // MARK: - Private

    private static func passwordData(from password: String) -> Data {
        Data(password.utf8)
    }

    private static func wrapDataKey(_ dataKey: Data, password: Data, salt: Data) throws -> Data {
        let derived = try AkashicPBKDF2.deriveKey(
            password: password,
            salt: salt,
            iterations: AkashicPBKDF2.defaultIterationCount,
            keyByteCount: 32
        )
        let sk = SymmetricKey(data: derived)
        return try AkashicSealedBlob.seal(plaintext: dataKey, using: sk)
    }

    private static func unwrap(wrapped: Data, password: Data, salt: Data, iterations: Int) throws -> Data {
        let derived = try AkashicPBKDF2.deriveKey(
            password: password,
            salt: salt,
            iterations: iterations,
            keyByteCount: 32
        )
        let sk = SymmetricKey(data: derived)
        return try AkashicSealedBlob.open(combined: wrapped, using: sk)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw AkashicCryptoError.randomGenerationFailed }
        return Data(bytes)
    }
}
