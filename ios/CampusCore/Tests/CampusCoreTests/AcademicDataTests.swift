@testable import CampusCore
import Foundation
import Testing

@Suite struct AcademicDataTests {
    @Test func malformedResponseAndExpiryKeepOnlyTheMatchingCachedQuery() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        try await fixture.coordinator.connect(.academic, using: AcademicFixture.Authorization())
        let week = ["xnxq01id": "sample", "zc": "3"]

        let fresh = try await fixture.coordinator.academicData(.schedule, fields: week)
        guard case .schedule(let original) = fresh.content else { Issue.record("Expected a schedule"); return }
        #expect(!fresh.isCached)
        #expect(original.lessons.first?.courseName == "合成课程")
        #expect(original.fields.keys.sorted() == ["xnxq01id", "zc"])
        let record = try #require(try fixture.registry.record(for: .academic))
        let cacheFolder = fixture.root.appending(path: "cache/academic/\(record.namespace.opaqueID)")
        let file = try #require(try FileManager.default.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil).first)
        let cached = try JSONDecoder().decode(CachedValue.self, from: Data(contentsOf: file))
        #expect(!String(decoding: cached.data, as: UTF8.self).contains("synthetic-opaque-value"))

        await #expect(throws: AcademicHTML.Error.unexpectedPage) {
            _ = try await fixture.coordinator.academicData(.schedule, fields: ["xnxq01id": "sample", "zc": "4"])
        }

        await fixture.provider.setMalformed()
        let fallback = try await fixture.coordinator.academicData(.schedule, fields: week)
        guard case .schedule(let older) = fallback.content else { Issue.record("Expected a cached schedule"); return }
        #expect(fallback.isCached)
        #expect(!fallback.needsAuthorization)
        #expect(older == original)
        #expect(fallback.updatedAt == fresh.updatedAt)
        await #expect(throws: AcademicHTML.Error.unexpectedPage) {
            _ = try await fixture.coordinator.academicData(.schedule, fields: ["xnxq01id": "sample", "zc": "4"])
        }

        await fixture.provider.setFailure(.expired)
        let expired = try await fixture.coordinator.academicData(.schedule, fields: week)
        #expect(expired.isCached)
        #expect(expired.needsAuthorization)
        let snapshot = try await fixture.coordinator.snapshot().first { $0.platform == .academic }
        #expect(snapshot?.status == .expired)
        let requestCount = await fixture.provider.requestCount
        await #expect(throws: ProviderFailure.actionRequired) {
            _ = try await fixture.coordinator.academicData(.schedule, fields: nil)
        }
        #expect(await fixture.provider.requestCount == requestCount)
    }

    @Test func filteredGradesDoNotReplaceCacheWhenResponseOmitsSelectedTerm() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        try await fixture.coordinator.connect(.academic, using: AcademicFixture.Authorization())
        let fields = ["kksj": "synthetic-term"]
        let table = """
            <table id="dataList"><tr><th>课程名称</th><th>课程编号</th><th>成绩</th></tr>
            <tr><td>合成课程</td><td>DEMO</td><td>90</td></tr></table>
            """
        await fixture.provider.setHTML("<select name=kksj><option value=synthetic-term selected>示例学期</option></select>\(table)")
        let fresh = try await fixture.coordinator.academicData(.grades, fields: fields)
        #expect(!fresh.isCached)
        await fixture.provider.setHTML(table.replacingOccurrences(of: ">90<", with: ">60<"))
        let cached = try await fixture.coordinator.academicData(.grades, fields: fields)
        guard case let .grades(grades) = cached.content else { Issue.record("Expected cached grades"); return }
        #expect(cached.isCached)
        #expect(grades.rows.first?.grade == "90")
        #expect(cached.updatedAt == fresh.updatedAt)
    }

    @Test func unlinkClearsCacheAndRejectsAnOlderInFlightResultAfterRebinding() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        let first = try #require(try fixture.registry.record(for: .academic))
        _ = try await core.academicData(.schedule, fields: nil)

        let gate = AcademicReadGate()
        await fixture.provider.pauseNextRead(at: gate)
        let inFlight = Task { try await core.academicData(.schedule, fields: nil) }
        await gate.waitUntilEntered()
        try await core.disconnect(.academic)
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        let second = try #require(try fixture.registry.record(for: .academic))
        await gate.release()

        await #expect(throws: SessionFailure.superseded) { _ = try await inFlight.value }
        #expect(first.namespace != second.namespace)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "cache/academic/\(first.namespace.opaqueID)").path))
        await fixture.provider.setFailure(.temporarilyUnavailable)
        await #expect(throws: ProviderFailure.temporarilyUnavailable) {
            _ = try await core.academicData(.schedule, fields: nil)
        }
    }
}

private struct AcademicFixture {
    struct Authorization: ProviderAuthorization {}
    let root: URL
    let registry: FileConnectionRegistry
    let provider: TestAcademicPageProvider
    let coordinator: LocalSessionCoordinator

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let registry = try FileConnectionRegistry(directory: root.appending(path: "registry"))
        let cache = try FileCampusCache(directory: root.appending(path: "cache"))
        let provider = TestAcademicPageProvider()
        self.root = root
        self.registry = registry
        self.provider = provider
        self.coordinator = LocalSessionCoordinator(
            providers: [.academic: provider], registry: registry,
            vault: KeychainCredentialVault(service: "ink.zzstar.yingke.synthetic.\(UUID().uuidString)"), cache: cache
        )
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private actor TestAcademicPageProvider: AcademicPageProvider {
    private var html = """
        <form><select name=xnxq01id><option value=sample>示例学期</option></select>
        <select name=zc><option value=3>第3周</option></select>
        <input type=hidden name=csrf value=synthetic-opaque-value></form>
        <table id=kbtable><tr><th>节次</th><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th><th>周六</th><th>周日</th></tr>
        <tr><th>第1节</th><td><div class=kbcontent>合成课程<br><font title="周次(节次)">3(周)[01节]</font></div></td>
        <td></td><td></td><td></td><td></td><td></td><td></td></tr></table>
        """
    private var failure: ProviderFailure?
    private var gate: AcademicReadGate?
    private(set) var requestCount = 0

    func setHTML(_ value: String) { html = value }
    func setMalformed() { html = "<html><body>非课表页面</body></html>" }
    func setFailure(_ value: ProviderFailure) { failure = value }
    func pauseNextRead(at gate: AcademicReadGate) { self.gate = gate }

    func connect(using authorization: any ProviderAuthorization) -> ProviderSession {
        ProviderSession(remoteUserID: "synthetic-account", credential: Data([1]))
    }
    func probe(_ session: ProviderSession) -> ProviderSession { session }
    func refresh(_ session: ProviderSession) -> ProviderSession { session }

    func page(_ endpoint: AcademicEndpoint, session: ProviderSession, fields: [String: String]?) async throws -> AcademicPage {
        requestCount += 1
        if let gate {
            self.gate = nil
            await gate.pause()
        }
        if let failure { throw failure }
        return AcademicPage(html: html, session: session)
    }
}

private actor AcademicReadGate {
    private var entered: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if blocked != nil { return }
        await withCheckedContinuation { entered = $0 }
    }

    func pause() async {
        await withCheckedContinuation {
            blocked = $0
            entered?.resume()
            entered = nil
        }
    }

    func release() {
        blocked?.resume()
        blocked = nil
    }
}
