import Foundation

/// RFC 4648 base32 (no padding) encode/decode for TOTP secrets and recovery codes.
public enum AkashicBase32 {
    private static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static let charToIndex: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() {
            map[c] = i
        }
        return map
    }()

    public static func encode(_ data: Data) -> String {
        var bits = 0
        var value = 0
        var output = [Character]()
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                let idx = (value >> bits) & 31
                output.append(alphabet[idx])
            }
        }
        if bits > 0 {
            let idx = (value << (5 - bits)) & 31
            output.append(alphabet[idx])
        }
        return String(output)
    }

    public static func decode(_ string: String) throws -> Data {
        let cleaned = string.uppercased().filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { throw AkashicCryptoError.invalidInput }
        var bits = 0
        var value = 0
        var out = [UInt8]()
        for c in cleaned {
            guard let idx = charToIndex[c] else { throw AkashicCryptoError.invalidInput }
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xff))
            }
        }
        return Data(out)
    }
}
