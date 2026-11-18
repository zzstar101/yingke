import CampusCore
import SwiftUI

extension AcademicEndpoint {
    var title: String {
        switch self {
        case .schedule, .semesterSchedule: "课程表"
        case .grades: "成绩查询"
        case .exams: "考试安排"
        case .plan: "培养方案"
        }
    }

    fileprivate var viewID: String {
        switch self {
        case .schedule, .semesterSchedule: "schedule"
        case .grades: "grades"
        case .exams: "exams"
        case .plan: "plan"
        }
    }

    fileprivate var emptyTitle: String {
        switch self {
        case .schedule, .semesterSchedule: "当前筛选没有课程"
        case .grades: "当前筛选没有成绩"
        case .exams: "教务系统未返回考试安排"
        case .plan: "教务系统未返回培养方案记录"
        }
    }

    fileprivate var verificationNote: String? {
        switch self {
        case .schedule, .semesterSchedule, .grades: nil
        case .exams: "考试明细尚待真实记录验证，请以教务系统为准。"
        case .plan: "培养方案的字段映射尚未完整验证，请以教务系统为准。"
        }
    }
}

struct AcademicDataView: View {
    let endpoint: AcademicEndpoint
    let load: @MainActor (AcademicEndpoint, [String: String]?, Bool) async throws -> AcademicDataResult

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var request = Request()
    @State private var completedRequest: Request?
    @State private var previous: LoadedResult?
    @State private var failure: String?
    @State private var gradeTerms: [AcademicOption] = []
    @State private var localGradeTerm: String?

    private struct Request: Equatable {
        var fields: [String: String]?
        var revision = 0
        var forceRefresh = false
    }

    private struct LoadedResult {
        let fields: [String: String]?
        let data: AcademicDataResult
    }

    private static let gradeTermKey = "kksj"

    private var loading: Bool { completedRequest != request }

    private var current: AcademicDataResult? {
        guard let previous, previous.fields == request.fields else { return nil }
        return previous.data
    }

