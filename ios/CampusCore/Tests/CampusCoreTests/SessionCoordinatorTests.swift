import CampusCore
import Foundation
import Testing

@Test func registeredProviderCanConnectWithExplicitKeychainOptIn() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()

    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)

    let snapshot = try #require(try await core.snapshot().first { $0.platform == .academic })
    #expect(snapshot.status == .connected)
    #expect(snapshot.canDisconnect)
    let record = try #require(try fixture.registry.record(for: .academic))
    #expect(try fixture.vault.load(in: record.namespace) == SyntheticProvider.session)
}

@Test func disconnectRetriesCleanupAfterRestartWithoutRestoringSession() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let record = try #require(try fixture.registry.record(for: .academic))
    let cached = CachedValue(data: Data([8]), updatedAt: .distantPast)
    try fixture.cache.save(cached, for: "sample", in: record.namespace)

    fixture.vault.failNextRemoval()
    await #expect(throws: SyntheticStorageFailure.self) { try await core.disconnect(.academic) }
    #expect(try fixture.cache.value(for: "sample", in: record.namespace) == cached)

    let restarted = fixture.coordinator()
    let pending = try #require(try await restarted.snapshot().first { $0.platform == .academic })
    #expect(pending.status == .cleanupRequired)
    #expect(pending.canDisconnect && !pending.canConnect)
    try await restarted.disconnect(.academic)
    try await restarted.disconnect(.academic)

    let disconnected = try await restarted.snapshot().first { $0.platform == .academic }
    #expect(disconnected?.status == .unbound)
    #expect(try fixture.vault.load(in: record.namespace) == nil)
    #expect(try fixture.cache.value(for: "sample", in: record.namespace) == nil)
    #expect(try fixture.registry.record(for: .academic) == nil)
}

@Test func disconnectPurgesLocalSessionEvenWhenTheCleanupMarkerCannotBeSaved() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let registry = FailingRegistry(base: fixture.registry)
    let core = LocalSessionCoordinator(providers: [.academic: fixture.provider], registry: registry, vault: fixture.vault, cache: fixture.cache)
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let record = try #require(try registry.record(for: .academic))
    registry.failNextSave()

    try await core.disconnect(.academic)

    #expect(try registry.record(for: .academic) == nil)
    #expect(try fixture.vault.load(in: record.namespace) == nil)
}

@Test func expirationTriggersOneRefreshAndPersistsRotatedCredentials() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let record = try #require(try fixture.registry.record(for: .academic))
    await fixture.provider.setProbeFailure(.expired)

    #expect(try await core.probe(.academic) == .expired)
    #expect(await fixture.provider.refreshCount == 0)
    #expect(try await core.refresh(.academic) == .connected)
    #expect(await fixture.provider.refreshCount == 1)
    #expect(try fixture.vault.load(in: record.namespace) == SyntheticProvider.rotatedSession)
}

@Test func offlineRefreshKeepsCachedDataAndDoesNotAttemptAuthentication() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization())
    let record = try #require(try fixture.registry.record(for: .academic))
    let cached = CachedValue(data: Data([9]), updatedAt: .distantPast)
    try fixture.cache.save(cached, for: "sample", in: record.namespace)
    await fixture.provider.setProbeFailure(.temporarilyUnavailable)

    #expect(try await core.refresh(.academic) == .temporarilyUnavailable)
    #expect(await fixture.provider.refreshCount == 0)
    #expect(try fixture.cache.value(for: "sample", in: record.namespace) == cached)
    #expect(try fixture.vault.load(in: record.namespace) == nil)
    let restarted = try await fixture.coordinator().snapshot().first { $0.platform == .academic }
    #expect(restarted?.status == .actionRequired)
}

@Test func overlappingRefreshRequestsShareOneProviderRecovery() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization())
    let gate = RequestGate()
    await fixture.provider.setProbeFailure(.expired)
    await fixture.provider.suspendRefresh(at: gate)
    let first = Task { try await core.refresh(.academic) }
    await gate.waitUntilEntered()

    let followers = (0..<8).map { _ in Task { try await core.refresh(.academic) } }
    // Keep the interrupted provider round trip suspended while the followers reach the actor.
    try await Task.sleep(for: .milliseconds(100))
    await gate.release()

    #expect(try await first.value == .connected)
    for follower in followers { #expect(try await follower.value == .connected) }
    #expect(await fixture.provider.refreshCount == 1)
    #expect(await fixture.provider.probeCount == 1)
}

@Test func lateRefreshCannotWriteAfterDisconnectAndRebind() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let first = try #require(try fixture.registry.record(for: .academic))
    let gate = RequestGate()
    await fixture.provider.setProbeFailure(.expired)
    await fixture.provider.suspendRefresh(at: gate)
    let stale = Task { try await core.refresh(.academic) }
    await gate.waitUntilEntered()

    try await core.disconnect(.academic)
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let second = try #require(try fixture.registry.record(for: .academic))
    await gate.release()

    await #expect(throws: SessionFailure.superseded) { _ = try await stale.value }
    #expect(first.namespace != second.namespace)
    #expect(try fixture.vault.load(in: first.namespace) == nil)
    #expect(try fixture.vault.load(in: second.namespace) == SyntheticProvider.session)
    #expect(try fixture.registry.record(for: .academic) == second)
}

@Test func corruptRegistryRecordDoesNotHideOtherPlatforms() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = fixture.coordinator()
    try await core.connect(.academic, using: SyntheticAuthorization())
    try Data([0xff]).write(to: fixture.root.appending(path: "registry/chaoxing.json"))

    let snapshots = try await core.snapshot()
    #expect(snapshots.first { $0.platform == .academic }?.status == .connected)
    let corrupt = try #require(snapshots.first { $0.platform == .chaoxing })
    #expect(corrupt.status == .temporarilyUnavailable)
    #expect(!corrupt.canConnect && !corrupt.canDisconnect)
}

