import Foundation

public protocol SessionCoordinator: Sendable {
    func snapshot() async throws -> [ConnectionSnapshot]
    func connect(_ platform: CampusPlatform, using authorization: any ProviderAuthorization, persistence: CredentialPersistence) async throws
    func probe(_ platform: CampusPlatform) async throws -> ConnectionStatus
    func refresh(_ platform: CampusPlatform) async throws -> ConnectionStatus
    func disconnect(_ platform: CampusPlatform) async throws
}

public extension SessionCoordinator {
    func connect(_ platform: CampusPlatform, using authorization: any ProviderAuthorization) async throws {
        try await connect(platform, using: authorization, persistence: .memoryOnly)
    }
}

public enum SessionFailure: Error, Equatable, Sendable {
    case unsupported, alreadyBound, busy, superseded, invalidIdentity
}

/// Create one coordinator per storage composition. All binding mutations pass through this actor.
public actor LocalSessionCoordinator: AcademicSessionCoordinator {
    private let providers: [CampusPlatform: any Provider]
    private let registry: any ConnectionRegistry
    private let vault: any CredentialVault
    private let cache: any CampusCache
    private var memory: [AccountNamespace: ProviderSession] = [:]
    private var operations: [CampusPlatform: Operation] = [:]
    private var unboundStatus: [CampusPlatform: ConnectionStatus] = [:]
    private var pendingCleanup: Set<CampusPlatform> = []
    private var academicRead: (id: UUID, cancel: @Sendable () -> Void)?

    private struct Operation {
        let id: UUID
        let kind: Kind
        let task: Task<ConnectionStatus, any Error>
    }

    private enum Kind { case connect, probe, refresh }

    public init(
        providers: [CampusPlatform: any Provider],
        registry: any ConnectionRegistry,
        vault: any CredentialVault,
        cache: any CampusCache
    ) {
        self.providers = providers
        self.registry = registry
        self.vault = vault
        self.cache = cache
    }

    public func snapshot() throws -> [ConnectionSnapshot] {
        CampusPlatform.allCases.map { platform in
            let record: ConnectionRecord?
            do {
                record = try registry.record(for: platform)
            } catch {
                return ConnectionSnapshot(platform: platform, status: .temporarilyUnavailable, canConnect: false, canDisconnect: false)
            }
            let isConnecting = operations[platform]?.kind == .connect
            let cleanupRequired = pendingCleanup.contains(platform) || record?.status == .cleanupRequired
            let status: ConnectionStatus
            if cleanupRequired {
                status = .cleanupRequired
            } else if isConnecting {
                status = .authenticating
            } else if let record, record.persistence == .memoryOnly, memory[record.namespace] == nil {
                status = .actionRequired
            } else {
                status = record?.status ?? unboundStatus[platform] ?? .unbound
            }
            return ConnectionSnapshot(
                platform: platform,
                status: status,
                canConnect: record == nil && !isConnecting && !cleanupRequired && providers[platform] != nil,
                canDisconnect: record != nil || isConnecting || cleanupRequired,
                bindingID: cleanupRequired ? nil : record?.namespace.opaqueID
            )
        }
    }

    public func connect(
        _ platform: CampusPlatform,
        using authorization: any ProviderAuthorization,
        persistence: CredentialPersistence
    ) async throws {
        guard let provider = providers[platform] else { throw SessionFailure.unsupported }
        guard operations[platform] == nil, !pendingCleanup.contains(platform) else { throw SessionFailure.busy }
        guard try registry.record(for: platform) == nil else { throw SessionFailure.alreadyBound }
        let id = UUID()
        let task = Task {
            try await finishConnect(platform, id: id, provider: provider, authorization: authorization, persistence: persistence)
        }
        operations[platform] = Operation(id: id, kind: .connect, task: task)
        _ = try await task.value
    }

    private func finishConnect(
        _ platform: CampusPlatform,
        id: UUID,
        provider: any Provider,
        authorization: any ProviderAuthorization,
        persistence: CredentialPersistence
    ) async throws -> ConnectionStatus {
        defer { finishOperation(platform, id: id) }
        let session: ProviderSession
        do {
            try assertCurrent(platform, id: id)
            session = try await provider.connect(using: authorization)
        } catch {
            try assertCurrent(platform, id: id)
            let failure = providerFailure(error)
            unboundStatus[platform] = status(for: failure)
            throw failure
        }
        try assertCurrent(platform, id: id)
        guard !session.remoteUserID.isEmpty else { throw SessionFailure.invalidIdentity }
        let namespace = AccountNamespace(platform: platform, remoteUserID: session.remoteUserID)
        let tombstone = ConnectionRecord(namespace: namespace, status: .cleanupRequired, persistence: persistence)
        // Journal the namespace before writing any credentials. A crash leaves a retryable tombstone.
        try registry.save(tombstone)
        do {
            if persistence == .keychain {
                try vault.save(session, in: namespace)
            }
            try registry.save(ConnectionRecord(namespace: namespace, status: .connected, persistence: persistence))
            if persistence == .memoryOnly { memory[namespace] = session }
            unboundStatus.removeValue(forKey: platform)
            return .connected
        } catch {
            try? purge(tombstone)
            throw error
        }
    }

    private func assertCurrent(_ platform: CampusPlatform, id: UUID) throws {
        guard operations[platform]?.id == id else { throw SessionFailure.superseded }
    }

    private func finishOperation(_ platform: CampusPlatform, id: UUID) {
        if operations[platform]?.id == id { operations.removeValue(forKey: platform) }
    }

    private func providerFailure(_ error: any Error) -> ProviderFailure {
        error as? ProviderFailure ?? .temporarilyUnavailable
    }

    private func status(for failure: ProviderFailure) -> ConnectionStatus {
        switch failure {
        case .expired: .expired
        case .actionRequired: .actionRequired
        case .temporarilyUnavailable: .temporarilyUnavailable
        }
    }

    private func purge(_ record: ConnectionRecord) throws {
        memory.removeValue(forKey: record.namespace)
        if record.persistence == .keychain {
            try vault.remove(in: record.namespace)
        }
        try cache.removeAll(in: record.namespace)
        try registry.remove(for: record.namespace.platform)
    }

    public func probe(_ platform: CampusPlatform) async throws -> ConnectionStatus {
        try await validate(platform, kind: .probe)
    }

    /// Reuses a valid session and attempts one recovery only after confirmed expiration.
    public func refresh(_ platform: CampusPlatform) async throws -> ConnectionStatus {
        try await validate(platform, kind: .refresh)
    }

    private func validate(_ platform: CampusPlatform, kind: Kind) async throws -> ConnectionStatus {
        if platform == .academic && academicRead != nil { throw SessionFailure.busy }
        if pendingCleanup.contains(platform) { return .cleanupRequired }
        guard let record = try registry.record(for: platform) else {
            return operations[platform]?.kind == .connect ? .authenticating : (unboundStatus[platform] ?? .unbound)
        }
        if record.status == .cleanupRequired { return .cleanupRequired }
        if record.status == .actionRequired { return .actionRequired }
        guard let provider = providers[platform] else { throw SessionFailure.unsupported }
        if let operation = operations[platform] {
            let status = try await operation.task.value
            guard kind == .refresh, operation.kind == .probe, status == .expired else { return status }
            // A refresh joining a read-only probe can only recover the binding it probed.
            guard !pendingCleanup.contains(platform), try registry.record(for: platform)?.namespace == record.namespace else {
                throw SessionFailure.superseded
            }
            return try await validate(platform, kind: .refresh)
        }
        let session: ProviderSession?
        switch record.persistence {
        case .keychain: session = try vault.load(in: record.namespace)
        case .memoryOnly: session = memory[record.namespace]
        }
        guard let session else { return try persistStatus(.actionRequired, for: record) }
        let id = UUID()
        let task = Task {
            try await finishValidation(record, id: id, kind: kind, provider: provider, session: session)
        }
        operations[platform] = Operation(id: id, kind: kind, task: task)
        return try await task.value
    }

    private func finishValidation(
        _ record: ConnectionRecord,
        id: UUID,
        kind: Kind,
        provider: any Provider,
        session: ProviderSession
    ) async throws -> ConnectionStatus {
        let platform = record.namespace.platform
        defer { finishOperation(platform, id: id) }
        try assertCurrent(platform, id: id)
        let updated: ProviderSession
        var attemptingRecovery = false
        do {
            do {
                if record.status == .expired && kind == .refresh { throw ProviderFailure.expired }
                updated = try await provider.probe(session)
            } catch ProviderFailure.expired where kind == .refresh {
                try assertCurrent(platform, id: id)
                attemptingRecovery = true
                updated = try await provider.refresh(session)
            }
        } catch {
            try assertCurrent(platform, id: id)
            let failure = providerFailure(error)
            return try persistStatus(attemptingRecovery && failure == .expired ? .actionRequired : status(for: failure), for: record)
        }
        try assertCurrent(platform, id: id)
        guard updated.remoteUserID.utf8.elementsEqual(session.remoteUserID.utf8) else {
            return try persistStatus(.actionRequired, for: record)
        }
        if updated != session {
            switch record.persistence {
            case .keychain: try vault.save(updated, in: record.namespace)
            case .memoryOnly: memory[record.namespace] = updated
            }
        }
        return try persistStatus(.connected, for: record)
    }

    private func persistStatus(_ status: ConnectionStatus, for record: ConnectionRecord) throws -> ConnectionStatus {
        if record.status != status {
            try registry.save(ConnectionRecord(namespace: record.namespace, status: status, persistence: record.persistence))
        }
        return status
    }
    public func academicData(_ endpoint: AcademicEndpoint, fields: [String: String]?, bindingID: String? = nil) async throws -> AcademicDataResult {
        try Task.checkCancellation()
        let platform = CampusPlatform.academic
        guard let provider = providers[platform] as? any AcademicPageProvider else { throw SessionFailure.unsupported }
        guard !pendingCleanup.contains(platform), let record = try registry.record(for: platform),
              record.status != .cleanupRequired else { throw ProviderFailure.actionRequired }
        if let bindingID, bindingID != record.namespace.opaqueID { throw SessionFailure.superseded }
        let key = try academicCacheKey(endpoint, fields: fields)
        let fallback = { [cache] (needsAuthorization: Bool) in
            guard let cached = try? cache.value(for: key, in: record.namespace),
                  let content = try? JSONDecoder().decode(AcademicContent.self, from: cached.data) else { return nil as AcademicDataResult? }
            return AcademicDataResult(content: content, updatedAt: cached.updatedAt, isCached: true, needsAuthorization: needsAuthorization)
        }
        guard record.status != .expired && record.status != .actionRequired else {
            if let data = fallback(true) { return data }
            throw ProviderFailure.actionRequired
        }
        let session = switch record.persistence {
        case .keychain: try vault.load(in: record.namespace)
        case .memoryOnly: memory[record.namespace]
        }
        guard let session else {
            _ = try persistStatus(.actionRequired, for: record)
            if let data = fallback(true) { return data }
            throw ProviderFailure.actionRequired
        }
        guard academicRead == nil, operations[platform] == nil else {
            if let data = fallback(false) { return data }
            throw SessionFailure.busy
        }

        let id = UUID()
        let task = Task { try await provider.page(endpoint, session: session, fields: fields) }
        academicRead = (id, { task.cancel() })
        defer { if academicRead?.id == id { academicRead = nil } }
        let page: AcademicPage
        do {
            page = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            guard academicRead?.id == id else { throw SessionFailure.superseded }
            try Task.checkCancellation()
            let failure = providerFailure(error)
            _ = try persistStatus(status(for: failure), for: record)
            if let data = fallback(failure == .expired || failure == .actionRequired) { return data }
            throw failure
        }
        guard academicRead?.id == id else { throw SessionFailure.superseded }
        try Task.checkCancellation()
        guard page.session.remoteUserID.utf8.elementsEqual(session.remoteUserID.utf8) else {
            _ = try persistStatus(.actionRequired, for: record)
            throw ProviderFailure.actionRequired
        }
        if page.session != session {
            switch record.persistence {
            case .keychain: try vault.save(page.session, in: record.namespace)
            case .memoryOnly: memory[record.namespace] = page.session
            }
        }
        _ = try persistStatus(.connected, for: record)
        let content: AcademicContent
        do {
            content = try AcademicContent(endpoint: endpoint, html: page.html)
            try content.checkSelection(fields)
        } catch {
            if let data = fallback(false) { return data }
            throw error
        }
        let updatedAt = Date()
        let encoded = try JSONEncoder().encode(content)
        try cache.save(CachedValue(data: encoded, updatedAt: updatedAt), for: key, in: record.namespace)
        return AcademicDataResult(content: content, updatedAt: updatedAt, isCached: false)
    }

    private func academicCacheKey(_ endpoint: AcademicEndpoint, fields: [String: String]?) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let selection = try encoder.encode(fields)
        return "academic.v1.\(endpoint).\(selection.base64EncodedString())"
    }

    public func disconnect(_ platform: CampusPlatform) throws {
        if platform == .academic {
            academicRead?.cancel()
            academicRead = nil
        }
        operations.removeValue(forKey: platform)?.task.cancel()
        unboundStatus.removeValue(forKey: platform)
        pendingCleanup.insert(platform)
        if let record = try registry.record(for: platform) {
            memory.removeValue(forKey: record.namespace)
            let tombstone = ConnectionRecord(namespace: record.namespace, status: .cleanupRequired, persistence: record.persistence)
            if record.status != .cleanupRequired {
                // A registry write failure must not prevent attempting to remove local secrets.
                try? registry.save(tombstone)
            }
            do {
                try purge(record)
            } catch {
                try? registry.save(tombstone)
                throw error
            }
        }
        pendingCleanup.remove(platform)
    }
}