    var body: some View {
        let query = request
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                filters
                if let note = endpoint.verificationNote {
                    statusLabel(note, symbol: "info.circle", suffix: "verification")
                }
                if let current {
                    freshness(current)
                }
                if loading {
                    ProgressView(current == nil ? "正在读取教务数据" : "正在同步教务数据")
                        .tint(CampusTheme.accent)
                        .foregroundStyle(CampusTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .academicSurface()
                        .accessibilityIdentifier(id("loading"))
                } else if let failure {
                    failurePanel(failure)
                }
                if let current {
                    results(current.content)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            .campusColumn()
        }
        .background(CampusTheme.background.ignoresSafeArea())
        .tint(CampusTheme.accent)
        .navigationTitle(endpoint.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Label("刷新教务数据", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
                .accessibilityIdentifier(id("refresh"))
            }
        }
        .task(id: query) { await fetch(query) }
    }

    private func id(_ suffix: String) -> String {
        "academic.\(endpoint.viewID).\(suffix)"
    }

    private func reload() {
        request.revision += 1
        request.forceRefresh = true
    }

    private func select(_ fields: [String: String]) {
        guard request.fields != fields else { return }
        request = Request(fields: fields, revision: request.revision + 1)
    }

    private func fetch(_ query: Request) async {
        guard !Task.isCancelled, query == request, completedRequest != query else { return }
        failure = nil
        defer {
            if !Task.isCancelled, query == request { completedRequest = query }
        }
        do {
            let data = try await load(endpoint, query.fields, query.forceRefresh)
            guard !Task.isCancelled, query == request else { return }
            previous = LoadedResult(fields: query.fields, data: data)
            if case let .grades(grades) = data.content, !grades.terms.isEmpty {
                gradeTerms = grades.terms
                localGradeTerm = nil
            }
        } catch {
            guard !Task.isCancelled, query == request else { return }
            if let providerFailure = error as? ProviderFailure,
               providerFailure == .expired || providerFailure == .actionRequired {
                failure = "教务会话需要重新授权。请返回强智教务重新授权后再试。"
            } else if error as? SessionFailure == .busy {
                failure = "另一个页面正在同步教务数据，请稍后重试。"
            } else if error is AcademicHTML.Error {
                failure = "暂时无法读取教务页面的结构。请稍后重试，或到教务系统查看。"
            } else {
                failure = "暂时无法读取教务数据。请检查网络后重试。"
            }
        }
    }

    @ViewBuilder private var filters: some View {
        switch previous?.data.content {
        case let .grades(grades):
            gradeFilter(grades)
        case .schedule, .exams, .plan, nil:
            EmptyView()
        }
    }

    @ViewBuilder private func gradeFilter(_ grades: AcademicGrades) -> some View {
        if !gradeTerms.isEmpty {
            let requestedTerm = request.fields?[Self.gradeTermKey]
            let selected = current == nil ? requestedTerm : grades.selectedTerm ?? requestedTerm
            filter("开课学期", suffix: "term", options: gradeTerms, selection: selected) { value in
                select([Self.gradeTermKey: value])
            }
            .academicSurface()
        } else if request.fields == nil {
            let terms = Set(grades.rows.compactMap(\.term).filter { !$0.isEmpty }).sorted(by: >)
            if !terms.isEmpty {
                let options = [AcademicOption(value: "", label: "全部学期")] + terms.map { AcademicOption(value: $0, label: $0) }
                filter("开课学期", suffix: "term", options: options, selection: localGradeTerm ?? "") { value in
                    localGradeTerm = value.isEmpty ? nil : value
                }
                .academicSurface()
            }
        }
    }

    private func filter(
        _ title: String, suffix: String, options: [AcademicOption], selection: String?, action: @escaping (String) -> Void
    ) -> some View {
        let selectedLabel = options.first { $0.value == selection }?.label ?? selection ?? "选择"
        return Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    guard selection != option.value else { return }
                    action(option.value)
                } label: {
                    if selection == option.value {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(title)
                    .foregroundStyle(CampusTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(selectedLabel.isEmpty ? "全部" : selectedLabel)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CampusTheme.accent)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .disabled(loading || options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(selectedLabel.isEmpty ? "全部" : selectedLabel)
        .accessibilityIdentifier(id(suffix))
    }

    private func statusLabel(_ title: String, symbol: String, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(CampusTheme.accent)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id(suffix))
        }
        .font(.subheadline)
        .foregroundStyle(CampusTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CampusTheme.soft, in: RoundedRectangle(cornerRadius: 14))
    }

    private func freshness(_ result: AcademicDataResult) -> some View {
        let date = result.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let showingPrevious = !loading && failure != nil
        let text = if result.needsAuthorization {
            "教务会话需要重新授权 · 显示本机缓存 · 上次同步于 \(date)"
        } else if result.syncFailed {
            "同步失败 · 显示本机缓存 · 上次同步于 \(date)"
        } else if result.isCached {
            "本机缓存 · 同步于 \(date)"
        } else if showingPrevious {
            "正在显示上次结果 · 同步于 \(date)"
        } else {
            "同步于 \(date)"
        }
        return statusLabel(
            text, symbol: result.isCached || showingPrevious ? "clock.arrow.circlepath" : "checkmark.circle", suffix: "freshness"
        )
    }

    private func failurePanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同步失败")
                .font(.headline)
                .foregroundStyle(CampusTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(id("error"))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(CampusTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") { reload() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier(id("retry"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .academicSurface()
    }

    private func emptyState(_ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "tray")
                    .foregroundStyle(CampusTheme.accent)
                    .accessibilityHidden(true)
                Text(endpoint.emptyTitle)
                    .foregroundStyle(CampusTheme.ink)
                    .accessibilityIdentifier(id("empty"))
            }
            .font(.headline)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(CampusTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .academicSurface()
    }

    @ViewBuilder private func results(_ content: AcademicContent) -> some View {
        switch content {
        case .schedule: EmptyView()
        case let .grades(grades): gradeResults(grades)
        case let .exams(records), let .plan(records): recordResults(records)
        }
    }

    @ViewBuilder private func gradeResults(_ grades: AcademicGrades) -> some View {
        let rows = grades.rows.enumerated().filter { _, row in
            localGradeTerm == nil || localGradeTerm == row.term
        }
        if rows.isEmpty {
            emptyState("可以切换开课学期，再查询成绩。")
        } else {
            ForEach(rows, id: \.offset) { index, grade in
                gradeRow(grade)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(id("row.\(index)"))
            }
        }
    }

    private func gradeRow(_ grade: AcademicGrade) -> some View {
        let details = [
            ("课程编号", Optional(grade.courseCode)), ("开课学期", grade.term), ("学分", grade.credits), ("学时", grade.hours),
            ("绩点", grade.gradePoint), ("考试性质", grade.examType), ("课程性质", grade.courseNature), ("课程属性", grade.courseAttribute)
        ].compactMap { label, value -> (String, String)? in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                Text(grade.courseName)
                    .font(.headline)
                    .foregroundStyle(CampusTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(grade.grade)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(CampusTheme.accent)
                    .accessibilityLabel("成绩 \(grade.grade)")
            }
            fields(details)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .academicSurface()
    }

    @ViewBuilder private func recordResults(_ records: AcademicRecords) -> some View {
        if records.rows.isEmpty {
            emptyState()
        } else {
            ForEach(Array(records.rows.enumerated()), id: \.offset) { index, row in
                fields(records.columns.enumerated().map { offset, column in
                    let value = offset < row.count ? row[offset] : ""
                    return (column, value.isEmpty ? "—" : value)
                })
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .academicSurface()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(id("row.\(index)"))
            }
        }
    }

    private func fields(_ pairs: [(String, String)]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        fieldLabel(pair.0)
                        fieldValue(pair.1, label: pair.0)
                    }
                } else {
                    GridRow {
                        fieldLabel(pair.0)
                        fieldValue(pair.1, label: pair.0)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(CampusTheme.muted)
            .accessibilityHidden(true)
    }

    private func fieldValue(_ value: String, label: String) -> some View {
        Text(value)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(CampusTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(label)，\(value)")
    }
}

private extension View {
    func academicSurface() -> some View {
        self
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(CampusTheme.line)
                    .allowsHitTesting(false)
            }
    }
}
