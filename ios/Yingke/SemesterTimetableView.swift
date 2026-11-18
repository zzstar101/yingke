import CampusCore
import SwiftUI

struct SemesterTimetableView: View {
    let load: @MainActor ([String: String]?, Bool) async throws -> AcademicDataResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = Query()
    @State private var completed: Query?
    @State private var result: AcademicDataResult?
    @State private var resultFields: [String: String]?
    @State private var defaultTerm: String?
    @State private var failure: String?
    @State private var week = 1
    @State private var dayMode = false
    @State private var day: Int?

    private struct Query: Equatable {
        var fields: [String: String]?
        var revision = 0
        var refresh = false
    }

    private static let termKey = "xnxq01id"
    private var loading: Bool { completed != query }

    private var schedule: AcademicSchedule? {
        guard resultFields == query.fields, case let .schedule(schedule)? = result?.content else { return nil }
        return schedule
    }

    private var knownSchedule: AcademicSchedule? {
        guard case let .schedule(schedule)? = result?.content else { return nil }
        return schedule
    }

    var body: some View {
        let request = query
        VStack(spacing: 0) {
            if let schedule {
                header(schedule)
                if let failure {
                    notice(failure)
                } else if result?.needsAuthorization == true {
                    notice("登录已失效，仍可查看已保存的课表")
                } else if result?.syncFailed == true {
                    notice("刷新失败，仍可查看已保存的课表")
                }
                weekPages(schedule)
            } else if loading {
                ProgressView("正在读取整学期课表")
                    .tint(CampusTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let knownSchedule {
                    HStack {
                        termMenu(knownSchedule)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
                ContentUnavailableView {
                    Label("同步失败", systemImage: "calendar.badge.exclamationmark")
                        .accessibilityIdentifier("academic.schedule.error")
                } description: {
                    Text(failure ?? "课表暂不可用。")
                } actions: {
                    Button("重试", action: refresh)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("academic.schedule.retry")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CampusTheme.background.ignoresSafeArea())
        .tint(CampusTheme.accent)
        .navigationTitle("课程表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if loading, schedule != nil {
                    ProgressView().accessibilityLabel("正在同步整学期课表")
                } else {
                    Button(action: refresh) {
                        Label("刷新整学期课表", systemImage: "arrow.clockwise")
                    }
                    .disabled(loading)
                    .accessibilityIdentifier("academic.schedule.refresh")
                }
            }
        }
        .task(id: request) { await fetch(request) }
    }

    private func header(_ schedule: AcademicSchedule) -> some View {
        let weeks = weekNumbers(schedule)
        let current = schedule.teachingWeek()
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                termMenu(schedule)
                Spacer(minLength: 4)
                if let field = schedule.periodSchemeField, schedule.periodSchemes.count > 1 {
                    Menu {
                        ForEach(schedule.periodSchemes, id: \.value) { option in
                            Button(option.label) { chooseScheme(option.value, field: field, schedule: schedule) }
                        }
                    } label: {
                        Label("节次方案", systemImage: "clock")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("academic.schedule.periodScheme")
                }
                if let current, weeks.contains(current), current != week {
                    Button("回本周") { setWeek(current) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("academic.schedule.thisWeek")
                }
            }
            HStack(spacing: 4) {
                arrow(-1, weeks: weeks)
                Menu {
                    ForEach(weeks, id: \.self) { choice in
                        Button("第\(choice)周", systemImage: choice == week ? "checkmark" : "calendar") { setWeek(choice) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("第\(week)周")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(CampusTheme.ink)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("教学周")
                .accessibilityValue("第\(week)周")
                .accessibilityHint("左右轻扫课表也可切换教学周")
                .accessibilityIdentifier("academic.schedule.week")
                arrow(1, weeks: weeks)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func termMenu(_ schedule: AcademicSchedule) -> some View {
        let selected = query.fields?[Self.termKey] ?? schedule.fields[Self.termKey]
        let label = schedule.terms.first { $0.value == selected }?.label ?? "选择学期"
        return Menu {
            ForEach(schedule.terms, id: \.value) { option in
                Button(option.label) { chooseTerm(option.value, selected: selected) }
            }
        } label: {
            Label(label, systemImage: "chevron.down")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(loading || schedule.terms.isEmpty)
        .accessibilityLabel("学期")
        .accessibilityValue(label)
        .accessibilityIdentifier("academic.schedule.term")
    }

    private func arrow(_ delta: Int, weeks: [Int]) -> some View {
        let destination = weeks.firstIndex(of: week).map { $0 + delta }.flatMap { weeks.indices.contains($0) ? weeks[$0] : nil }
        return Button {
            if let destination { setWeek(destination) }
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destination == nil ? CampusTheme.muted.opacity(0.5) : CampusTheme.accent)
        .disabled(destination == nil)
        .accessibilityLabel(delta < 0 ? "上一教学周" : "下一教学周")
        .accessibilityIdentifier(delta < 0 ? "academic.schedule.previousWeek" : "academic.schedule.nextWeek")
    }

    private func weekPages(_ schedule: AcademicSchedule) -> some View {
        TabView(selection: $week) {
            ForEach(weekNumbers(schedule), id: \.self) { number in
                ScrollView {
                    let lessons = schedule.lessons(inTeachingWeek: number)
                    if lessons.isEmpty {
                        ContentUnavailableView("本周没有课程", systemImage: "calendar")
                            .padding(.top, 40)
                            .accessibilityIdentifier("academic.schedule.empty")
                    } else {
                        AcademicTimetable(lessons: lessons, periods: schedule.periods,
                                          lastPeriod: schedule.lessons.map(\.endPeriod).max() ?? 1,
                                          dayMode: $dayMode, selectedDay: $day)
                            .padding(.top, 6)
                            .padding(.bottom, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CampusTheme.background)
                .accessibilityHidden(number != week)
                .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(CampusTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    private func setWeek(_ number: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { week = number }
    }

    private func weekNumbers(_ schedule: AcademicSchedule) -> [Int] {
        let offered = schedule.weeks.compactMap { Int($0.value) }.filter { (1...60).contains($0) }
        let courseWeeks = schedule.lessons.flatMap(\.weeks).filter { (1...60).contains($0) }
        let maximum = max(offered.max() ?? 1, courseWeeks.max() ?? 1)
        return Array(1...maximum)
    }

    private func chooseTerm(_ term: String, selected: String?) {
        guard term != selected else { return }
        let fields = term == defaultTerm ? nil : [Self.termKey: term]
        query = Query(fields: fields, revision: query.revision + 1)
    }

    private func chooseScheme(_ scheme: String, field: String, schedule: AcademicSchedule) {
        guard schedule.fields[field] != scheme, let term = schedule.fields[Self.termKey] else { return }
        query = Query(fields: [Self.termKey: term, field: scheme], revision: query.revision + 1)
    }

    private func refresh() {
        query = Query(fields: query.fields, revision: query.revision + 1, refresh: true)
    }

    private func fetch(_ request: Query) async {
        guard !Task.isCancelled, request == query, request != completed else { return }
        failure = nil
        defer { if !Task.isCancelled, request == query { completed = request } }
        do {
            let data = try await load(request.fields, request.refresh)
            guard !Task.isCancelled, query == request else { return }
            guard case let .schedule(timetable) = data.content else { throw AcademicHTML.Error.unexpectedPage }
            let available = weekNumbers(timetable)
            if schedule == nil || !available.contains(week) {
                week = timetable.teachingWeek().flatMap { available.contains($0) ? $0 : nil } ?? available[0]
                day = nil
            }
            if request.fields == nil { defaultTerm = timetable.fields[Self.termKey] }
            resultFields = request.fields
            result = data
        } catch {
            guard !Task.isCancelled, query == request else { return }
            switch error {
            case ProviderFailure.actionRequired, ProviderFailure.expired:
                failure = "请返回强智教务，重新授权后再试。"
            case SessionFailure.busy:
                failure = "另一个页面正在同步，请稍后重试。"
            case is AcademicHTML.Error:
                failure = "暂时无法完整读取整学期课表，请稍后重试。"
            default:
                failure = "暂时无法连接教务，请稍后重试。"
            }
        }
    }
}
