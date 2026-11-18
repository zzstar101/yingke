import Foundation
import libxml2

public struct AcademicOption: Codable, Sendable, Equatable {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct AcademicPeriod: Codable, Sendable, Equatable {
    public let number: Int
    public let startTime: String
    public let endTime: String

    public init(number: Int, startTime: String, endTime: String) {
        self.number = number
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct AcademicLesson: Codable, Sendable, Hashable {
    public let courseName: String
    /// Monday is 1 and Sunday is 7.
    public let weekday: Int
    public let startPeriod: Int
    public let endPeriod: Int
    public let teacher: String?
    public let location: String?
    /// Sorted, distinct teaching weeks. An empty array means the page supplied no week set.
    public let weeks: [Int]
    public let weekLabel: String?

    public init(courseName: String, weekday: Int, startPeriod: Int, endPeriod: Int,
                teacher: String? = nil, location: String? = nil, weeks: [Int] = [], weekLabel: String? = nil) {
        self.courseName = courseName
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.teacher = teacher
        self.location = location
        self.weeks = weeks
        self.weekLabel = weekLabel
    }
}

public struct AcademicSchedule: Codable, Sendable, Equatable {
    public let terms: [AcademicOption]
    public let weeks: [AcademicOption]
    /// Selected term and any recognized period scheme. Legacy single-week queries also include the selected week.
    public let fields: [String: String]
    public let lessons: [AcademicLesson]
    /// Only periods for which the page supplied a start and end time.
    public let periods: [AcademicPeriod]
    public let periodSchemeField: String?
    public let periodSchemes: [AcademicOption]
    /// The teaching week at sync time, when it was available.
    public let currentTeachingWeek: Int?
    private let teachingWeekObservedAt: Date?

    public init(terms: [AcademicOption], weeks: [AcademicOption], fields: [String: String],
                lessons: [AcademicLesson], periods: [AcademicPeriod] = [], periodSchemeField: String? = nil,
                periodSchemes: [AcademicOption] = [], currentTeachingWeek: Int? = nil, teachingWeekObservedAt: Date? = nil) {
        self.terms = terms
        self.weeks = weeks
        self.fields = fields
        self.lessons = lessons
        self.periods = periods
        self.periodSchemeField = periodSchemeField
        self.periodSchemes = periodSchemes
        self.currentTeachingWeek = currentTeachingWeek
        self.teachingWeekObservedAt = teachingWeekObservedAt
    }

    /// Resolves the cached teaching week using local Mondays in Asia/Shanghai.
    public func teachingWeek(on date: Date = .now) -> Int? {
        let week: Int?
        if let currentTeachingWeek {
            if let teachingWeekObservedAt {
                week = AcademicTeachingCalendar.weeks(from: teachingWeekObservedAt, to: date).map { currentTeachingWeek + $0 }
            } else {
                week = currentTeachingWeek
            }
        } else {
            week = AcademicTeachingCalendar.publishedWeek(for: fields["xnxq01id"], on: date)
        }
        guard let week, week > 0, weeks.contains(where: { Int($0.value) == week }) else { return nil }
        return week
    }

    public func lessons(inTeachingWeek week: Int) -> [AcademicLesson] {
        lessons.filter { $0.weeks.contains(week) }
    }
}

private enum AcademicTeachingCalendar {
    static var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func weeks(from start: Date, to date: Date) -> Int? {
        let calendar = shanghaiCalendar
        guard let startMonday = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
              let endMonday = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let days = calendar.dateComponents([.day], from: startMonday, to: endMonday).day else { return nil }
        return days / 7
    }

    static func publishedWeek(for term: String?, on date: Date) -> Int? {
        // GZASC 2026–2027 published teaching calendar: https://www.gzasc.edu.cn/news/info/1003/52260.htm
        let start: DateComponents
        let count: Int
        switch term {
        case "2026-2027-1": start = DateComponents(year: 2026, month: 8, day: 31); count = 20
        case "2026-2027-2": start = DateComponents(year: 2027, month: 3, day: 1); count = 19
        default: return nil
        }
        guard let monday = shanghaiCalendar.date(from: start), let offset = weeks(from: monday, to: date),
              (0..<count).contains(offset) else { return nil }
        return offset + 1
    }
}

public struct AcademicGrade: Codable, Sendable, Equatable {
    public let courseName: String
    public let courseCode: String
    public let grade: String
    public let term: String?
    public let credits: String?
    public let hours: String?
    public let gradePoint: String?
    public let examType: String?
    public let courseNature: String?
    public let courseAttribute: String?

    public init(courseName: String, courseCode: String, grade: String, term: String? = nil,
                credits: String? = nil, hours: String? = nil, gradePoint: String? = nil, examType: String? = nil,
                courseNature: String? = nil, courseAttribute: String? = nil) {
        self.courseName = courseName
        self.courseCode = courseCode
        self.grade = grade
        self.term = term
        self.credits = credits
        self.hours = hours
        self.gradePoint = gradePoint
        self.examType = examType
        self.courseNature = courseNature
        self.courseAttribute = courseAttribute
    }
}

public struct AcademicGrades: Codable, Sendable, Equatable {
    public let rows: [AcademicGrade]
    public let terms: [AcademicOption]
    public let selectedTerm: String?

    public init(rows: [AcademicGrade], terms: [AcademicOption] = [], selectedTerm: String? = nil) {
        self.rows = rows
        self.terms = terms
        self.selectedTerm = selectedTerm
    }
}

/// A conservative projection of recognized academic table columns, retaining their display order.
public struct AcademicRecords: Codable, Sendable, Equatable {
    public let columns: [String]
    public let rows: [[String]]

    public init(columns: [String], rows: [[String]]) {
        self.columns = columns
        self.rows = rows
    }
}

public enum AcademicHTML {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unexpectedPage
    }

    public static func schedule(_ html: String) throws -> AcademicSchedule {
        try schedulePage(html).schedule
    }

    /// Recognizes the authenticated timetable page without interpreting its course rows.
    static func confirmSchedulePage(_ html: String) throws {
        try withPage(html) { page in
            let tables = page.descendants { $0.name == "table" && $0["id"] == "kbtable" }
            let filterNames = Set(page.descendants { $0.name == "select" || $0.name == "input" }.compactMap { $0["name"] })
            guard tables.count == 1, filterNames.isSuperset(of: ["xnxq01id", "zc"]) else {
                throw Error.unexpectedPage
            }
        }
    }

    struct ScheduleForm {
        let controls: [URLQueryItem]
        let filterIndices: [String: Int]
        let selected: [String: String]
        let terms: [AcademicOption]
        let weeks: [AcademicOption]
        let periodSchemeField: String?
        let periodSchemes: [AcademicOption]
        let action: String?
        let method: String?
        let allWeeksValue: String?
        let currentTeachingWeek: Int?

        var hasSelectedAllWeeks: Bool {
            guard let allWeeksValue else { return false }
            return selected["zc"] == allWeeksValue
        }

        func matches(_ selection: [String: String]) -> Bool {
            selection.allSatisfy { selected[$0.key] == $0.value }
        }

        func numericWeeks() throws -> [(number: Int, option: AcademicOption)] {
            let candidates = weeks.compactMap { option -> (number: Int, option: AcademicOption)? in
                guard option.value.match(#"^[0-9]{1,2}$"#) != nil,
                      let number = Int(option.value), (1...60).contains(number), option.value != allWeeksValue
                else { return nil }
                return (number, option)
            }
            guard Set(candidates.map(\.number)).count == candidates.count else { throw Error.unexpectedPage }
            return candidates.sorted { $0.number < $1.number }
        }
    }

    typealias TeachingWeekObservation = (number: Int, date: Date)

    static func semesterSchedule(_ html: String, observation: TeachingWeekObservation?) throws -> AcademicSchedule {
        try withScheduleForm(html) { table, form in
            guard form.hasSelectedAllWeeks else { throw Error.unexpectedPage }
            let (lessons, periods) = try timetable(table)
            guard lessons.allSatisfy({ !$0.weeks.isEmpty }) else { throw Error.unexpectedPage }
            let options = try form.numericWeeks().map(\.option)
            return semesterSchedule(form, options: options, lessons: lessons, periods: periods, observation: observation)
        }
    }

    static func combineScheduleWeeks(_ pages: [(week: Int, schedule: AcademicSchedule)], form: ScheduleForm,
                                     options: [AcademicOption], observation: TeachingWeekObservation?) throws -> AcademicSchedule {
        var orderedKeys: [AcademicLesson] = []
        var lessonWeeks: [AcademicLesson: [Int]] = [:]
        var periods: [Int: AcademicPeriod] = [:]
        var conflictingPeriods: Set<Int> = []
        for (week, schedule) in pages {
            for lesson in schedule.lessons {
                guard lesson.weeks.isEmpty || lesson.weeks.contains(week) else { throw Error.unexpectedPage }
                let key = AcademicLesson(courseName: lesson.courseName, weekday: lesson.weekday,
                    startPeriod: lesson.startPeriod, endPeriod: lesson.endPeriod, teacher: lesson.teacher, location: lesson.location)
                if lessonWeeks[key] == nil { orderedKeys.append(key) }
                if lessonWeeks[key]?.last != week { lessonWeeks[key, default: []].append(week) }
            }
            for period in schedule.periods {
                if let previous = periods.updateValue(period, forKey: period.number), previous != period {
                    conflictingPeriods.insert(period.number)
                }
            }
        }
        let lessons = orderedKeys.map { lesson in
            AcademicLesson(courseName: lesson.courseName, weekday: lesson.weekday,
                startPeriod: lesson.startPeriod, endPeriod: lesson.endPeriod, teacher: lesson.teacher, location: lesson.location,
                weeks: lessonWeeks[lesson] ?? [])
        }
        let consistentPeriods = periods.values.filter { !conflictingPeriods.contains($0.number) }.sorted { $0.number < $1.number }
        return semesterSchedule(form, options: options, lessons: lessons, periods: consistentPeriods, observation: observation)
    }

    private static func semesterSchedule(_ form: ScheduleForm, options: [AcademicOption], lessons: [AcademicLesson],
                                         periods: [AcademicPeriod], observation: TeachingWeekObservation?) -> AcademicSchedule {
        let availableWeeks = Set(options.compactMap { Int($0.value) })
        let observed = observation.flatMap { availableWeeks.contains($0.number) ? $0 : nil }
        return AcademicSchedule(terms: form.terms, weeks: options, fields: form.selected.filter { $0.key != "zc" },
                                lessons: lessons, periods: periods, periodSchemeField: form.periodSchemeField,
                                periodSchemes: form.periodSchemes, currentTeachingWeek: observed?.number,
                                teachingWeekObservedAt: observed?.date)
    }

    /// Extracts controls for an immediate filtered query, even if the default grid cannot be parsed.
    static func scheduleForm(_ html: String) throws -> ScheduleForm {
        try withScheduleForm(html) { _, form in form }
    }

    static func schedulePage(_ html: String) throws -> (schedule: AcademicSchedule, form: [URLQueryItem], filterIndices: [String: Int]) {
        try withScheduleForm(html) { table, form in
            let (lessons, periods) = try timetable(table)
            let schedule = AcademicSchedule(terms: form.terms, weeks: form.weeks, fields: form.selected,
                                            lessons: lessons, periods: periods, periodSchemeField: form.periodSchemeField,
                                            periodSchemes: form.periodSchemes)
            return (schedule, form.controls, form.filterIndices)
        }
    }

    private static func withScheduleForm<T>(_ html: String, extract: (HTMLNode, ScheduleForm) throws -> T) throws -> T {
        try withPage(html) { page in
            guard let table = page.descendants(where: { $0.name == "table" && $0["id"] == "kbtable" }).only,
                  let form = page.descendants(where: { $0.name == "form" }).filter({ form in
                      let names = form.formControls.map { $0["name"] }
                      return names.contains("xnxq01id") && names.contains("zc")
                  }).only,
                  let term = form.formControls.filter({ $0.name == "select" && $0["name"] == "xnxq01id" }).only,
                  let week = form.formControls.filter({ $0.name == "select" && $0["name"] == "zc" }).only
            else { throw Error.unexpectedPage }

            let fields = form.successfulFields()
            let scheme = periodScheme(in: form)
            let schemeName = scheme?["name"]
            var selected: [String: String] = [:]
            var filterIndices: [String: Int] = [:]
            for filter in [term, week] + (scheme.map { [$0] } ?? []) {
                let indices = fields.indices.filter { fields[$0].control.pointer == filter.pointer }
                guard let index = indices.only, let value = fields[index].item.value else {
                    throw Error.unexpectedPage
                }
                let name = fields[index].item.name
                selected[name] = value
                filterIndices[name] = index
            }
            guard selected["xnxq01id"]?.isEmpty == false else { throw Error.unexpectedPage }
            let allLabels = ["全部", "整学期", "全学期", "全部周", "所有周", "全部周次", "所有周次", "全部教学周", "所有教学周"]
            let weekOptions = week.optionNodes.filter { !$0.disabled }
            let allValue = weekOptions.filter { allLabels.contains($0.option.label.filter { !$0.isWhitespace }) }.only?["value"]
            let uniqueAllValue = allValue.flatMap { value in
                weekOptions.filter { $0.option.value == value }.count == 1 ? value : nil
            }
            let markedWeek = weekOptions.map(\.option).compactMap { option -> Int? in
                guard let value = Int(option.value), value > 0 else { return nil }
                let label = option.label.filter { !$0.isWhitespace }
                let suffix = label.match(#"^第?([0-9]{1,2})周[（(]当前(?:教学)?周[）)]$"#)?.first
                let prefix = label.match(#"^当前(?:教学)?周[:：]?第?([0-9]{1,2})周$"#)?.first
                guard (suffix ?? prefix).flatMap(Int.init) == value else { return nil }
                return value
            }.only
            return try extract(table, ScheduleForm(controls: fields.map(\.item), filterIndices: filterIndices,
                                                   selected: selected, terms: term.options, weeks: week.options,
                                                   periodSchemeField: schemeName, periodSchemes: scheme?.options ?? [],
                                                    action: form["action"], method: form["method"], allWeeksValue: uniqueAllValue,
                                                    currentTeachingWeek: markedWeek))
        }
    }

    private static func periodScheme(in form: HTMLNode) -> HTMLNode? {
        let labels = form.descendants { $0.name == "label" }
        let titles = ["节次方案", "节次设置", "作息方案", "作息时间"]
        return form.formControls.filter { control in
            guard control.name == "select", let name = control["name"], name != "xnxq01id", name != "zc",
                  !control.disabled, control["multiple"] == nil, control.selectedOption != nil else { return false }
            let identity = control["id"]
            let associated = labels.filter { label in
                (identity != nil && label["for"] == identity)
                    || control.ancestors.contains(where: { $0.pointer == label.pointer })
            }.map(\.text)
            return (associated + [control["title"] ?? "", control["aria-label"] ?? ""]).contains { label in
                titles.contains(where: label.hasPrefix)
            }
        }.only
    }

    private static func timetable(_ table: HTMLNode) throws -> ([AcademicLesson], [AcademicPeriod]) {
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        let grid = try TimetableGrid(rows: table.tableRows)
        guard let header = grid.rows.enumerated().compactMap({ rowIndex, row -> (Int, Int)? in
            let start = row.keys.sorted().first { column in
                let label = row[column]?.node.text ?? ""
                return label.hasPrefix("星期一") || label.hasPrefix("周一")
            }
            guard let start, start > 0, weekdays.enumerated().allSatisfy({ offset, day in
                let label = row[start + offset]?.node.text ?? ""
                return label.hasPrefix("星期\(day)") || label.hasPrefix("周\(day)")
                    || (day == "日" && (label.hasPrefix("星期天") || label.hasPrefix("周天")))
            }) else { return nil }
            return (rowIndex, start)
        }).only else { throw Error.unexpectedPage }

        let (headerRow, firstDay) = header
        if grid.rows.count == headerRow + 2,
           let cell = grid.rows[headerRow + 1][0], cell.width == firstDay + 7,
           grid.rows[headerRow + 1].count == cell.width,
           ["暂无课表", "暂无课程", "本周无课程", "本周没有课程"].contains(cell.node.text.normalizedMessage) {
            return ([], [])
        }
        var periodByRow: [Int: ClosedRange<Int>] = [:]
        var periods: [AcademicPeriod] = []
        var previousPeriod = 0
        for index in (headerRow + 1)..<grid.rows.count {
            let row = grid.rows[index]
            if isSectionRow(row, at: index) { continue }
            if index == grid.rows.count - 1, !periodByRow.isEmpty,
               isTrailingNoteRow(row, at: index, periodColumn: firstDay - 1) { continue }
            guard let periodCell = row[firstDay - 1], periodCell.firstRow == index,
                  let range = periodRange(periodCell.node.lines.first?.value ?? ""),
                  range.lowerBound > previousPeriod, range.upperBound <= 32
            else { throw Error.unexpectedPage }
            previousPeriod = range.upperBound
            periodByRow[index] = range
            // A grouped row's time is the whole block, not the time of an individual period.
            if range.lowerBound == range.upperBound,
               let times = periodCell.node.lines.map(\.value).joined(separator: " ").match(
                #"(?<![0-9])((?:[01]?[0-9]|2[0-3])[:：][0-5][0-9])\s*[-－–—~～至]\s*((?:[01]?[0-9]|2[0-3])[:：][0-5][0-9])(?![0-9])"#
            ) {
                periods.append(AcademicPeriod(number: range.lowerBound,
                    startTime: times[0].replacingOccurrences(of: "：", with: ":"),
                    endTime: times[1].replacingOccurrences(of: "：", with: ":")))
            }
        }
        guard !periodByRow.isEmpty else { throw Error.unexpectedPage }

        var lessons: [AcademicLesson] = []
        for index in periodByRow.keys.sorted() {
            guard let period = periodByRow[index] else { continue }
            for day in 1...7 {
                guard let cell = grid.rows[index][firstDay + day - 1], cell.width == 1,
                      let endPeriod = periodByRow[cell.lastRow] else { throw Error.unexpectedPage }
                guard cell.firstRow == index else { continue }
                lessons += try parseLessons(cell.node, weekday: day, startPeriod: period.lowerBound, endPeriod: endPeriod.upperBound)
            }
        }
        return (lessons, periods)
    }

    private static func isSectionRow(_ row: [Int: TimetableGrid.Cell], at index: Int) -> Bool {
        let cells = row.filter { $0.key == $0.value.firstColumn }.values
        guard !cells.isEmpty, cells.allSatisfy({ $0.firstRow == index && $0.lastRow == index }) else { return false }
        let labels = cells.flatMap { $0.node.lines.map(\.value) }.filter { !$0.isEmpty }
        guard let label = labels.only else { return false }
        return ["上午", "中午", "下午", "晚上", "晚间"].contains(label.trimmingCharacters(in: CharacterSet(charactersIn: ":： ")))
    }

    private static func isTrailingNoteRow(_ row: [Int: TimetableGrid.Cell], at index: Int, periodColumn: Int) -> Bool {
        guard let heading = row[periodColumn], heading.firstColumn == periodColumn,
              let label = heading.node.lines.only?.value,
              label.match(#"^[\p{Han}]{1,6}\s*[:：]$"#) != nil else { return false }
        guard row.values.allSatisfy({ $0.firstRow == index && $0.lastRow == index }) else { return false }
        if row.values.allSatisfy({ $0.firstColumn == periodColumn || $0.node.lines.isEmpty }) { return true }

        let title = label.trimmingCharacters(in: CharacterSet(charactersIn: ":： "))
        guard ["备注", "注", "说明"].contains(title), heading.width == 1,
              let body = row[periodColumn + 1], body.firstColumn == periodColumn + 1, body.width == 7,
              row.keys.allSatisfy({ (periodColumn...(periodColumn + 7)).contains($0) }) else { return false }
        return body.node.descendants { node in
            node.name == "table" || node.classes.contains("kbcontent") || node.classes.contains("kbcontent1")
        }.isEmpty
    }

    private static func periodRange(_ label: String) -> ClosedRange<Int>? {
        let label = label.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? label
        if let bounds = label.match(#"^(?:第\s*)?([0-9]{1,2})\s*[-－–—~～至]\s*([0-9]{1,2})\s*节"#),
           let start = Int(bounds[0]), let end = Int(bounds[1]), start > 0, end >= start {
            return start...end
        }
        if let digits = label.match(#"^(?:第\s*)?([0-9]{1,2})(?=\s|节|[（(]|$)"#)?.first,
           let number = Int(digits), number > 0 {
            return number...number
        }
        guard let ordinal = label.match(#"^第\s*([一二三四五六七八九十]+(?:\s*[-－–—~～至、，,]\s*[一二三四五六七八九十]+)?)\s*节"#)?.first else { return nil }
        let parts = ordinal.components(separatedBy: CharacterSet(charactersIn: "-－–—~～至、，,")).map { $0.collapsedWhitespace }
        if parts.count == 2, let start = chinesePeriod(parts[0]), let end = chinesePeriod(parts[1]), end >= start {
            return start...end
        }
        if let number = chinesePeriod(ordinal) { return number...number }
        // StrongQZ concatenates consecutive ordinals, including 第九十十一节.
        for start in 1..<chinesePeriodLabels.count {
            var remaining = ordinal[...]
            for end in start..<chinesePeriodLabels.count {
                let token = chinesePeriodLabels[end]
                guard remaining.hasPrefix(token) else { break }
                remaining = remaining.dropFirst(token.count)
                if remaining.isEmpty { return start...end }
            }
        }
        return nil
    }

    private static let chinesePeriodLabels: [String] = {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (0...32).map { number in
            let ones = digits[number % 10]
            if number < 10 { return ones }
            let tens = number < 20 ? "" : digits[number / 10]
            return tens + "十" + ones
        }
    }()

    private static func chinesePeriod(_ ordinal: String) -> Int? {
        guard !ordinal.isEmpty else { return nil }
        return chinesePeriodLabels.firstIndex(of: ordinal)
    }

    private static func parseLessons(_ cell: HTMLNode, weekday: Int, startPeriod: Int, endPeriod: Int) throws -> [AcademicLesson] {
        let courses = cell.descendants { $0.classes.contains("kbcontent") || $0.classes.contains("kbcontent1") }
            .filter { node in
                !node.ancestors.prefix(while: { $0.pointer != cell.pointer }).contains {
                    $0.classes.contains("kbcontent") || $0.classes.contains("kbcontent1")
                }
            }
        let full = courses.filter { $0.classes.contains("kbcontent") }.map(\.lines).filter { !$0.isEmpty }
        let compact = courses.filter { $0.classes.contains("kbcontent1") }.map(\.lines).filter { !$0.isEmpty }
        let blocks = full.isEmpty ? compact : full
        if blocks.isEmpty {
            guard cell.lines.isEmpty else { throw Error.unexpectedPage }
            return []
        }
        return try blocks.flatMap { lines in
            var segments: [[AcademicLine]] = []
            var segment: [AcademicLine] = []
            for line in lines {
                if line.value.match(#"^[-－–—_]{3,}$"#) != nil || (line.kind == .course && !segment.isEmpty) {
                    if !segment.isEmpty { segments.append(segment) }
                    segment = []
                    if line.kind != .course { continue }
                }
                segment.append(line)
            }
            if !segment.isEmpty { segments.append(segment) }
            return try segments.map { lines in
                try lesson(lines, weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod)
            }
        }
    }

    private static func lesson(_ lines: [AcademicLine], weekday: Int, startPeriod: Int, endPeriod: Int) throws -> AcademicLesson {
        var course: String?
        var teacher: String?
        var location: String?
        var weekText: String?
        for line in lines {
            let kind = line.kind ?? (line.value.match(#"^[第0-9].*[周週]"#) != nil ? .weeks : nil)
            switch kind {
            case .course: course = line.value
            case .teacher: teacher = line.value
            case .location: location = line.value
            case .weeks: weekText = line.value
            case nil:
                if course == nil { course = line.value }
            }
        }
        guard let course else { throw Error.unexpectedPage }
        let explicitPeriods = weekText?.match(#"[\[［【]\s*0*([0-9]{1,2})(?:\s*[-－–—~～至]\s*0*([0-9]{1,2}))?\s*节\s*[\]］】]"#)
        let lessonStart = explicitPeriods.flatMap { Int($0[0]) } ?? startPeriod
        let lessonEnd = explicitPeriods.flatMap { Int($0[1]) ?? Int($0[0]) } ?? endPeriod
        guard (1...32).contains(lessonStart), (lessonStart...32).contains(lessonEnd) else { throw Error.unexpectedPage }
        let weekLabel = weekText?.components(separatedBy: CharacterSet(charactersIn: "[［【")).first?.collapsedWhitespace
        let weeks = try weekLabel.map(weekSet) ?? []
        return AcademicLesson(courseName: course, weekday: weekday, startPeriod: lessonStart, endPeriod: lessonEnd,
                              teacher: teacher, location: location, weeks: weeks, weekLabel: weekLabel)
    }

    private static func weekSet(_ label: String) throws -> [Int] {
        let compact = label.filter { !$0.isWhitespace }.replacingOccurrences(of: "週", with: "周")
        var rangeList = compact
        var parity: Int?
        for suffix in ["(单周)", "（单周）", "(双周)", "（双周）"] where compact.hasSuffix(suffix) {
            parity = suffix.contains("单") ? 1 : 0
            rangeList = String(compact.dropLast(suffix.count))
            break
        }
        for suffix in ["(周)", "（周）", "周"] where rangeList.hasSuffix(suffix) {
            rangeList.removeLast(suffix.count)
            break
        }
        if rangeList.hasPrefix("第") { rangeList.removeFirst() }
        var result: Set<Int> = []
        for item in rangeList.components(separatedBy: CharacterSet(charactersIn: ",，、;；")) {
            guard let bounds = item.match(#"^([0-9]{1,2})(?:[-－–—~～至]([0-9]{1,2}))?([单双])?$"#),
                  let start = Int(bounds[0]), (1...60).contains(start) else { throw Error.unexpectedPage }
            let end = Int(bounds[1]) ?? start
            guard (start...60).contains(end) else { throw Error.unexpectedPage }
            let filter = bounds[2] == "单" ? 1 : bounds[2] == "双" ? 0 : parity
            result.formUnion((start...end).filter { filter == nil || $0 % 2 == filter })
        }
        guard !result.isEmpty else { throw Error.unexpectedPage }
        return result.sorted()
    }

    public static func grades(_ html: String) throws -> AcademicGrades {
        try withPage(html) { page in
            let aliases = [
                "courseName": ["课程名称", "课程名"],
                "courseCode": ["课程编号", "课程代码", "课程号"],
                "grade": ["成绩", "总评成绩", "最终成绩"],
                "term": ["开课学期", "学期", "学年学期"],
                "credits": ["学分"],
                "hours": ["学时", "总学时"],
                "gradePoint": ["绩点"],
                "examType": ["考试性质", "考核性质"],
                "courseNature": ["课程性质"],
                "courseAttribute": ["课程属性"],
            ]
            guard let table = page.descendants(where: { $0.name == "table" && $0["id"] == "dataList" }).only,
                  let schema = AcademicTable(node: table, recognizes: { Set($0).containsAny(aliases["courseName"] ?? [])
                      && Set($0).containsAny(aliases["courseCode"] ?? []) && Set($0).containsAny(aliases["grade"] ?? []) })
            else { throw Error.unexpectedPage }
            var fields: [String: Int] = [:]
            for (key, names) in aliases {
                let matches = schema.headers.indices.filter { names.contains(schema.headers[$0]) }
                guard matches.count <= 1 else { throw Error.unexpectedPage }
                fields[key] = matches.first
            }
            let rows = try schema.values().map { cells -> AcademicGrade in
                func value(_ key: String) -> String? {
                    fields[key].map { cells[$0] }.flatMap { $0.isEmpty ? nil : $0 }
                }
                guard let name = value("courseName"), let code = value("courseCode"), let grade = value("grade")
                else { throw Error.unexpectedPage }
                return AcademicGrade(courseName: name, courseCode: code, grade: grade, term: value("term"),
                    credits: value("credits"), hours: value("hours"), gradePoint: value("gradePoint"),
                    examType: value("examType"), courseNature: value("courseNature"), courseAttribute: value("courseAttribute"))
            }
            let term = page.descendants(where: { $0.name == "select" && $0["name"] == "kksj" }).only
            return AcademicGrades(rows: rows, terms: term?.options ?? [], selectedTerm: term?.selectedOption?.value)
        }
    }

    /// The empty response is documented. Populated exam table headers are provisional.
    public static func exams(_ html: String) throws -> AcademicRecords {
        try withPage(html) { page in
            let names = ["课程名称", "课程名"]
            let logistics = ["考试时间", "考试日期", "考试地点", "考试教室", "考场"]
            let tables = page.descendants(where: { $0.name == "table" }).compactMap { table in
                AcademicTable(node: table) { labels in
                    Set(labels).containsAny(names) && Set(labels).containsAny(logistics)
                }
            }
            if let table = tables.only {
                let allowed = Set(names + logistics + ["课程编号", "课程代码", "课程号", "考试场次", "考试类型", "考试性质", "座位号"])
                return try table.projected(to: allowed, required: [names, logistics])
            }
            let message = "当前学生没有考试安排"
            let emptyMessageVisible = page.lines.contains { $0.value.normalizedMessage == message }
                || page.descendants(where: { ["p", "div", "span", "td"].contains($0.name) && $0.text.normalizedMessage == message }).first != nil
            guard tables.isEmpty, emptyMessageVisible else { throw Error.unexpectedPage }
            return AcademicRecords(columns: [], rows: [])
        }
    }

    /// The curriculum table headings are provisional until confirmed against populated responses.
    public static func plan(_ html: String) throws -> AcademicRecords {
        try withPage(html) { page in
            let names = ["课程名称", "课程名"]
            let credits = ["学分"]
            let curriculum = ["课程性质", "课程属性", "课程类别", "课程类型", "建议修读学期", "建议学期", "开课学期"]
            let tables = page.descendants(where: { $0.name == "table" }).compactMap { table in
                AcademicTable(node: table) { labels in
                    let headers = Set(labels)
                    return headers.containsAny(names) && headers.containsAny(credits) && headers.containsAny(curriculum)
                }
            }
            guard let table = tables.only else { throw Error.unexpectedPage }
            let allowed = Set(names + credits + curriculum + ["课程编号", "课程代码", "课程号", "学时", "总学时", "考核方式"])
            return try table.projected(to: allowed, required: [names, credits])
        }
    }

    private static func withPage<T>(_ html: String, extract: (HTMLNode) throws -> T) throws -> T {
        guard !html.isEmpty, html.utf8.count <= 4 * 1024 * 1024 else { throw Error.unexpectedPage }
        // The system HTML parser recovers omitted end tags and decodes entities. It never renders
        // the document or runs scripts. Disable networking and avoid inserting a synthetic DTD.
        let options = HTML_PARSE_NONET.rawValue | HTML_PARSE_NOERROR.rawValue
            | HTML_PARSE_NOWARNING.rawValue | HTML_PARSE_NODEFDTD.rawValue
        guard let document = htmlReadMemory(html, Int32(html.utf8.count), nil, "UTF-8", Int32(options)) else {
            throw Error.unexpectedPage
        }
        defer { xmlFreeDoc(document) }
        guard let root = xmlDocGetRootElement(document) else { throw Error.unexpectedPage }
        return try extract(HTMLNode(pointer: root))
    }
}

private struct AcademicTable {
    let headers: [String]
    private let dataRows: [[HTMLNode]]

    init?(node: HTMLNode, recognizes: ([String]) -> Bool) {
        let rows = node.tableRows.map(\.tableCells)
        let headerRows = rows.indices.filter { index in
            isUnspanned(rows[index]) && recognizes(rows[index].map(\.text))
        }
        guard let index = headerRows.only else { return nil }
        headers = rows[index].map(\.text)
        dataRows = Array(rows.dropFirst(index + 1))
    }

    func values() throws -> [[String]] {
        if dataRows.count == 1, let message = dataRows[0].only?.text,
           Self.emptyMessages.contains(message.normalizedMessage) {
            return []
        }
        guard !dataRows.isEmpty else { throw AcademicHTML.Error.unexpectedPage }
        return try dataRows.map { row in
            guard row.count == headers.count, isUnspanned(row) else { throw AcademicHTML.Error.unexpectedPage }
            return row.map { $0.lines.map(\.value).joined(separator: " ") }
        }
    }

    func projected(to allowed: Set<String>, required: [[String]]) throws -> AcademicRecords {
        let columns = headers.indices.filter { allowed.contains(headers[$0]) }
        let labels = columns.map { headers[$0] }
        let distinctLabels = Set(labels)
        let requiredColumns = required.map { choices in columns.filter { choices.contains(headers[$0]) } }
        guard distinctLabels.count == labels.count, requiredColumns.allSatisfy({ !$0.isEmpty }) else {
            throw AcademicHTML.Error.unexpectedPage
        }
        let rows = try values().map { row in
            guard requiredColumns.allSatisfy({ group in group.contains(where: { !row[$0].isEmpty }) }) else {
                throw AcademicHTML.Error.unexpectedPage
            }
            return columns.map { row[$0] }
        }
        return AcademicRecords(columns: labels, rows: rows)
    }

    private static let emptyMessages: Set<String> = [
        "暂无数据", "无数据", "没有数据", "未查询到数据", "没有查询到数据", "未查询到相关数据",
        "没有查询到相关数据", "无相关数据", "暂无成绩", "未查询到成绩", "当前学生没有考试安排",
    ]
}

private func isUnspanned(_ cells: [HTMLNode]) -> Bool {
    cells.allSatisfy { ($0["colspan"] ?? "1") == "1" && ($0["rowspan"] ?? "1") == "1" }
}

private extension Set where Element == String {
    func containsAny(_ options: [String]) -> Bool { options.contains(where: contains) }
}

private struct TimetableGrid {
    struct Cell {
        let node: HTMLNode
        let width: Int
        let firstColumn: Int
        let firstRow: Int
        let lastRow: Int
    }

    let rows: [[Int: Cell]]

    init(rows sourceRows: [HTMLNode]) throws {
        var rows = Array(repeating: [Int: Cell](), count: sourceRows.count)
        for (index, row) in sourceRows.enumerated() {
            var column = 0
            for node in row.tableCells {
                while rows[index][column] != nil { column += 1 }
                let width = Int(node["colspan"] ?? "1") ?? 0
                let height = Int(node["rowspan"] ?? "1") ?? 0
                guard column < 32, (1...(32 - column)).contains(width),
                      (1...(rows.count - index)).contains(height) else { throw AcademicHTML.Error.unexpectedPage }
                let cell = Cell(node: node, width: width, firstColumn: column, firstRow: index, lastRow: index + height - 1)
                for coveredRow in index...cell.lastRow {
                    for coveredColumn in column..<(column + width) {
                        guard rows[coveredRow].updateValue(cell, forKey: coveredColumn) == nil else {
                            throw AcademicHTML.Error.unexpectedPage
                        }
                    }
                }
                column += width
            }
        }
        self.rows = rows
    }
}

private struct AcademicLine {
    enum Kind {
        case course, teacher, weeks, location

        init?(_ label: String?) {
            switch label?.collapsedWhitespace {
            case "课程名称", "课程名", "课程": self = .course
            case "老师", "教师", "任课教师", "授课教师": self = .teacher
            case "周次", "周次(节次)", "周次（节次）", "教学周": self = .weeks
            case "教室", "地点", "上课地点", "上课教室": self = .location
            default: return nil
            }
        }
    }

    let value: String
    let kind: Kind?
}

/// A borrowed libxml2 node. All traversal completes before `withPage` frees the document.
private struct HTMLNode {
    let pointer: xmlNodePtr

    var name: String { String(decodingCString: pointer.pointee.name, as: UTF8.self) }

    subscript(_ attribute: String) -> String? {
        guard let property = xmlHasProp(pointer, attribute) else { return nil }
        var value = ""
        var current = property.pointee.children
        while let child = current {
            if child.pointee.type == XML_TEXT_NODE, let content = child.pointee.content {
                value += String(decodingCString: content, as: UTF8.self)
            }
            current = child.pointee.next
        }
        return value
    }

    var children: [HTMLNode] {
        var nodes: [HTMLNode] = []
        var current = pointer.pointee.children
        while let child = current {
            if child.pointee.type == XML_ELEMENT_NODE {
                let node = HTMLNode(pointer: child)
                if !Self.ignoredTags.contains(node.name) { nodes.append(node) }
            }
            current = child.pointee.next
        }
        return nodes
    }

    private static let ignoredTags: Set<String> = ["script", "style", "template", "noscript"]

    var ancestors: [HTMLNode] {
        var nodes: [HTMLNode] = []
        var current = pointer.pointee.parent
        while let parent = current, parent.pointee.type == XML_ELEMENT_NODE {
            nodes.append(HTMLNode(pointer: parent))
            current = parent.pointee.parent
        }
        return nodes
    }

    func descendants(where include: (HTMLNode) -> Bool) -> [HTMLNode] {
        var matches: [HTMLNode] = []
        func visit(_ node: HTMLNode) {
            for child in node.children {
                if include(child) { matches.append(child) }
                visit(child)
            }
        }
        visit(self)
        return matches
    }

    var classes: [Substring] { (self["class"] ?? "").split(whereSeparator: \.isWhitespace) }

    var tableRows: [HTMLNode] {
        children.flatMap { child -> [HTMLNode] in
            switch child.name {
            case "tr": [child]
            case "thead", "tbody", "tfoot": child.children.filter { $0.name == "tr" }
            default: []
            }
        }
    }

    var tableCells: [HTMLNode] { children.filter { $0.name == "th" || $0.name == "td" } }

    var lines: [AcademicLine] {
        var lines: [AcademicLine] = []
        var runningText = ""
        func flush() {
            let value = runningText.collapsedWhitespace
            if !value.isEmpty { lines.append(AcademicLine(value: value, kind: nil)) }
            runningText = ""
        }
        func walk(_ node: HTMLNode) {
            node.forEachChild(text: { runningText += $0 }, element: { child in
                if child.name == "br" || child.name == "hr" {
                    flush()
                    if child.name == "hr" { lines.append(AcademicLine(value: "---", kind: nil)) }
                } else if let kind = AcademicLine.Kind(child["title"]) {
                    flush()
                    if !child.text.isEmpty { lines.append(AcademicLine(value: child.text, kind: kind)) }
                } else {
                    let block = child.name == "div" || child.name == "p"
                    if block { flush() }
                    walk(child)
                    if block { flush() }
                }
            })
        }
        walk(self)
        flush()
        return lines
    }

    var text: String {
        textContent.collapsedWhitespace
    }

    var textContent: String {
        var value = ""
        forEachChild(text: { value += $0 }, element: { value += $0.textContent })
        return value
    }

    func forEachChild(text: (String) -> Void, element: (HTMLNode) -> Void) {
        var current = pointer.pointee.children
        while let child = current {
            switch child.pointee.type {
            case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
                if let content = child.pointee.content { text(String(decodingCString: content, as: UTF8.self)) }
            case XML_ELEMENT_NODE:
                let node = HTMLNode(pointer: child)
                if !Self.ignoredTags.contains(node.name) { element(node) }
            default: break
            }
            current = child.pointee.next
        }
    }

    var disabled: Bool {
        self["disabled"] != nil || ancestors.contains {
            ($0.name == "optgroup" || $0.name == "fieldset") && $0["disabled"] != nil
        }
    }

    var formControls: [HTMLNode] {
        descendants(where: { control in
            ["input", "select", "textarea"].contains(control.name) && control["form"] == nil
                && control.ancestors.first(where: { $0.name == "form" })?.pointer == pointer
        })
    }

    var optionNodes: [HTMLNode] { descendants(where: { $0.name == "option" }) }

    var option: AcademicOption {
        AcademicOption(value: self["value"] ?? text, label: self["label"] ?? text)
    }

    var options: [AcademicOption] { optionNodes.filter { !$0.disabled }.map(\.option) }

    var selectedOption: AcademicOption? {
        if let selected = optionNodes.last(where: { $0["selected"] != nil }) {
            return selected.disabled ? nil : selected.option
        }
        return options.first
    }

    func successfulFields() -> [(control: HTMLNode, item: URLQueryItem)] {
        var result: [(control: HTMLNode, item: URLQueryItem)] = []
        for control in formControls where !control.disabled {
            guard let name = control["name"], !name.isEmpty else { continue }
            let value: String?
            switch control.name {
            case "select":
                if control["multiple"] != nil {
                    for option in control.optionNodes where !option.disabled && option["selected"] != nil {
                        result.append((control, URLQueryItem(name: name, value: option.option.value)))
                    }
                    continue
                } else {
                    value = control.selectedOption?.value
                }
            case "textarea":
                value = control.text
            default:
                switch control["type"]?.lowercased() {
                case "submit", "image", "reset", "button", "file", "password": value = nil
                case "checkbox", "radio": value = control["checked"] == nil ? nil : control["value"] ?? "on"
                default: value = control["value"] ?? ""
                }
            }
            if let value {
                result.append((control, URLQueryItem(name: name, value: value)))
            }
        }
        return result
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

private extension String {
    var collapsedWhitespace: String { split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    var normalizedMessage: String { trimmingCharacters(in: CharacterSet(charactersIn: "。！!")) }

    func match(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: self).map { String(self[$0]) } ?? ""
        }
    }
}
