import AkashicCore
import Foundation
import LocalAuthentication
import Security

enum AkashicKeychain {
    private static let service = "com.akashic.database.dataKey"

    static func saveDataKeyForBiometry(_ key: Data) throws {
        try deleteDataKey()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryCurrentSet],
            &error
        ) else {
            _ = error?.takeRetainedValue()
            throw AkashicCryptoError.unsupportedPlatform
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "primary",
            kSecValueData as String: key,
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AkashicCryptoError.authenticationFailed }
    }

    static func readDataKeyWithBiometry(reason: String) async throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "primary",
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AkashicCryptoError.authenticationFailed)
                }
            }
        }
    }

    static func deleteDataKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "primary",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
