import CampusCore
import SwiftUI
import WebKit

struct AcademicAuthorizationView: View {
    let model: AccountsModel
    @Environment(\.dismiss) private var dismiss
    @State private var rememberSession = false
    @State private var browser: WKWebView?
    @State private var readyToVerify = false
    @State private var verifying = false
    @State private var message: String?
    @State private var attempt = UUID()
    @State private var submissions = AcademicLoginSubmissions()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("在强智教务页面填写账号、密码和验证码。登录成功后，点「完成绑定」。")
                        .font(.subheadline)
                    Toggle("在本机保留登录会话", isOn: $rememberSession)
                        .accessibilityIdentifier("academic.rememberSession")
                        .disabled(verifying)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                Divider()
                AcademicLoginBrowser(submissions: submissions, attempt: attempt) { webView, ready, error in
                    browser = webView
                    readyToVerify = ready
                    message = error
                }
                .id(attempt)
                .allowsHitTesting(!verifying)
                Divider()
                VStack(spacing: 4) {
                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(CampusTheme.muted)
                    }
                    if verifying {
                        ProgressView("正在确认教务会话")
                            .padding(8)
                    } else {
                        Button("完成绑定") { Task { await verify() } }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .disabled(!readyToVerify)
                            .accessibilityIdentifier("academic.finishBinding")
                    }
                }
                .padding(8)
            }
            .background(CampusTheme.background)
            .navigationTitle("教务账号授权")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(verifying)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重开网页") {
                        browser = nil
                        message = nil
                        readyToVerify = false
                        attempt = UUID()
                    }
                    .disabled(verifying)
                }
            }
        }
        .interactiveDismissDisabled(verifying)
    }

    private func verify() async {
        guard let browser, readyToVerify, !verifying else { return }
        verifying = true
        defer { verifying = false }
        message = nil
        let cookies = await browser.configuration.websiteDataStore.httpCookieStore.allCookies()
        // The authorization page does not expose a verified stable account ID.
        // Use a new opaque identity per binding; never join it to a previous binding's cache.
        let authorization = AcademicAuthorization(cookies: cookies, accountID: UUID().uuidString)
        do {
            try await model.authorizeAcademic(authorization, persistence: rememberSession ? .keychain : .memoryOnly)
            dismiss()
        } catch ProviderFailure.expired {
            message = "教务登录尚未完成或会话已失效，请重新打开网页登录。"
        } catch ProviderFailure.actionRequired {
            message = "请先在教务网页完成验证码和登录。"
        } catch {
            message = "暂时无法确认教务会话。请检查网络后重试。"
        }
    }
}

@MainActor
private final class AcademicLoginSubmissions {
    private var lastSubmission: ContinuousClock.Instant?
    private var activeAttempt: UUID?

    func begin(_ attempt: UUID) -> Bool {
        let now = ContinuousClock.now
        guard activeAttempt == nil,
              lastSubmission.map({ $0.duration(to: now) >= .milliseconds(1200) }) ?? true else { return false }
        lastSubmission = now
        activeAttempt = attempt
        return true
    }

    func finish(_ attempt: UUID) {
        if activeAttempt == attempt { activeAttempt = nil }
    }
}

private struct AcademicLoginBrowser: UIViewRepresentable {
    let submissions: AcademicLoginSubmissions
    let attempt: UUID
    var didChange: (WKWebView, Bool, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(submissions: submissions, attempt: attempt, didChange: didChange) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.keyboardDismissMode = .interactive
        context.coordinator.load(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.didChange = didChange
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadingTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.finishSubmission()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var didChange: (WKWebView, Bool, String?) -> Void
        var loadingTask: Task<Void, Never>?
        private let submissions: AcademicLoginSubmissions
        private let attempt: UUID
        private var submitted = false

        func finishSubmission() { submissions.finish(attempt) }

        #if DEBUG
        private static var usesLocalFixture: Bool {
            ProcessInfo.processInfo.arguments.contains("--ui-test-local-authorization")
        }
        #endif

        fileprivate init(submissions: AcademicLoginSubmissions, attempt: UUID, didChange: @escaping (WKWebView, Bool, String?) -> Void) {
            self.submissions = submissions
            self.attempt = attempt
            self.didChange = didChange
        }

        func load(_ webView: WKWebView) {
            loadingTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                #if DEBUG
                if Self.usesLocalFixture {
                    webView.loadHTMLString("<p>合成授权页</p>", baseURL: nil)
                    return
                }
                #endif
                // The login form and its captcha/scripts are hosted on the same HTTPS origin.
                let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https://jw\\.educationgroup\\.cn(:443)?/gzasc_jsxsd/"},"action":{"type":"ignore-previous-rules"}}]"#
                do {
                    guard let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "yingke.academic.login.v1", encodedContentRuleList: rules
                    ), !Task.isCancelled else { return }
                    webView.configuration.userContentController.add(ruleList)
                    webView.load(URLRequest(url: AcademicProvider.loginURL))
                } catch {
                    guard !Task.isCancelled else { return }
                    didChange(webView, false, "暂时无法打开教务授权页，请重开网页。")
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            #if DEBUG
            if Self.usesLocalFixture, navigationAction.request.url?.absoluteString == "about:blank" {
                return .allow
            }
            #endif
            guard let url = navigationAction.request.url, AcademicProvider.permits(url),
                  let frame = navigationAction.targetFrame else { return .cancel }
            let method = navigationAction.request.httpMethod ?? "GET"
            if method == "POST" {
                guard frame.isMainFrame, url.path == "/gzasc_jsxsd/xk/LoginToXk" else { return .cancel }
                guard submissions.begin(attempt) else { return .cancel }
                submitted = true
                didChange(webView, false, nil)
            } else if method != "GET" || (submitted && navigationAction.navigationType == .linkActivated) {
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            #if DEBUG
            if Self.usesLocalFixture, navigationResponse.response.url?.absoluteString == "about:blank" {
                return .allow
            }
            #endif
            guard let url = navigationResponse.response.url, AcademicProvider.permits(url) else { return .cancel }
            if navigationResponse.isForMainFrame,
               let response = navigationResponse.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                finishSubmission()
                didChange(webView, false, "教务网页暂时不可用，请重开网页后再试。")
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finishSubmission()
            guard submitted, let url = webView.url, AcademicProvider.permits(url) else { return }
            webView.evaluateJavaScript("document.querySelector('input[type=password], input[name=RANDOMCODE]') === null") { [weak self, weak webView] result, _ in
                guard let self, let webView, webView.url == url else { return }
                self.didChange(webView, result as? Bool == true, nil)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            reportFailure(webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            reportFailure(webView, error: error)
        }

        private func reportFailure(_ webView: WKWebView, error: any Error) {
            guard (error as? URLError)?.code != .cancelled else { return }
            finishSubmission()
            didChange(webView, false, "教务网页加载失败，请检查网络后重开网页。")
        }
    }
}
