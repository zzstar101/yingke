import CryptoKit
import Foundation

/// Implementations must be thread-safe. Mutations complete synchronously so that
/// the coordinator can update storage without suspending between generation checks.
public protocol ConnectionRegistry: Sendable {
    func record(for platform: CampusPlatform) throws -> ConnectionRecord?
    func save(_ record: ConnectionRecord) throws
    func remove(for platform: CampusPlatform) throws
}

public protocol CredentialVault: Sendable {
    func load(in namespace: AccountNamespace) throws -> ProviderSession?
    func save(_ session: ProviderSession, in namespace: AccountNamespace) throws
    func remove(in namespace: AccountNamespace) throws
}

public struct CachedValue: Codable, Equatable, Sendable {
    public let data: Data
    public let updatedAt: Date

    public init(data: Data, updatedAt: Date) {
        self.data = data
        self.updatedAt = updatedAt
    }
}

/// Store normalized campus data only. Credentials belong in CredentialVault.
public protocol CampusCache: Sendable {
    func value(for key: String, in namespace: AccountNamespace) throws -> CachedValue?
    func save(_ value: CachedValue, for key: String, in namespace: AccountNamespace) throws
    func removeAll(in namespace: AccountNamespace) throws
}

public struct FileConnectionRegistry: ConnectionRegistry {
    private let files: PrivateFiles

    public init(directory: URL) throws {
        files = try PrivateFiles(directory: directory)
    }

    public func record(for platform: CampusPlatform) throws -> ConnectionRecord? {
        guard let record = try files.load(ConnectionRecord.self, from: url(for: platform)) else { return nil }
        guard record.namespace.platform == platform else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    public func save(_ record: ConnectionRecord) throws {
        try files.save(record, to: url(for: record.namespace.platform))
    }

    public func remove(for platform: CampusPlatform) throws {
        try files.remove(url(for: platform))
    }

    private func url(for platform: CampusPlatform) -> URL {
        files.directory.appending(path: platform.rawValue + ".json", directoryHint: .notDirectory)
    }
}

public struct FileCampusCache: CampusCache {
    private let files: PrivateFiles

    public init(directory: URL) throws {
        files = try PrivateFiles(directory: directory)
    }

    public func value(for key: String, in namespace: AccountNamespace) throws -> CachedValue? {
        try files.load(CachedValue.self, from: url(for: key, in: namespace))
    }

    public func save(_ value: CachedValue, for key: String, in namespace: AccountNamespace) throws {
        try files.makeDirectory(accountDirectory(namespace))
        try files.save(value, to: url(for: key, in: namespace))
    }

    public func removeAll(in namespace: AccountNamespace) throws {
        try files.remove(accountDirectory(namespace))
    }

    private func accountDirectory(_ namespace: AccountNamespace) -> URL {
        files.directory.appending(path: namespace.platform.rawValue, directoryHint: .isDirectory)
            .appending(path: namespace.opaqueID, directoryHint: .isDirectory)
    }

    private func url(for key: String, in namespace: AccountNamespace) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return accountDirectory(namespace).appending(path: digest + ".json", directoryHint: .notDirectory)
    }
}

struct PrivateFiles: Sendable {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try makeDirectory(directory)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
    }

    func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try JSONEncoder().encode(value).write(to: url, options: options)
    }

    func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Repeated cleanup of an already absent item succeeds.
        }
    }
}
