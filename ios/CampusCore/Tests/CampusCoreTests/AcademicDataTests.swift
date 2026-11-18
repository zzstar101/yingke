@testable import CampusCore
import Foundation
import Testing

@Suite struct AcademicDataTests {
    @Test func reopeningAnAcademicQueryUsesCacheBeforeTouchingTheProvider() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        let week = ["xnxq01id": "sample", "zc": "3"]

        let fresh = try await core.academicData(.schedule, fields: week)
        await fixture.provider.setFailure(.temporarilyUnavailable)
        let reopened = try await core.academicData(.schedule, fields: week)

        #expect(reopened.isCached)
        #expect(reopened.updatedAt == fresh.updatedAt)
        #expect(await fixture.provider.requestCount == 1)
    }

    @Test func returningToTheExactDefaultTimetableSelectionUsesItsCache() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a"))
        let defaultPage = try await core.academicData(.schedule, fields: nil)
        let week3 = ["xnxq01id": "sample", "zc": "3", "scheme": "a"]
        let week4 = ["xnxq01id": "sample", "zc": "4", "scheme": "a"]

        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(week: "4", periodScheme: "a"))
        let otherWeek = try await core.academicData(.schedule, fields: week4)
        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a"))
        let returned = try await core.academicData(.schedule, fields: week3)

        #expect(!otherWeek.isCached)
        #expect(returned.isCached)
        #expect(returned.updatedAt == defaultPage.updatedAt)
        guard case let .schedule(schedule) = returned.content else { Issue.record("Expected a schedule"); return }
        #expect(schedule.fields == week3)
        #expect(await fixture.provider.requestCount == 2)
    }

    @Test func reopeningDefaultTimetableUsesTheLatestExactSelectionSync() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a"))
        _ = try await core.academicData(.schedule, fields: nil)

        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a", course: "更新课程"))
        let week = ["xnxq01id": "sample", "zc": "3", "scheme": "a"]
        let synced = try await core.academicData(.schedule, fields: week, forceRefresh: true)
        let reopened = try await core.academicData(.schedule, fields: nil)

        #expect(!synced.isCached)
        #expect(reopened.isCached)
        #expect(reopened.updatedAt == synced.updatedAt)
        guard case let .schedule(schedule) = reopened.content else { Issue.record("Expected a schedule"); return }
        #expect(schedule.lessons.first?.courseName == "更新课程")
        #expect(await fixture.provider.requestCount == 2)
    }

    @Test func semesterCacheUsesOnlyCompleteResultsAndSharesTheLatestExactSelection() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a"))
        _ = try await core.academicData(.schedule, fields: nil)
        await #expect(throws: AcademicHTML.Error.unexpectedPage) {
            _ = try await core.academicData(.semesterSchedule, fields: nil)
        }

        let selection = ["xnxq01id": "sample", "scheme": "a"]
        let weeks = [3, 4].map { AcademicOption(value: String($0), label: "第\($0)周") }
        let complete = AcademicSchedule(terms: [], weeks: weeks, fields: selection, lessons: [
            AcademicLesson(courseName: "整学期课程", weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [3, 4]),
        ])
        await fixture.provider.setSemesterSchedule(complete)
        let fresh = try await core.academicData(.semesterSchedule, fields: nil)
        let exact = try await core.academicData(.semesterSchedule, fields: selection)
        #expect(exact.isCached)
        #expect(exact.updatedAt == fresh.updatedAt)
        guard case .schedule(let term) = exact.content else { Issue.record("Expected a complete term"); return }
        #expect(term == complete)

        let refreshed = AcademicSchedule(terms: [], weeks: weeks, fields: selection, lessons: [])
        await fixture.provider.setSemesterSchedule(refreshed)
        let synced = try await core.academicData(.semesterSchedule, fields: selection, forceRefresh: true)
        await fixture.provider.setSemesterSchemaFailure()
        let fallback = try await core.academicData(.semesterSchedule, fields: nil, forceRefresh: true)
        #expect(fallback.isCached && fallback.syncFailed)
        #expect(fallback.updatedAt == synced.updatedAt)
        guard case .schedule(let cached) = fallback.content else { Issue.record("Expected the latest cached term"); return }
        #expect(cached == refreshed)
        #expect(await fixture.provider.requestCount == 5)
    }

    @Test func expiredSessionOnlyReusesTheExactDefaultSelection() async throws {
        let fixture = try AcademicFixture()
        defer { fixture.removeFiles() }
        let core = fixture.coordinator
        try await core.connect(.academic, using: AcademicFixture.Authorization())
        await fixture.provider.setHTML(TestAcademicPageProvider.scheduleHTML(periodScheme: "a"))
        let defaultPage = try await core.academicData(.schedule, fields: nil)
        let matching = ["xnxq01id": "sample", "zc": "3", "scheme": "a"]

        await fixture.provider.setFailure(.expired)
        let fallback = try await core.academicData(.schedule, fields: matching, forceRefresh: true)

        #expect(fallback.isCached)
        #expect(fallback.syncFailed)
        #expect(fallback.needsAuthorization)
        #expect(fallback.updatedAt == defaultPage.updatedAt)
        for fields in [["xnxq01id": "sample", "zc": "3", "scheme": "b"], ["xnxq01id": "sample", "zc": "3"]] {
            await #expect(throws: ProviderFailure.actionRequired) {
                _ = try await core.academicData(.schedule, fields: fields)
            }
        }
        #expect(await fixture.provider.requestCount == 2)
    }

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
        let fallback = try await fixture.coordinator.academicData(.schedule, fields: week, forceRefresh: true)
        #expect(fallback.syncFailed)
        guard case .schedule(let older) = fallback.content else { Issue.record("Expected a cached schedule"); return }
        #expect(fallback.isCached)
        #expect(!fallback.needsAuthorization)
        #expect(older == original)
        #expect(fallback.updatedAt == fresh.updatedAt)
        await #expect(throws: AcademicHTML.Error.unexpectedPage) {
            _ = try await fixture.coordinator.academicData(.schedule, fields: ["xnxq01id": "sample", "zc": "4"])
        }

        await fixture.provider.setFailure(.expired)
        let expired = try await fixture.coordinator.academicData(.schedule, fields: week, forceRefresh: true)
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
        let cached = try await fixture.coordinator.academicData(.grades, fields: fields, forceRefresh: true)
        #expect(cached.syncFailed)
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
        let inFlight = Task { try await core.academicData(.schedule, fields: nil, forceRefresh: true) }
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
    static func scheduleHTML(week: String = "3", periodScheme: String? = nil, course: String = "合成课程") -> String {
        let scheme = periodScheme.map { "<select name=scheme aria-label=节次方案><option value=\($0)>示例方案</option></select>" } ?? ""
        return """
            <form><select name=xnxq01id><option value=sample>示例学期</option></select>
            <select name=zc><option value=\(week)>第\(week)周</option></select>\(scheme)
            <input type=hidden name=csrf value=synthetic-opaque-value></form>
            <table id=kbtable><tr><th>节次</th><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th><th>周六</th><th>周日</th></tr>
            <tr><th>第1节</th><td><div class=kbcontent>\(course)<br><font title="周次(节次)">\(week)(周)[01节]</font></div></td>
            <td></td><td></td><td></td><td></td><td></td><td></td></tr></table>
            """
    }

    private var html = scheduleHTML()
    private var termSchedule: AcademicSchedule?
    private var semesterSchemaFailure = false
    private var failure: ProviderFailure?
    private var gate: AcademicReadGate?
    private(set) var requestCount = 0

    func setHTML(_ value: String) { html = value }
    func setMalformed() { html = "<html><body>非课表页面</body></html>" }
    func setSemesterSchedule(_ value: AcademicSchedule) { termSchedule = value }
    func setSemesterSchemaFailure() { semesterSchemaFailure = true }
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
        if endpoint == .semesterSchedule, semesterSchemaFailure { throw AcademicHTML.Error.unexpectedPage }
        return AcademicPage(html: html, session: session, semesterSchedule: endpoint == .semesterSchedule ? termSchedule : nil)
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
