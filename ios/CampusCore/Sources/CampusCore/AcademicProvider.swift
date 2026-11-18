import Foundation

public enum AcademicEndpoint: Sendable {
    case schedule, grades, exams, plan

    fileprivate var path: String {
        switch self {
        case .schedule: "xskb/xskb_list.do"
        case .grades: "kscj/cjcx_list"
        case .exams: "xsks/xsksap_list"
        case .plan: "pyfa/pyfa_query"
        }
    }
}

public struct AcademicAuthorization: ProviderAuthorization, CustomReflectable {
    fileprivate let cookies: [HTTPCookie]
    fileprivate let accountID: String

    public init(cookies: [HTTPCookie], accountID: String) {
        self.cookies = cookies
        self.accountID = accountID
    }

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct AcademicPage: Sendable, CustomReflectable {
    public let html: String
    public let session: ProviderSession

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct AcademicProvider: Provider {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static let loginURL = URL(string: "https://jw.educationgroup.cn/gzasc_jsxsd/")!
    private static let activationURL = loginURL.appending(path: "framework/xsMain.jsp")
    private static let prefix = "/gzasc_jsxsd/"
    private static let host = "jw.educationgroup.cn"

    private static let portalRequests = AcademicRequestGate(interval: .milliseconds(1_200))
    private let gate: AcademicRequestGate
    private let send: Send

    public init() {
        gate = Self.portalRequests
        send = Self.sendEphemeral
    }

    init(requestInterval: Duration, send: @escaping Send) {
        gate = AcademicRequestGate(interval: requestInterval)
        self.send = send
    }

    public static func permits(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              ownsOrigin(parts), parts.percentEncodedPath.hasPrefix(prefix) else { return false }
        let path = parts.path
        let encoded = parts.percentEncodedPath.lowercased()
        return !path.contains("\\") && !path.contains("//") && !path.contains(";") && !path.contains("%") &&
            !encoded.contains("%2f") && !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }

    private static func ownsOrigin(_ parts: URLComponents) -> Bool {
        parts.scheme?.lowercased() == "https" && parts.host?.lowercased() == host &&
            (parts.port == nil || parts.port == 443) && parts.user == nil && parts.password == nil
    }

    public func connect(using authorization: any ProviderAuthorization) async throws -> ProviderSession {
        guard let authorization = authorization as? AcademicAuthorization,
              !authorization.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderFailure.actionRequired
        }
        let jar = AcademicCookies(authorization.cookies)
        guard !jar.isEmpty else { throw ProviderFailure.actionRequired }
        _ = try await load(Self.activationURL, referer: Self.loginURL, jar: jar)
        let html = try await load(Self.loginURL.appending(path: AcademicEndpoint.schedule.path), referer: Self.activationURL, jar: jar)
        try Self.validateSchedule(html)
        return try jar.session(for: authorization.accountID)
    }

    public func probe(_ session: ProviderSession) async throws -> ProviderSession {
        let page = try await page(.schedule, session: session)
        try Self.validateSchedule(page.html)
        return page.session
    }

    public func refresh(_ session: ProviderSession) async throws -> ProviderSession {
        try Task.checkCancellation()
        throw ProviderFailure.actionRequired
    }

    public func page(_ endpoint: AcademicEndpoint, session: ProviderSession, fields: [String: String]? = nil) async throws -> AcademicPage {
        let jar = try AcademicCookies(session: session)
        let endpointURL = Self.loginURL.appending(path: endpoint.path)
        var url = endpointURL
        var form: Data?
        if let fields {
            if endpoint == .schedule {
                let prefetch = try await load(endpointURL, referer: Self.activationURL, jar: jar)
                guard let live = try? AcademicHTML.schedulePage(prefetch) else {
                    // Let the coordinator classify the schema error and keep any cached result.
                    return AcademicPage(html: prefetch, session: try jar.session(for: session.remoteUserID))
                }
                var controls = live.form
                if let term = fields["xnxq01id"], live.schedule.terms.contains(where: { $0.value == term }) {
                    controls["xnxq01id"] = term
                }
                // A requested term may have different week options from the prefetched term.
                if let week = fields["zc"] { controls["zc"] = week }
                if let name = live.schedule.periodSchemeField, let scheme = fields[name],
                   live.schedule.periodSchemes.contains(where: { $0.value == scheme }) {
                    controls[name] = scheme
                }
                form = Data(Self.encode(controls, form: true).utf8)
            } else if !fields.isEmpty {
                var parts = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)!
                parts.percentEncodedQuery = Self.encode(fields, form: false)
                guard let filtered = parts.url else { throw ProviderFailure.temporarilyUnavailable }
                url = filtered
            }
        }
        let html = try await load(url, referer: form == nil ? Self.activationURL : endpointURL, jar: jar, form: form)
        return AcademicPage(html: html, session: try jar.session(for: session.remoteUserID))
    }

