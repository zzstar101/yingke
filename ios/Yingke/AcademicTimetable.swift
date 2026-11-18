import CampusCore
import SwiftUI

struct AcademicTimetable: View {
    let lessons: [AcademicLesson]
    let periods: [AcademicPeriod]
    let lastPeriod: Int
    @Binding var dayMode: Bool
    @Binding var selectedDay: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: LessonBlock?

    private nonisolated static let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
    private static let rowHeight: CGFloat = 52
    private static let railWidth: CGFloat = 37
    private static let headerHeight: CGFloat = 46

    private var simpleLayout: Bool { typeSize >= .xxxLarge }
    private var showDay: Bool { dayMode || simpleLayout }

    var body: some View {
        let entries = lessons.enumerated().map { LessonEntry(id: $0.offset, lesson: $0.element) }
            .sorted { ($0.lesson.weekday, $0.lesson.startPeriod, $0.id) < ($1.lesson.weekday, $1.lesson.startPeriod, $1.id) }
        let activeDay = selectedDay ?? entries.first?.lesson.weekday ?? 1

        VStack(alignment: .leading, spacing: 12) {
            if !simpleLayout {
                modePicker(count: entries.count)
                    .padding(.horizontal, 16)
            }
            if showDay {
                dayPicker(activeDay)
                    .padding(.horizontal, 16)
                dayAgenda(entries.filter { $0.lesson.weekday == activeDay }, day: activeDay)
                    .padding(.horizontal, 16)
            } else {
                weekGrid(entries)
            }
        }
        .sheet(item: $detail) { block in
            TimetableLessonDetail(block: block, periods: periods)
        }
    }

