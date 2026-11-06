import CryptoKit
import Foundation

/// Authenticated encryption for wrapped keys and secrets (ChaCha20-Poly1305).
/// Each seal uses a fresh random nonce (CryptoKit default); combined = nonce || ciphertext || tag.
public enum AkashicSealedBlob {
    public static func seal(plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try ChaChaPoly.seal(plaintext, using: key)
        return sealed.combined
    }

    public static func open(combined: Data, using key: SymmetricKey) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(box, using: key)
    }
}
