import CryptoKit
import Foundation

public enum CampusPlatform: String, CaseIterable, Codable, Sendable {
    case academic, chaoxing, campusSSO, secondClassroom
}

public enum ConnectionStatus: String, Codable, Sendable {
    case unbound, authenticating, connected, expired, actionRequired, temporarilyUnavailable
    case disconnecting, cleanupRequired
}

public struct ConnectionSnapshot: Sendable, Equatable, Identifiable {
    public let platform: CampusPlatform
    public let status: ConnectionStatus
    public let canConnect: Bool
    public let canDisconnect: Bool
    /// An opaque local token for the lifetime of a binding, used to discard rendered data when it changes.
    public let bindingID: String?
    public var id: CampusPlatform { platform }

    public init(platform: CampusPlatform, status: ConnectionStatus, canConnect: Bool, canDisconnect: Bool, bindingID: String? = nil) {
        self.platform = platform
        self.status = status
        self.canConnect = canConnect
        self.canDisconnect = canDisconnect
        self.bindingID = bindingID
    }
}

public enum CredentialPersistence: String, Codable, Sendable {
    case memoryOnly, keychain
}

/// A platform-scoped, opaque identifier for a single local binding of a remote user.
public struct AccountNamespace: Hashable, Codable, Sendable {
    public let platform: CampusPlatform
    public let opaqueID: String

    init(platform: CampusPlatform, remoteUserID: String) {
        self.platform = platform
        // Discard the random key so low-entropy campus IDs cannot be guessed from a registry or cache path.
        opaqueID = HMAC<SHA256>.authenticationCode(
            for: Data(remoteUserID.utf8), using: SymmetricKey(size: .bits256)
        ).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey { case platform, opaqueID }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(CampusPlatform.self, forKey: .platform)
        opaqueID = try container.decode(String.self, forKey: .opaqueID)
        guard opaqueID.utf8.count == 64, opaqueID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw DecodingError.dataCorruptedError(forKey: .opaqueID, in: container, debugDescription: "Invalid account namespace")
        }
    }
}

/// Only binding metadata belongs in the ordinary registry.
public struct ConnectionRecord: Codable, Equatable, Sendable {
    public let namespace: AccountNamespace
    public let status: ConnectionStatus
    public let persistence: CredentialPersistence

    public init(namespace: AccountNamespace, status: ConnectionStatus, persistence: CredentialPersistence) {
        self.namespace = namespace
        self.status = status
        self.persistence = persistence
    }
}