    private func modePicker(count: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("\(count) 条课程安排")
                    .font(.subheadline)
                    .foregroundStyle(CampusTheme.muted)
                    .fixedSize()
                Spacer(minLength: 4)
                modeButtons
            }
            modeButtons
        }
    }

    private var modeButtons: some View {
        HStack(spacing: 2) {
            modeButton("周课表", icon: "calendar", day: false)
            modeButton("日程", icon: "list.bullet", day: true)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(3)
        .background(CampusTheme.soft, in: RoundedRectangle(cornerRadius: 13))
    }

    private func modeButton(_ title: String, icon: String, day: Bool) -> some View {
        Button {
            changeMode(day)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(dayMode == day ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(dayMode == day ? CampusTheme.accent : CampusTheme.muted)
                .background(dayMode == day ? CampusTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityAddTraits(dayMode == day ? .isSelected : [])
        .accessibilityIdentifier(day ? "academic.schedule.mode.day" : "academic.schedule.mode.week")
    }

    private func changeMode(_ day: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { dayMode = day }
    }

    @ViewBuilder private func dayPicker(_ day: Int) -> some View {
        if simpleLayout {
            dayMenu(day)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { index in
                        dayButton(index, selected: day == index, expanded: true)
                    }
                }
                .frame(minWidth: 7 * 44)
                .padding(3)
                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                dayMenu(day)
            }
        }
    }

    private func dayMenu(_ day: Int) -> some View {
        Menu {
            ForEach(1...7, id: \.self) { choice in
                Button(Self.dayName(choice)) { selectedDay = choice }
            }
        } label: {
            Label(Self.dayName(day), systemImage: "chevron.down")
                .font(.headline)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("选择星期")
        .accessibilityValue(Self.dayName(day))
        .accessibilityIdentifier("academic.schedule.dayMenu")
    }

    private func dayButton(_ day: Int, selected: Bool = false, expanded: Bool = false) -> some View {
        Button {
            selectedDay = day
            changeMode(true)
        } label: {
            Text(expanded ? Self.dayName(day) : Self.dayNames[day - 1])
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? CampusTheme.accent : CampusTheme.ink)
                .background(selected ? CampusTheme.soft : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityLabel(Self.dayName(day))
        .accessibilityHint(expanded ? "" : "查看当天课程")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("academic.schedule.day.\(day)")
    }

    private func weekGrid(_ entries: [LessonEntry]) -> some View {
        let last = max(lastPeriod, periods.map(\.number).max() ?? 0, 1)
        let gridHeight = CGFloat(last) * Self.rowHeight
        return GeometryReader { proxy in
            let preferredWidth = Self.railWidth + 7 * 44
            let inset = max(0, min(12, (proxy.size.width - preferredWidth) / 2))
            grid(entries, last: last, width: proxy.size.width - 2 * inset, height: gridHeight)
                .padding(.horizontal, inset)
        }
        .frame(height: Self.headerHeight + gridHeight)
    }

    private func grid(_ entries: [LessonEntry], last: Int, width: CGFloat, height: CGFloat) -> some View {
        let columnWidth = (width - Self.railWidth) / 7
        let rowHeight = Self.rowHeight
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("节次")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CampusTheme.muted)
                    .frame(width: Self.railWidth)
                    .accessibilityHidden(true)
                ForEach(1...7, id: \.self) { day in
                    dayButton(day)
                        .frame(width: columnWidth)
                        .background(day >= 6 ? CampusTheme.soft.opacity(0.36) : .clear)
                }
            }
            .frame(height: Self.headerHeight)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let rail = Self.railWidth
                    let weekend = rail + 5 * columnWidth
                    context.fill(Path(CGRect(x: weekend, y: 0, width: size.width - weekend, height: size.height)),
                                 with: .color(CampusTheme.soft.opacity(0.28)))
                    var lines = Path()
                    for index in 0..<7 {
                        let x = rail + CGFloat(index) * columnWidth
                        lines.move(to: CGPoint(x: x, y: 0))
                        lines.addLine(to: CGPoint(x: x, y: height))
                    }
                    for index in 0..<last {
                        let y = CGFloat(index) * rowHeight
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(CampusTheme.line), lineWidth: 0.6)
                }
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(1...last, id: \.self) { period in
                        VStack(spacing: 3) {
                            Text("\(period)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CampusTheme.ink)
                            if let time = periods.first(where: { $0.number == period })?.startTime {
                                Text(time)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(CampusTheme.muted)
                            }
                        }
                        .frame(width: Self.railWidth, height: rowHeight)
                    }
                }
                .accessibilityHidden(true)
                ForEach(LessonBlock.group(entries)) { block in
                    tile(block, height: CGFloat(block.end - block.start + 1) * rowHeight - 5, width: columnWidth - 2)
                        .offset(x: Self.railWidth + CGFloat(block.day - 1) * columnWidth + 1,
                                y: CGFloat(block.start - 1) * rowHeight + 2.5)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(width: width, height: Self.headerHeight + height)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).strokeBorder(CampusTheme.line).allowsHitTesting(false)
        }
    }

    private func tile(_ block: LessonBlock, height: CGFloat, width: CGFloat) -> some View {
        let lesson = block.entries[0].lesson
        return Button {
            detail = block
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.courseName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(height >= 90 ? 3 : 2)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
                if block.entries.count > 1 {
                    Text("共 \(block.entries.count) 条")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                } else if height >= 90, let location = lesson.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 7)
            .padding(.bottom, 3)
            .frame(width: width, height: height, alignment: .topLeading)
            .foregroundStyle(block.entries[0].color.ink)
            .background(block.entries[0].color.paper, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityLabel(block.entries.count == 1 ? lesson.courseName : "\(block.entries.count) 条课程安排，\(block.entries.map(\.lesson.courseName).joined(separator: "、"))")
        .accessibilityValue(block.entries.count == 1 ? lesson.summary(periods: periods) : "\(Self.dayName(block.day))，第 \(block.start) 至 \(block.end) 节")
        .accessibilityHint("查看课程详情")
        .accessibilityIdentifier("academic.schedule.lesson.\(block.id)")
    }

    @ViewBuilder private func dayAgenda(_ entries: [LessonEntry], day: Int) -> some View {
        if entries.isEmpty {
            Label("\(Self.dayName(day))没有课程", systemImage: "calendar")
                .font(.body)
                .foregroundStyle(CampusTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("academic.schedule.dayEmpty")
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id { Divider().padding(.horizontal, 14) }
                    agendaRow(entry)
                }
            }
            .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private func agendaRow(_ entry: LessonEntry) -> some View {
        let lesson = entry.lesson
        return Button {
            detail = LessonBlock(entries: [entry])
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Capsule()
                    .fill(entry.color.ink)
                    .frame(width: 4, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.courseName)
                        .font(.headline)
                        .foregroundStyle(CampusTheme.ink)
                    Text([lesson.periodLabel, lesson.timeLabel(periods), lesson.location]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(CampusTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CampusTheme.muted)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityLabel(lesson.courseName)
        .accessibilityValue(lesson.summary(periods: periods))
        .accessibilityIdentifier("academic.schedule.lesson.\(entry.id)")
    }

    nonisolated static func dayName(_ day: Int) -> String {
        day == 7 ? "周日" : "周\(dayNames[day - 1])"
    }
}

private struct LessonEntry: Identifiable {
    let id: Int
    let lesson: AcademicLesson

    var color: LessonColor {
        let index = lesson.courseName.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % LessonColor.colors.count }
        return LessonColor.colors[index]
    }
}

private struct LessonBlock: Identifiable {
    var entries: [LessonEntry]
    var id: Int { entries[0].id }
    var day: Int { entries[0].lesson.weekday }
    var start: Int { entries[0].lesson.startPeriod }
    var end: Int { entries.map(\.lesson.endPeriod).max() ?? start }

    static func group(_ sortedEntries: [LessonEntry]) -> [Self] {
        var result: [Self] = []
        for entry in sortedEntries {
            if let last = result.last, last.day == entry.lesson.weekday, entry.lesson.startPeriod <= last.end {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(Self(entries: [entry]))
            }
        }
        return result
    }
}

private struct LessonColor {
    let paper: Color
    let ink: Color

    init(_ lightPaper: UInt32, _ lightInk: UInt32, _ darkPaper: UInt32, _ darkInk: UInt32) {
        paper = CampusTheme.adaptive(lightPaper, darkPaper)
        ink = CampusTheme.adaptive(lightInk, darkInk)
    }

    static let colors: [Self] = [
        .init(0xDFEDDF, 0x1F4E36, 0x30483A, 0xD5EBD6),
        .init(0xE0E9F5, 0x26476C, 0x303F56, 0xD7E5F7),
        .init(0xF3E6CD, 0x604517, 0x4C3D28, 0xFBE5B6),
        .init(0xEFE2EF, 0x5B385C, 0x49374B, 0xF6DFF4),
        .init(0xF5E1D9, 0x663B2E, 0x50382F, 0xF9DFD4),
        .init(0xDDEDEB, 0x245451, 0x294744, 0xD0EBE8)
    ]
}

private struct TimetableLessonDetail: View {
    let block: LessonBlock
    let periods: [AcademicPeriod]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if block.entries.count > 1 {
                        Label("这个课格有 \(block.entries.count) 条课程安排", systemImage: "rectangle.on.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(CampusTheme.muted)
                    }
                    ForEach(block.entries) { entry in
                        lessonDetail(entry)
                    }
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(CampusTheme.background.ignoresSafeArea())
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .tint(CampusTheme.accent)
        .presentationDetents(block.entries.count > 1 || typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func lessonDetail(_ entry: LessonEntry) -> some View {
        let lesson = entry.lesson
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(AcademicTimetable.dayName(lesson.weekday)) · \(lesson.periodLabel)")
                    .font(.subheadline.weight(.semibold))
                Text(lesson.courseName)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let time = lesson.timeLabel(periods) {
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                }
            }
            .foregroundStyle(entry.color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(entry.color.paper)

            VStack(alignment: .leading, spacing: 12) {
                detailRow("教室", value: lesson.location, icon: "mappin.and.ellipse")
                detailRow("教师", value: lesson.teacher, icon: "person")
                detailRow("上课周次", value: lesson.displayWeeks, icon: "calendar")
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private func detailRow(_ title: String, value: String?, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(CampusTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(CampusTheme.muted)
                Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "教务未提供")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CampusTheme.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension AcademicLesson {
    var periodLabel: String {
        startPeriod == endPeriod ? "第 \(startPeriod) 节" : "第 \(startPeriod)–\(endPeriod) 节"
    }

    var displayWeeks: String? {
        weekLabel ?? (weeks.isEmpty ? nil : "第 \(weeks.map(String.init).joined(separator: "、")) 周")
    }

    func timeLabel(_ periods: [AcademicPeriod]) -> String? {
        guard let start = periods.first(where: { $0.number == startPeriod }),
              let end = periods.first(where: { $0.number == endPeriod }) else { return nil }
        return "\(start.startTime)–\(end.endTime)"
    }

    func summary(periods: [AcademicPeriod]) -> String {
        [AcademicTimetable.dayName(weekday), periodLabel, timeLabel(periods), location]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }
}
