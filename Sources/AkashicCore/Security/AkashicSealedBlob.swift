import CryptoKit
import Foundation

/// Authenticated encryption for wrapped keys and secrets (ChaCha20-Poly1305).
public enum AkashicSealedBlob {
    public static func seal(plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw AkashicCryptoError.invalidInput }
        return combined
    }

    public static func open(combined: Data, using key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(box, using: key)
    }
}
