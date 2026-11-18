import Foundation

/// Each adapter defines its own authorization input and interaction flow.
public protocol ProviderAuthorization: Sendable {}

/// Sensitive, provider-owned material. Store it only in memory or through CredentialVault.
public struct ProviderSession: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let remoteUserID: String
    public let credential: Data

    public init(remoteUserID: String, credential: Data) {
        self.remoteUserID = remoteUserID
        self.credential = credential
    }

    public var description: String { "ProviderSession(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public enum ProviderFailure: Error, Equatable, Sendable {
    case expired, actionRequired, temporarilyUnavailable
}

/// Adapters isolate cookies/session state per call, check cancellation where practical,
/// and dispose of temporary auth and web state before returning, including on failure.
/// They return session material to the coordinator without writing shared or persistent state.
public protocol Provider: Sendable {
    func connect(using authorization: any ProviderAuthorization) async throws -> ProviderSession
    func probe(_ session: ProviderSession) async throws -> ProviderSession
    func refresh(_ session: ProviderSession) async throws -> ProviderSession
}
