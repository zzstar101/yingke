@testable import CampusCore
import Foundation
import Testing

private let portal = URL(string: "https://jw.educationgroup.cn/gzasc_jsxsd/")!
private let activation = portal.appending(path: "framework/xsMain.jsp")
private let schedule = portal.appending(path: "xskb/xskb_list.do")
private let scheduleHTML = """
<html><form><select name="xnxq01id"><option value="2026-1">2026-1</option></select>
<select name="zc"><option value="1">1</option></select></form>
<table id="kbtable">
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr><th>1</th><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
</table></html>
"""
private let gradesHTML = #"<html><table id="dataList"><tr><th>课程名称</th><th>课程编号</th><th>成绩</th></tr><tr><td>合成课程</td><td>DEMO</td><td>90</td></tr></table></html>"#

@Test func academicActivationCarriesRotatedCookiesIntoTheNextRead() async throws {
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>", headers: [
            "Set-Cookie": "JSESSIONID=activated; Path=/gzasc_jsxsd; Secure; HttpOnly; SameSite=Lax",
        ]),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: scheduleHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let seed = try #require(HTTPCookie.cookies(withResponseHeaderFields: [
        "Set-Cookie": "JSESSIONID=browser; Path=/gzasc_jsxsd; Secure; HttpOnly",
    ], for: portal).first)
    let session = try await provider.connect(using: AcademicAuthorization(cookies: [seed], accountID: "fixture-account"))
    let page = try await provider.page(.schedule, session: session, fields: nil)

    #expect(page.session.remoteUserID == "fixture-account")
    #expect(page.html == scheduleHTML)
    let requests = await server.requests
    #expect(requests.map(\.httpMethod) == ["GET", "GET", "GET"])
    #expect(requests.map { $0.value(forHTTPHeaderField: "Cookie") } == ["JSESSIONID=browser", "JSESSIONID=activated", "JSESSIONID=activated"])
}

@Test func academicSchedulePostsFormFieldsAndOtherPagesUseQueryFilters() async throws {
    let grades = portal.appending(path: "kscj/cjcx_list")
    let exams = portal.appending(path: "xsks/xsksap_list")
    let plan = portal.appending(path: "pyfa/pyfa_query")
    let examsHTML = "<html><p>当前学生没有考试安排</p></html>"
    let planHTML = "<html><table><tr><th>课程名称</th><th>学分</th><th>课程性质</th></tr><tr><td>合成课程</td><td>2</td><td>必修</td></tr></table></html>"
    let liveForm = scheduleHTML
        .replacingOccurrences(of: "</select>", with: "<option value=\"2026-2\">2026-2</option></select>", options: [], range: scheduleHTML.range(of: "</select>"))
        .replacingOccurrences(of: "</form>", with: """
            <input type="hidden" name="csrf" value="prefetched-token">
            <select name="dynamicPeriodKey" aria-label="节次方案"><option value="default">默认</option><option value="第 1+&amp;">方案一</option></select></form>
            """)
    let selectedHTML = liveForm
        .replacingOccurrences(of: "value=\"2026-2\"", with: "value=\"2026-2\" selected")
        .replacingOccurrences(of: "value=\"1\">1</option>", with: "value=\"9\">9</option>")
        .replacingOccurrences(of: "value=\"第 1+&amp;\"", with: "value=\"第 1+&amp;\" selected")
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: liveForm, headers: [
            "Set-Cookie": "JSESSIONID=prefetched; Path=/gzasc_jsxsd; Secure; HttpOnly",
        ]),
        .init(schedule, html: selectedHTML),
        .init(URL(string: "\(grades.absoluteString)?kksj=2026-1")!, html: gradesHTML),
        .init(URL(string: "\(exams.absoluteString)?xnxqid=2026-1")!, html: examsHTML),
        .init(plan, html: planHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    var session = try await provider.connect(using: fixtureAuthorization())
    let selected = try await provider.page(.schedule, session: session, fields: [
        "xnxq01id": "2026-2", "zc": "9", "dynamicPeriodKey": "第 1+&",
        "csrf": "caller-secret", "unrelated": "caller-identifier",
    ])
    #expect(selected.html == selectedHTML)
    session = selected.session
    session = try await provider.page(.grades, session: session, fields: ["kksj": "2026-1"]).session
    session = try await provider.page(.exams, session: session, fields: ["xnxqid": "2026-1"]).session
    _ = try await provider.page(.plan, session: session)

    let requests = Array(await server.requests.dropFirst(2))
    #expect(requests.map(\.httpMethod) == ["GET", "POST", "GET", "GET", "GET"])
    let prefetch = try #require(requests.first)
    #expect(prefetch.url == schedule)
    #expect(prefetch.httpBody == nil)
    let post = try #require(requests.dropFirst().first)
    #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=UTF-8")
    #expect(post.value(forHTTPHeaderField: "Cookie") == "JSESSIONID=prefetched")
    let body = try #require(post.httpBody)
    #expect(String(decoding: body, as: UTF8.self) == "xnxq01id=2026-2&zc=9&csrf=prefetched-token&dynamicPeriodKey=%E7%AC%AC+1%2B%26")
    #expect(requests.dropFirst(2).allSatisfy { $0.httpBody == nil })
}

