import Foundation

public enum AkashicCryptoError: Error, Equatable, Sendable {
    case invalidInput
    case keyDerivationFailed
    case authenticationFailed
    case unsupportedPlatform
    case randomGenerationFailed
}