    private static func encode(_ fields: [String: String], form: Bool) -> String {
        let allowed = CharacterSet(charactersIn: form ? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._" : "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func escaped(_ value: String) -> String {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed)!
            return form ? encoded.replacingOccurrences(of: "%20", with: "+") : encoded
        }
        return fields.sorted { $0.key < $1.key }.map { "\(escaped($0.key))=\(escaped($0.value))" }.joined(separator: "&")
    }

    private func load(_ initialURL: URL, referer: URL, jar: AcademicCookies, form: Data? = nil) async throws -> String {
        var url = initialURL
        for hop in 0...4 {
            guard Self.permits(url) else { throw ProviderFailure.temporarilyUnavailable }
            let request = Self.request(for: url, referer: referer, form: form, cookie: jar.header(for: url))
            let (data, response) = try await perform(request)
            guard response.url == url else { throw ProviderFailure.temporarilyUnavailable }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let target = URL(string: location, relativeTo: url)?.absoluteURL else {
                    throw ProviderFailure.temporarilyUnavailable
                }
                if Self.isLoginDestination(target) { throw ProviderFailure.expired }
                // Follow only canonicalization of the requested read-only route.
                guard hop < 4, target != url, Self.permits(target), target.path == initialURL.path else {
                    throw ProviderFailure.temporarilyUnavailable
                }
                // A GET after a filtered POST can silently return the default schedule.
                guard form == nil || [307, 308].contains(response.statusCode) else {
                    throw ProviderFailure.temporarilyUnavailable
                }
                jar.apply(response, from: url)
                url = target
                continue
            }
            guard response.statusCode == 200,
                  let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                throw ProviderFailure.temporarilyUnavailable
            }
            if Self.containsLoginForm(html, at: url) { throw ProviderFailure.expired }
            jar.apply(response, from: url)
            return html
        }
        throw ProviderFailure.temporarilyUnavailable
    }

    private static func request(for url: URL, referer: URL, form: Data?, cookie: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        if let form {
            request.httpMethod = "POST"
            request.httpBody = form
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await gate.perform(request, send: send)
        } catch {
            try Task.checkCancellation()
            throw ProviderFailure.temporarilyUnavailable
        }
    }

    private static func isLoginDestination(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true), ownsOrigin(parts) else { return false }
        return [String(prefix.dropLast()), prefix, prefix + "xk/LoginToXk"].contains(parts.percentEncodedPath)
    }

    private static func containsLoginForm(_ html: String, at url: URL) -> Bool {
        let expression = /(?is)<form\b[^>]*\saction\s*=\s*["']?([^"'\s>]+)[^>]*>(.*?)<\/form\s*>/
        let password = /(?i)<input\b[^>]*\stype\s*=\s*(?:"password"|'password'|password(?=[\s>]))/
        return html.matches(of: expression).contains { match in
            guard let action = URL(string: String(match.output.1), relativeTo: url)?.absoluteURL,
                  isLoginDestination(action) else { return false }
            return match.output.2.firstMatch(of: password) != nil
        }
    }

    private static func validateSchedule(_ html: String) throws {
        do {
            _ = try AcademicHTML.schedule(html)
        } catch {
            throw ProviderFailure.temporarilyUnavailable
        }
    }

    private static func sendEphemeral(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: AcademicRedirectStopper(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderFailure.temporarilyUnavailable }
        return (data, response)
    }
}

