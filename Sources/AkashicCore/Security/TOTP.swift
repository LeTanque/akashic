import CryptoKit
import Foundation

/// Time-based one-time passwords (RFC 6238). Algorithm: HMAC-SHA1, 30s window, 6 digits.
public enum TOTP {
    public static let defaultPeriod: UInt64 = 30
    public static let defaultDigits = 6

    public static func code(
        secret: Data,
        date: Date = Date(),
        period: UInt64 = defaultPeriod,
        digits: Int = defaultDigits,
        t0: UInt64 = 0
    ) -> String {
        let counter = UInt64(floor((date.timeIntervalSince1970 - TimeInterval(t0)) / TimeInterval(period)))
        return hotp(secret: secret, counter: counter, digits: digits)
    }

    /// Validates against current step ± `allowedDrift` periods (each side).
    public static func validate(
        secret: Data,
        code: String,
        date: Date = Date(),
        period: UInt64 = defaultPeriod,
        digits: Int = defaultDigits,
        allowedDrift: Int = 1
    ) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == digits, normalized.allSatisfy(\.isNumber) else { return false }
        let base = UInt64(floor((date.timeIntervalSince1970) / TimeInterval(period)))
        for delta in -allowedDrift ... allowedDrift {
            let ctr = Int64(base) + Int64(delta)
            guard ctr >= 0 else { continue }
            let expected = hotp(secret: secret, counter: UInt64(ctr), digits: digits)
            if expected == normalized { return true }
        }
        return false
    }

    private static func hotp(secret: Data, counter: UInt64, digits: Int) -> String {
        var ctr = counter.bigEndian
        let ctrData = Data(bytes: &ctr, count: MemoryLayout<UInt64>.size)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: ctrData, using: key)
        let h = Data(mac)
        let offset = Int(h[h.count - 1] & 0x0f)
        let binCode =
            (UInt32(h[offset]) & 0x7f) << 24
            | (UInt32(h[offset + 1]) & 0xff) << 16
            | (UInt32(h[offset + 2]) & 0xff) << 8
            | (UInt32(h[offset + 3]) & 0xff)
        let mod = UInt32(pow(10, Double(digits)))
        let num = binCode % mod
        return String(format: "%0*u", digits, num)
    }
}
