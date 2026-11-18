import Foundation
import Security

public enum KeychainFailure: Error, Equatable, Sendable {
    case operationFailed(OSStatus)
    case invalidPayload
}

public struct KeychainCredentialVault: CredentialVault {
    private let service: String

    public init(service: String) { self.service = service }

    public func load(in namespace: AccountNamespace) throws -> ProviderSession? {
        var request = query(for: namespace)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try requireSuccess(status)
        guard let data = item as? Data,
              let session = try? JSONDecoder().decode(ProviderSession.self, from: data) else {
            throw KeychainFailure.invalidPayload
        }
        return session
    }

    public func save(_ session: ProviderSession, in namespace: AccountNamespace) throws {
        let request = query(for: namespace)
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(request as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let item = request.merging(values) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                try requireSuccess(SecItemUpdate(request as CFDictionary, values as CFDictionary))
            } else {
                try requireSuccess(addStatus)
            }
        } else {
            try requireSuccess(status)
        }
    }

    public func remove(in namespace: AccountNamespace) throws {
        let status = SecItemDelete(query(for: namespace) as CFDictionary)
        if status != errSecItemNotFound { try requireSuccess(status) }
    }

    private func requireSuccess(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainFailure.operationFailed(status) }
    }

    private func query(for namespace: AccountNamespace) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + "." + namespace.platform.rawValue,
            kSecAttrAccount as String: namespace.opaqueID,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
