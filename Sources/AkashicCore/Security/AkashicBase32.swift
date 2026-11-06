import Foundation

/// RFC 4648 Base32 (alphabet A–Z2–7), no `=` padding in encoded output.
///
/// Uses a `UInt64` bit buffer with masking after each emitted quintet so long inputs and decode
/// stays well-defined. Independent checks show encoder output matches reference Base32 for standard
/// vectors (including 19- and 20-byte secrets); the `UInt64` path is defensive hardening.
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
        guard !data.isEmpty else { return "" }
        var buffer: UInt64 = 0
        var bits = 0
        var output = [Character]()

        for byte in data {
            buffer = (buffer << 8) | UInt64(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                let idx = Int((buffer >> bits) & 0x1F)
                output.append(alphabet[idx])
                buffer = bits > 0 ? (buffer & ((1 << bits) - 1)) : 0
            }
        }
        if bits > 0 {
            let idx = Int((buffer << (5 - bits)) & 0x1F)
            output.append(alphabet[idx])
        }
        return String(output)
    }

    public static func decode(_ string: String) throws -> Data {
        var cleaned = string.uppercased().filter { !$0.isWhitespace }
        while cleaned.last == "=" {
            cleaned.removeLast()
        }
        guard !cleaned.isEmpty else { throw AkashicCryptoError.invalidInput }

        var buffer: UInt64 = 0
        var bits = 0
        var out = [UInt8]()

        for c in cleaned {
            guard let v = charToIndex[c] else { throw AkashicCryptoError.invalidInput }
            buffer = (buffer << 5) | UInt64(v)
            bits += 5
            while bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xFF))
                buffer = bits > 0 ? (buffer & ((1 << bits) - 1)) : 0
            }
        }
        return Data(out)
    }
}