private actor AcademicRequestGate {
    private let interval: Duration
    private var lastStart: ContinuousClock.Instant?
    private var inFlight = false
    private var waiters: [(UUID, CheckedContinuation<Void, any Error>)] = []

    init(interval: Duration) { self.interval = interval }

    func perform(_ request: URLRequest, send: AcademicProvider.Send) async throws -> (Data, HTTPURLResponse) {
        try await acquire()
        defer { release() }
        if let lastStart {
            try await ContinuousClock().sleep(until: lastStart.advanced(by: interval))
        }
        try Task.checkCancellation()
        lastStart = ContinuousClock.now
        let result = try await send(request)
        try Task.checkCancellation()
        return result
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard inFlight else {
            inFlight = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters.append((id, $0)) }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            inFlight = false
        } else {
            waiters.removeFirst().1.resume()
        }
    }
}

private final class AcademicRedirectStopper: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Keep Foundation's full cookie attributes and a private, in-memory jar for each call.
private final class AcademicCookies {
    private let storage = URLSessionConfiguration.ephemeral.httpCookieStorage!

    init(_ cookies: [HTTPCookie]) {
        store(cookies, from: AcademicProvider.loginURL)
    }

    convenience init(session: ProviderSession) throws {
        guard let object = try? PropertyListSerialization.propertyList(from: session.credential, format: nil),
              let records = object as? [[String: Any]] else { throw ProviderFailure.actionRequired }
        let cookies = records.compactMap { record in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: record.map {
                (HTTPCookiePropertyKey(rawValue: $0.key), $0.value)
            }))
        }
        guard records.count == cookies.count else { throw ProviderFailure.actionRequired }
        self.init(cookies)
        guard !isEmpty else { throw ProviderFailure.expired }
    }

    var isEmpty: Bool { storage.cookies?.isEmpty != false }

    func apply(_ response: HTTPURLResponse, from url: URL) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { headers, entry in
            if let name = entry.key as? String, let value = entry.value as? String {
                headers[name] = value
            }
        }
        store(HTTPCookie.cookies(withResponseHeaderFields: headers, for: url), from: url)
    }

    private func store(_ cookies: [HTTPCookie], from url: URL) {
        let allowedDomains = ["jw.educationgroup.cn", ".jw.educationgroup.cn", ".educationgroup.cn"]
        for cookie in cookies where allowedDomains.contains(cookie.domain.lowercased()) {
            if let expiration = cookie.expiresDate, expiration <= Date() {
                for stored in storage.cookies ?? [] where
                    stored.name == cookie.name && stored.path == cookie.path &&
                    stored.domain.lowercased() == cookie.domain.lowercased() {
                    storage.deleteCookie(stored)
                }
            } else {
                storage.setCookies([cookie], for: url, mainDocumentURL: AcademicProvider.loginURL)
            }
        }
    }

    func header(for url: URL) -> String? {
        HTTPCookie.requestHeaderFields(with: storage.cookies(for: url) ?? [])["Cookie"]
    }

    func session(for accountID: String) throws -> ProviderSession {
        guard let cookies = storage.cookies, !cookies.isEmpty else { throw ProviderFailure.expired }
        let sorted = cookies.sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
        let records = sorted.compactMap { cookie in
            cookie.properties.map { properties in
                Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) })
            }
        }
        guard records.count == cookies.count,
              let data = try? PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0) else {
            throw ProviderFailure.temporarilyUnavailable
        }
        return ProviderSession(remoteUserID: accountID, credential: data)
    }
}