@Test func academicSemesterScheduleSubmitsTheExplicitAllWeeksOptionWithTermAndScheme() async throws {
    let prefetch = scheduleHTML
        .replacingOccurrences(of: "<form>", with: #"<form action="xskb_list.do" method="post">"#)
        .replacingOccurrences(of: "</form>", with: """
            <input type="hidden" name="csrf" value="prefetched-token">
            <select name="scheme" aria-label="节次方案"><option value="A">方案一</option><option value="B">方案二</option></select></form>
            """)
        .replacingOccurrences(of: "<option value=\"2026-1\">2026-1</option>", with: """
            <option value="2026-1" selected>2026-1</option><option value="2026-2">2026-2</option>
            """)
        .replacingOccurrences(of: "<option value=\"1\">1</option>", with: """
            <option value="1" selected>第1周</option><option value="学期 +&amp;">整学期</option>
            """)
    let full = prefetch
        .replacingOccurrences(of: " selected", with: "")
        .replacingOccurrences(of: #"value="2026-2""#, with: #"value="2026-2" selected"#)
        .replacingOccurrences(of: #"value="B""#, with: #"value="B" selected"#)
        .replacingOccurrences(of: #"value="学期 +&amp;""#, with: #"value="学期 +&amp;" selected"#)
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: prefetch),
        .init(schedule, html: full),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())

    let page = try await provider.page(.semesterSchedule, session: session, fields: ["xnxq01id": "2026-2", "scheme": "B"])
    #expect(page.html == full)
    let requests = Array(await server.requests.dropFirst(2))
    #expect(requests.map(\.httpMethod) == ["GET", "POST"])
    let post = try #require(requests.last)
    #expect(post.httpBody == Data("xnxq01id=2026-2&zc=%E5%AD%A6%E6%9C%9F+%2B%26&csrf=prefetched-token&scheme=B".utf8))
}

@Test func academicSemesterScheduleCollectsEveryAdvertisedWeekWhenThereIsNoAllOption() async throws {
    func page(_ week: Int, token: String, course: String) -> String {
        scheduleHTML
            .replacingOccurrences(of: #"<option value="1">1</option>"#, with: """
                <option value="3" \(week == 3 ? "selected" : "")>第3周</option>
                <option value="1" \(week == 1 ? "selected" : "")>第1周</option>
                <option value="2" \(week == 2 ? "selected" : "")>第2周</option>
                """)
            .replacingOccurrences(of: "</form>", with: "<input type=hidden name=csrf value=\(token)></form>")
            .replacingOccurrences(of: "<th>1</th><td></td>", with: "<th>1</th><td><div class=kbcontent>\(course)</div></td>")
    }
    let unmarked = page(2, token: "one", course: "专属课程")
    let prefetch = unmarked.replacingOccurrences(of: ">第2周</option>", with: ">第2周（当前周）</option>")
    #expect(try AcademicHTML.schedule(prefetch).lessons.count == 1)
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: prefetch),
        .init(schedule, html: page(1, token: "two", course: "普通课程")),
        .init(schedule, html: page(3, token: "three", course: "普通课程")),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())

    let result = try await provider.page(.semesterSchedule, session: session)
    let term = try #require(result.semesterSchedule)
    #expect(term.fields == ["xnxq01id": "2026-1"])
    #expect(term.weeks.map(\.value) == ["1", "2", "3"])
    #expect(term.currentTeachingWeek == 2)
    #expect(term.teachingWeek() == 2)
    #expect(term.lessons.count == 2)
    #expect(term.lessons.first(where: { $0.courseName == "普通课程" })?.weeks == [1, 3])
    #expect(term.lessons.first(where: { $0.courseName == "专属课程" })?.weeks == [2])
    let requests = Array(await server.requests.dropFirst(2))
    #expect(requests.map(\.httpMethod) == ["GET", "POST", "POST"])
    #expect(requests[1].httpBody == Data("xnxq01id=2026-1&zc=1&csrf=one".utf8))
    #expect(requests[2].httpBody == Data("xnxq01id=2026-1&zc=3&csrf=two".utf8))
}

@Test func academicFilteredScheduleUsesTheFormEvenWhenTheDefaultGridIsUnrecognized() async throws {
    let prefetch = scheduleHTML.replacingOccurrences(of: "<th>1</th>", with: "<th>合成未知节次</th>")
    let selected = scheduleHTML.replacingOccurrences(of: "<option value=\"1\">1</option>", with: "<option value=\"2\">2</option>")
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: prefetch),
        .init(schedule, html: prefetch),
        .init(schedule, html: selected),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())

    #expect(throws: AcademicHTML.Error.unexpectedPage) { _ = try AcademicHTML.schedule(prefetch) }
    let page = try await provider.page(.schedule, session: session, fields: ["zc": "2"])
    let requests = await server.requests
    #expect(requests.map(\.httpMethod) == ["GET", "GET", "GET", "POST"])
    #expect(requests.last?.httpBody == Data("xnxq01id=2026-1&zc=2".utf8))
    #expect(try AcademicHTML.schedule(page.html).fields["zc"] == "2")
}

@Test(arguments: [false, true]) func academicRecognizesTheOfficialLoginFormOrRedirectAsExpired(_ redirect: Bool) async throws {
    let form = #"<html><form action="/gzasc_jsxsd/xk/LoginToXk"><input type="password"><img src="verifycode.servlet"></form></html>"#
    let reply: AcademicTestServer.Reply = redirect
        ? .init(schedule, status: 302, headers: ["Location": "/gzasc_jsxsd/"])
        : .init(schedule, html: form)
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        reply,
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    await #expect(throws: ProviderFailure.expired) { _ = try await provider.probe(session) }
    await #expect(throws: ProviderFailure.actionRequired) { _ = try await provider.refresh(session) }
    #expect(await server.requests.count == 3)
}

@Test(arguments: [
    "http://jw.educationgroup.cn/gzasc_jsxsd/xskb/xskb_list.do",
    "https://jw.educationgroup.cn.example/gzasc_jsxsd/xskb/xskb_list.do",
    "https://jw.educationgroup.cn:444/gzasc_jsxsd/xskb/xskb_list.do",
    "https://mail.educationgroup.cn/gzasc_jsxsd/xskb/xskb_list.do",
    "/gzasc_jsxsd_elsewhere/xskb/xskb_list.do",
    "/gzasc_jsxsd/%2e%2e/account",
    "/gzasc_jsxsd/grxx/xsxx",
]) func academicRedirectRefusesDestinationsOutsideTheReadOnlyRoute(_ location: String) async throws {
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, status: 307, headers: ["Location": location]),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    await #expect(throws: ProviderFailure.temporarilyUnavailable) { _ = try await provider.connect(using: fixtureAuthorization()) }
    #expect(await server.requests.count == 2)
}

@Test(arguments: [301, 302, 303]) func academicRejectsMethodChangingRedirectsFromSchedulePost(_ status: Int) async throws {
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: scheduleHTML),
        .init(schedule, status: status, headers: ["Location": "?canonical=1"]),
        .init(URL(string: "\(schedule.absoluteString)?canonical=1")!, html: scheduleHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    await #expect(throws: ProviderFailure.temporarilyUnavailable) {
        _ = try await provider.page(.schedule, session: session, fields: ["zc": "2"])
    }
    #expect(await server.requests.map(\.httpMethod) == ["GET", "GET", "GET", "POST"])
}

@Test func academicPreservesScheduleFormOnAnAllowed307Redirect() async throws {
    let canonical = URL(string: "\(schedule.absoluteString)?canonical=1")!
    let selected = scheduleHTML.replacingOccurrences(of: "value=\"1\">1</option>", with: "value=\"2\">2</option>")
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: scheduleHTML),
        .init(schedule, status: 307, headers: ["Location": "?canonical=1"]),
        .init(canonical, html: selected),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    let page = try await provider.page(.schedule, session: session, fields: ["zc": "2"])
    #expect(page.html == selected)
    let requests = await server.requests
    #expect(requests.map(\.httpMethod) == ["GET", "GET", "GET", "POST", "POST"])
    #expect(requests.last?.httpBody == Data("xnxq01id=2026-1&zc=2".utf8))
}

@Test func academicFollowsAnAllowedRedirectWithCookiesRotatedOnThatHop() async throws {
    let canonical = URL(string: "\(schedule.absoluteString)?canonical=1")!
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, status: 302, headers: [
            "Location": "?canonical=1",
            "Set-Cookie": "JSESSIONID=redirected; Path=/gzasc_jsxsd; Secure; HttpOnly",
        ]),
        .init(canonical, html: scheduleHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    _ = try await provider.connect(using: fixtureAuthorization())
    #expect(await server.requests.last?.value(forHTTPHeaderField: "Cookie") == "JSESSIONID=redirected")
}

@Test func academicSerializesAndPacesEveryRequestIncludingRedirects() async throws {
    let canonical = URL(string: "\(schedule.absoluteString)?canonical=1")!
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, status: 302, headers: ["Location": "?canonical=1"]),
        .init(canonical, html: scheduleHTML),
        .init(schedule, html: scheduleHTML),
        .init(schedule, html: scheduleHTML),
    ], latency: .milliseconds(25))
    let provider = AcademicProvider(requestInterval: .milliseconds(80)) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    async let first = provider.probe(session)
    async let second = provider.probe(session)
    _ = try await (first, second)

    let starts = await server.starts
    #expect(starts.count == 5)
    #expect(zip(starts, starts.dropFirst()).allSatisfy { $0.duration(to: $1) >= .milliseconds(75) })
    #expect(await server.maximumInFlight == 1)
}

@Test(arguments: [403, 429]) func academicDenialStatusesAreTemporary(_ status: Int) async throws {
    let grades = portal.appending(path: "kscj/cjcx_list")
    let challenge = "<html><title>访问受限</title><table><tr><td>稍后重试</td></tr></table></html>"
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(grades, html: challenge, status: status),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    await #expect(throws: ProviderFailure.temporarilyUnavailable) { _ = try await provider.page(.grades, session: session) }
    #expect(await server.requests.count == 3)
}

@Test func academicReturnsMalformedBusinessHTMLForCallerSchemaHandling() async throws {
    let grades = portal.appending(path: "kscj/cjcx_list")
    let unknownHTML = "<html><h1>Unexpected academic layout</h1></html>"
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: scheduleHTML),
        .init(grades, html: unknownHTML),
        .init(schedule, html: unknownHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())
    let gradesPage = try await provider.page(.grades, session: session)
    let schedulePage = try await provider.page(.schedule, session: session, fields: ["zc": "9"])
    #expect(gradesPage.html == unknownHTML)
    #expect(schedulePage.html == unknownHTML)
    #expect(throws: AcademicHTML.Error.unexpectedPage) { _ = try AcademicHTML.grades(gradesPage.html) }
    #expect(throws: AcademicHTML.Error.unexpectedPage) { _ = try AcademicHTML.schedule(schedulePage.html) }
    #expect(await server.requests.map(\.httpMethod) == ["GET", "GET", "GET", "GET"])
}

@Test func academicSchedulePreservesRepeatedFormControlsWhenSelectingAWeek() async throws {
    let formHTML = scheduleHTML.replacingOccurrences(of: "</form>", with: """
        <input type=hidden name=display value=first>
        <input type=hidden name=display value=second>
        <input type=hidden name=zc value=original>
        </form>
        """)
    let selectedHTML = formHTML.replacingOccurrences(of: #"name="zc"><option value="1">1"#, with: #"name="zc"><option value="2">2"#)
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: formHTML),
        .init(schedule, html: formHTML),
        .init(schedule, html: selectedHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let session = try await provider.connect(using: fixtureAuthorization())

    #expect(try AcademicHTML.schedule(formHTML).fields["zc"] == "1")
    let page = try await provider.page(.schedule, session: session, fields: ["zc": "2"])
    #expect(try AcademicHTML.schedule(page.html).fields["zc"] == "2")
    let request = try #require(await server.requests.last)
    #expect(request.httpMethod == "POST")
    #expect(request.httpBody == Data("xnxq01id=2026-1&zc=2&display=first&display=second&zc=original".utf8))
}

@Test func academicConfirmsSessionWhenRecognizedScheduleHasUnsupportedRows() async throws {
    let changedLayout = scheduleHTML.replacingOccurrences(of: "<th>1</th>", with: "<th>节次标签暂未支持</th>")
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: changedLayout),
        .init(schedule, html: changedLayout),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }

    let session = try await provider.connect(using: fixtureAuthorization())
    _ = try await provider.probe(session)
    #expect(throws: AcademicHTML.Error.unexpectedPage) { try AcademicHTML.schedule(changedLayout) }
}

@Test func academicRejectsA200ShellWithoutAnAuthenticatedSchedule() async throws {
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>"),
        .init(schedule, html: "<html><h1>稍后重试</h1></html>"),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    await #expect(throws: ProviderFailure.temporarilyUnavailable) { _ = try await provider.connect(using: fixtureAuthorization()) }
}

@Test func academicCookieStateIsScopedAndOnlyAdvancesWithTheReturnedSession() async throws {
    let grades = portal.appending(path: "kscj/cjcx_list")
    let server = AcademicTestServer([
        .init(activation, html: "<html><frameset></frameset></html>", headers: [
            "Set-Cookie": "gradePreference=active; Path=/gzasc_jsxsd/kscj; Secure; HttpOnly; SameSite=Strict; Max-Age=3600, wrongDomain=excluded; Domain=example.test; Path=/, wrongPort=excluded; Port=8443; Path=/",
        ]),
        .init(schedule, html: scheduleHTML),
        .init(grades, html: gradesHTML, headers: ["Set-Cookie": "gradePreference=; Path=/gzasc_jsxsd/kscj; Max-Age=0"]),
        .init(grades, html: gradesHTML),
        .init(grades, html: gradesHTML),
    ])
    let provider = AcademicProvider(requestInterval: .zero) { try await server.send($0) }
    let initial = try await provider.connect(using: fixtureAuthorization())
    let removed = try await provider.page(.grades, session: initial)
    _ = try await provider.page(.grades, session: removed.session)
    _ = try await provider.page(.grades, session: initial)

    let requests = await server.requests
    let header = { (request: URLRequest) in request.value(forHTTPHeaderField: "Cookie") ?? "" }
    #expect(header(requests[1]) == "JSESSIONID=fixture")
    #expect(Set(header(requests[2]).components(separatedBy: "; ")) == ["gradePreference=active", "JSESSIONID=fixture"])
    #expect(header(requests[3]) == "JSESSIONID=fixture")
    #expect(Set(header(requests[4]).components(separatedBy: "; ")) == ["gradePreference=active", "JSESSIONID=fixture"])
}

private func fixtureAuthorization() throws -> AcademicAuthorization {
    let cookies = HTTPCookie.cookies(withResponseHeaderFields: [
        "Set-Cookie": "JSESSIONID=fixture; Path=/gzasc_jsxsd; Secure; HttpOnly",
    ], for: portal)
    return AcademicAuthorization(cookies: cookies, accountID: "fixture-account")
}

private actor AcademicTestServer {
    struct Reply: Sendable {
        let url: URL
        let html: String
        let status: Int
        let headers: [String: String]

        init(_ url: URL, html: String = "", status: Int = 200, headers: [String: String] = [:]) {
            self.url = url
            self.html = html
            self.status = status
            self.headers = headers
        }
    }

    private var replies: [Reply]
    private let latency: Duration
    private var inFlight = 0
    private(set) var requests: [URLRequest] = []
    private(set) var starts: [ContinuousClock.Instant] = []
    private(set) var maximumInFlight = 0

    init(_ replies: [Reply], latency: Duration = .zero) {
        self.replies = replies
        self.latency = latency
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        starts.append(ContinuousClock.now)
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        guard let expected = replies.first, request.url == expected.url else {
            Issue.record("Unexpected synthetic academic request")
            throw URLError(.unsupportedURL)
        }
        replies.removeFirst()
        if latency > .zero { try await Task.sleep(for: latency) }
        let response = try #require(HTTPURLResponse(url: expected.url, statusCode: expected.status, httpVersion: "HTTP/1.1", headerFields: expected.headers))
        return (Data(expected.html.utf8), response)
    }
}
