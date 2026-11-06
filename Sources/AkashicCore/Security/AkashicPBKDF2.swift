import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256 key stretching (CommonCrypto). Params documented in `docs/sync-design.md`.
public enum AkashicPBKDF2 {
    /// OWASP-recommended iteration count for PBKDF2-HMAC-SHA256 (2023 guidance).
    public static let defaultIterationCount = 600_000

    public static func deriveKey(
        password: Data,
        salt: Data,
        iterations: Int = defaultIterationCount,
        keyByteCount: Int = 32
    ) throws -> Data {
        guard iterations > 0, keyByteCount > 0 else { throw AkashicCryptoError.invalidInput }
        var derived = Data(count: keyByteCount)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedPtr in
            guard let derivedBase = derivedPtr.baseAddress else { return Int32(kCCParamError) }
            return password.withUnsafeBytes { passwordPtr in
                guard let passwordBase = passwordPtr.baseAddress else { return Int32(kCCParamError) }
                return salt.withUnsafeBytes { saltPtr in
                    guard let saltBase = saltPtr.baseAddress else { return Int32(kCCParamError) }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBase.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBase.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBase.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw AkashicCryptoError.keyDerivationFailed }
        return derived
    }
}