@Test func cacheAndVaultAreIsolatedByPlatformAndBinding() async throws {
    let fixture = try Fixture()
    defer { fixture.removeFiles() }
    let core = LocalSessionCoordinator(
        providers: [.academic: fixture.provider, .chaoxing: SyntheticProvider()],
        registry: fixture.registry, vault: fixture.vault, cache: fixture.cache
    )
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    try await core.connect(.chaoxing, using: SyntheticAuthorization(), persistence: .keychain)
    let academic = try #require(try fixture.registry.record(for: .academic))
    let chaoxing = try #require(try fixture.registry.record(for: .chaoxing))
    let value = CachedValue(data: Data([7]), updatedAt: .distantPast)
    let key = "courses"
    try fixture.cache.save(value, for: key, in: academic.namespace)
    #expect(try fixture.cache.value(for: key, in: chaoxing.namespace) == nil)
    try fixture.cache.save(value, for: key, in: chaoxing.namespace)

    try await core.disconnect(.academic)
    await fixture.provider.setRemoteUserID("synthetic-account-b")
    try await core.connect(.academic, using: SyntheticAuthorization(), persistence: .keychain)
    let otherUser = try #require(try fixture.registry.record(for: .academic))

    #expect(academic.namespace != otherUser.namespace)
    #expect(try fixture.cache.value(for: key, in: otherUser.namespace) == nil)
    #expect(try fixture.cache.value(for: key, in: chaoxing.namespace) == value)
    #expect(try fixture.vault.load(in: chaoxing.namespace) == SyntheticProvider.session)
    let registryData = try Data(contentsOf: fixture.root.appending(path: "registry/academic.json"))
    #expect(!String(decoding: registryData, as: UTF8.self).contains("synthetic-account-b"))
}

private actor RequestGate {
    private var entry: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if blocked != nil { return }
        await withCheckedContinuation { entry = $0 }
    }

    func pause() async {
        await withCheckedContinuation {
            blocked = $0
            entry?.resume()
            entry = nil
        }
    }

    func release() {
        blocked?.resume()
        blocked = nil
    }
}

private struct Fixture {
    let root: URL
    let registry: FileConnectionRegistry
    let cache: FileCampusCache
    let vault = SyntheticVault()
    let provider = SyntheticProvider()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        registry = try FileConnectionRegistry(directory: root.appending(path: "registry"))
        cache = try FileCampusCache(directory: root.appending(path: "cache"))
    }

    func coordinator() -> LocalSessionCoordinator {
        LocalSessionCoordinator(providers: [.academic: provider], registry: registry, vault: vault, cache: cache)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private struct SyntheticAuthorization: ProviderAuthorization {}

private actor SyntheticProvider: Provider {
    static let session = ProviderSession(remoteUserID: "synthetic-account-a", credential: Data([1, 2, 3]))

    private var remoteUserID = SyntheticProvider.session.remoteUserID

    func setRemoteUserID(_ id: String) { remoteUserID = id }

    func connect(using authorization: any ProviderAuthorization) async throws -> ProviderSession {
        ProviderSession(remoteUserID: remoteUserID, credential: Self.session.credential)
    }

    static let rotatedSession = ProviderSession(remoteUserID: "synthetic-account-a", credential: Data([4, 5, 6]))
    private var probeFailure: ProviderFailure?
    private var refreshGate: RequestGate?
    private(set) var refreshCount = 0
    private(set) var probeCount = 0

    func setProbeFailure(_ failure: ProviderFailure) { probeFailure = failure }
    func suspendRefresh(at gate: RequestGate) { refreshGate = gate }

    func probe(_ session: ProviderSession) async throws -> ProviderSession {
        probeCount += 1
        if let probeFailure { throw probeFailure }
        return session
    }

    func refresh(_ session: ProviderSession) async throws -> ProviderSession {
        refreshCount += 1
        if let gate = refreshGate {
            refreshGate = nil
            await gate.pause()
        }
        probeFailure = nil
        return Self.rotatedSession
    }
}

private enum SyntheticStorageFailure: Error { case removal, save }

private final class FailingRegistry: ConnectionRegistry, @unchecked Sendable {
    private let base: FileConnectionRegistry
    private let lock = NSLock()
    private var failSave = false

    init(base: FileConnectionRegistry) { self.base = base }

    func failNextSave() { lock.withLock { failSave = true } }

    func record(for platform: CampusPlatform) throws -> ConnectionRecord? { try base.record(for: platform) }

    func save(_ record: ConnectionRecord) throws {
        try lock.withLock {
            if failSave {
                failSave = false
                throw SyntheticStorageFailure.save
            }
            try base.save(record)
        }
    }

    func remove(for platform: CampusPlatform) throws { try base.remove(for: platform) }
}

private final class SyntheticVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [AccountNamespace: ProviderSession] = [:]
    private var failRemoval = false

    func failNextRemoval() { lock.withLock { failRemoval = true } }

    func load(in namespace: AccountNamespace) throws -> ProviderSession? {
        lock.withLock { sessions[namespace] }
    }

    func save(_ session: ProviderSession, in namespace: AccountNamespace) throws {
        lock.withLock { sessions[namespace] = session }
    }

    func remove(in namespace: AccountNamespace) throws {
        try lock.withLock {
            if failRemoval {
                failRemoval = false
                throw SyntheticStorageFailure.removal
            }
            sessions.removeValue(forKey: namespace)
        }
    }
}
