// SPDX-License-Identifier: Apache-2.0
import Foundation
import Security

enum EnrollmentStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "org.meshcentral.iosagent.demo") + ".enrollment",
         kSecAttrAccount as String: "default"]
    }
    static func load() throws -> SavedEnrollment? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AgentError.keychain(status) }
        let profile = try JSONDecoder().decode(SavedEnrollment.self, from: data)
        _ = try profile.validated()
        return profile
    }
    static func save(_ profile: SavedEnrollment) throws {
        _ = try profile.validated()
        let data = try JSONEncoder().encode(profile)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AgentError.keychain(status) }
    }
    static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AgentError.keychain(status) }
    }
}
