@testable import CampusCore
import Foundation
import Testing

@Suite struct AcademicHTMLTests {
    @Test func cachedTeachingWeekAdvancesOnShanghaiMondayAndKeepsOnlyItsLessons() throws {
        let shanghaiSunday = Date(timeIntervalSince1970: 1_794_758_399) // 2026-11-15 23:59:59 in Shanghai
        let monday = shanghaiSunday.addingTimeInterval(1)
        let weeks = [10, 11, 12].map { AcademicOption(value: String($0), label: "第\($0)周") }
        let schedule = AcademicSchedule(terms: [], weeks: weeks, fields: ["xnxq01id": "synthetic"], lessons: [
            AcademicLesson(courseName: "单周课程", weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [11]),
            AcademicLesson(courseName: "后续课程", weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [12]),
        ], currentTeachingWeek: 11, teachingWeekObservedAt: shanghaiSunday)
        let cached = try JSONDecoder().decode(AcademicSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(cached.currentTeachingWeek == 11)
        #expect(cached.teachingWeek(on: shanghaiSunday) == 11)
        #expect(cached.teachingWeek(on: monday) == 12)
        #expect(cached.teachingWeek(on: monday.addingTimeInterval(7 * 86_400)) == nil)
        #expect(cached.lessons(inTeachingWeek: 12).map(\.courseName) == ["后续课程"])
    }

    @Test func teachingWeekUsesExactPublishedTeachingIntervalsAndDecodesOldCache() throws {
        let legacy = Data(#"{"terms":[],"weeks":[{"value":"3","label":"第3周"}],"fields":{"zc":"3"},"lessons":[],"periods":[],"periodSchemes":[]}"#.utf8)
        let old = try JSONDecoder().decode(AcademicSchedule.self, from: legacy)
        #expect(old.currentTeachingWeek == nil)
        #expect(old.teachingWeek() == nil)
        let fallStart = Date(timeIntervalSince1970: 1_788_105_600) // 2026-08-31 00:00 in Shanghai
        let springStart = Date(timeIntervalSince1970: 1_803_830_400) // 2027-03-01 00:00 in Shanghai
        let weeks = (1...20).map { AcademicOption(value: String($0), label: "第\($0)周") }
        let fall = AcademicSchedule(terms: [], weeks: weeks, fields: ["xnxq01id": "2026-2027-1"], lessons: [])
        let spring = AcademicSchedule(terms: [], weeks: weeks, fields: ["xnxq01id": "2026-2027-2"], lessons: [])
        #expect(fall.teachingWeek(on: fallStart.addingTimeInterval(-1)) == nil)
        #expect(fall.teachingWeek(on: fallStart) == 1)
        #expect(fall.teachingWeek(on: fallStart.addingTimeInterval(19 * 7 * 86_400)) == 20)
        #expect(fall.teachingWeek(on: fallStart.addingTimeInterval(20 * 7 * 86_400)) == nil)
        #expect(spring.teachingWeek(on: springStart) == 1)
        #expect(spring.teachingWeek(on: springStart.addingTimeInterval(18 * 7 * 86_400)) == 19)
        #expect(spring.teachingWeek(on: springStart.addingTimeInterval(19 * 7 * 86_400)) == nil)
    }

    @Test func scheduleUsesSelectedTermAndSuccessfulControlsFromTheScheduleForm() throws {
        let (schedule, form, _) = try AcademicHTML.schedulePage("""
            <form><input name="unrelated" value="ignored"></form>
            <FORM id=query>
              <select name=xnxq01id>
                <option value=synthetic-next>合成后续学期
                <option value=synthetic-current SELECTED>合成当前学期
              </select>
              <select name=zc><option value=2 disabled>第2周<option value=3>第3周</select>
              <input type=hidden name=jcfangan value="period&amp;plan">
              <input type=checkbox name=display value=detail checked>
              <input type=checkbox name=unchecked value=ignored>
              <input type=submit name=submit value=ignored>
              <input type=hidden disabled name=disabled value=ignored>
              <input type=password name=password value=ignored>
            </FORM>
            \(Self.emptyTimetable)
            """)

        #expect(schedule.terms == [
            AcademicOption(value: "synthetic-next", label: "合成后续学期"),
            AcademicOption(value: "synthetic-current", label: "合成当前学期"),
        ])
        #expect(schedule.weeks == [AcademicOption(value: "3", label: "第3周")])
        #expect(schedule.fields == ["xnxq01id": "synthetic-current", "zc": "3"])
        #expect(form == [
            URLQueryItem(name: "xnxq01id", value: "synthetic-current"),
            URLQueryItem(name: "zc", value: "3"),
            URLQueryItem(name: "jcfangan", value: "period&plan"),
            URLQueryItem(name: "display", value: "detail"),
        ])
    }

    @Test func scheduleExposesPeriodPlanOptionsUsingTheActualControlName() throws {
        let result = try AcademicHTML.schedule("""
            <form>
                <select name=xnxq01id><option value=synthetic>合成学期</option></select>
                <select name=zc><option value=1>第1周</option></select>
                <label for=scheme>节次方案：</label>
                <select id=scheme name=dynamicPeriodKey><option value=alpha>方案甲</option>
                    <option value=beta selected>方案乙</option></select>
            </form>
            \(Self.emptyTimetable)
            """)
        #expect(result.periodSchemeField == "dynamicPeriodKey")
        #expect(result.periodSchemes == [AcademicOption(value: "alpha", label: "方案甲"), AcademicOption(value: "beta", label: "方案乙")])
        #expect(result.fields["dynamicPeriodKey"] == "beta")
    }

    @Test func scheduleDistinguishesRecognizedEmptyGridsFromIncompleteOrUnknownMarkup() throws {
        #expect(try AcademicHTML.schedule(Self.scheduleForm + Self.emptyTimetable).lessons.isEmpty)
        let empty = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)<tr><td colspan=8>暂无课程</td></tr></table>
            """)
        #expect(empty.lessons.isEmpty)
        for html in [
            "<table id=kbtable>\(Self.weekdayHeader)<tr><th>1</th><td></td></tr></table>",
            "<table id=kbtable>\(Self.weekdayHeader)<tr><th>1</th><td><div class=newlayout>合成课程</div></td>\(String(repeating: "<td></td>", count: 6))</tr></table>",
        ] {
            #expect(throws: AcademicHTML.Error.unexpectedPage) { try AcademicHTML.schedule(Self.scheduleForm + html) }
        }
    }

    @Test func timetableReadsGroupedChinesePeriodsAndSkipsSectionLabels() throws {
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th colspan=8>上午：</th></tr>
            <tr><th>第一二节<br>08:05—09:50</th>
                <td><div class=kbcontent>合成课程甲</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            <tr><th>第三四节</th>
                \(String(repeating: "<td></td>", count: 6))
                <td><div class=kbcontent>合成课程乙</div></td></tr>
            <tr><th>第九十节</th>
                <td><div class=kbcontent>合成课程丙</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            </table>
            """)
        #expect(schedule.lessons.map(\.startPeriod) == [1, 3, 9])
        #expect(schedule.lessons.map(\.endPeriod) == [2, 4, 10])
        #expect(schedule.lessons.map(\.weekday) == [1, 7, 1])
        #expect(schedule.periods.isEmpty)
    }

    @Test func timetableReadsThreeConsecutiveChinesePeriods() throws {
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th>第九十十一节</th>
                <td><div class=kbcontent>合成晚间课程</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            </table>
            """)
        #expect(schedule.lessons.map(\.startPeriod) == [9])
        #expect(schedule.lessons.map(\.endPeriod) == [11])
    }

    @Test func timetableSkipsTrailingNoteRowWithoutDiscardingUnrecognizedCourseRows() throws {
        let closing = String(repeating: "<td>&nbsp;</td>", count: 7)
        let footer = "<tr><td>注：</td>\(closing)</tr>"
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th>第一节</th><td><div class=kbcontent>合成课程</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            \(footer)</table>
            """)
        #expect(schedule.lessons.map(\.courseName) == ["合成课程"])

        #expect(throws: AcademicHTML.Error.unexpectedPage) {
            try AcademicHTML.schedule(Self.scheduleForm + """
                <table id=kbtable>\(Self.weekdayHeader)
                <tr><th>第一节</th>\(closing)</tr>
                <tr><td>注：</td><td><div class=kbcontent>另一个合成课程</div></td>
                    \(String(repeating: "<td></td>", count: 6))</tr></table>
                """)
        }
    }

    @Test func timetableReadsRecognizedFooterWithTextAcrossSevenDays() throws {
        let grid = """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th>第九十十一节<br>18:00-20:30</th>
                <td><div class=kbcontent1>合成课程</div>
                <div class=kbcontent>合成课程<br><font title="老师">合成教师</font><br>
                    <font title="周次(节次)">2-4,6(周)[09-10-11节]</font><br>
                    <font title="教室">合成教室</font></div></td>
                \(String(repeating: "<td><div class=kbcontent1>&nbsp;</div><div class=kbcontent>&nbsp;</div></td>", count: 6))</tr>
            """
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + grid + """
            <tr><th>备注:</th><td colspan="7">合成说明 2-6周</td></tr></table>
            """)
        #expect(schedule.lessons.map(\.courseName) == ["合成课程"])
        #expect(schedule.lessons.map(\.startPeriod) == [9])
        #expect(schedule.lessons.map(\.endPeriod) == [11])
        #expect(schedule.lessons.map(\.weeks) == [[2, 3, 4, 6]])

        #expect(throws: AcademicHTML.Error.unexpectedPage) {
            try AcademicHTML.schedule(Self.scheduleForm + grid + """
                <tr><th>备注:</th><td colspan="7"><div class=kbcontent>潜在课程内容</div></td></tr></table>
                """)
        }
    }

    @Test func timetableReadsChinesePeriodLabels() throws {
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th>第一节<br>08:05—08:50</th>
                <td><div class=kbcontent>合成课程甲</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            <tr><th>第十一节</th>
                <td><div class=kbcontent>合成课程乙</div></td>
                \(String(repeating: "<td></td>", count: 6))</tr>
            </table>
            """)
        #expect(schedule.lessons.map(\.startPeriod) == [1, 11])
        #expect(schedule.lessons.map(\.endPeriod) == [1, 11])
        #expect(schedule.periods == [AcademicPeriod(number: 1, startTime: "08:05", endTime: "08:50")])
    }

    @Test func timetablePreservesWeekdaysAndSeparateTeacherWeekSegments() throws {
        let schedule = try AcademicHTML.schedule(Self.scheduleForm + """
            <table id=kbtable>\(Self.weekdayHeader)
            <tr><th>第1节<br>08:05—08:50</th>
              <td rowspan=2>
                <div class="kbcontent1">精简显示</div><div class="kbcontent">&nbsp;</div>
                <div class="kbcontent highlight">
                  合成课程甲<br><font title="老师">教师甲</font><br>
                  <font title="周次(节次)">1,3,7-9(周)[01-02节]</font><br><font title="教室">实验室A</font><br>
                  ---------------------<br>合成课程甲<br><font title="教师">教师乙</font>
                  <br><font title="周次(节次)">2-6双(周)[01-02节]</font>
                  <br><font title="教室">实验室B</font>
                </div>
              </td>
              \(String(repeating: "<td></td>", count: 5))
              <td><div class="kbcontent1">合成周日课程<br>第4、6周</div></td>
            </tr>
            <tr><th>2<br>09:15 - 10:00</th>\(String(repeating: "<td></td>", count: 6))</tr>
            </table>
            """)

        #expect(schedule.lessons == [
            AcademicLesson(courseName: "合成课程甲", weekday: 1, startPeriod: 1, endPeriod: 2,
                           teacher: "教师甲", location: "实验室A", weeks: [1, 3, 7, 8, 9], weekLabel: "1,3,7-9(周)"),
            AcademicLesson(courseName: "合成课程甲", weekday: 1, startPeriod: 1, endPeriod: 2,
                           teacher: "教师乙", location: "实验室B", weeks: [2, 4, 6], weekLabel: "2-6双(周)"),
            AcademicLesson(courseName: "合成周日课程", weekday: 7, startPeriod: 1, endPeriod: 1,
                           weeks: [4, 6], weekLabel: "第4、6周"),
        ])
        #expect(schedule.periods == [
            AcademicPeriod(number: 1, startTime: "08:05", endTime: "08:50"),
            AcademicPeriod(number: 2, startTime: "09:15", endTime: "10:00"),
        ])
    }

    @Test func gradesMapColumnsByHeadingAndIgnoreUnrelatedStudentData() throws {
        let result = try AcademicHTML.grades("""
            <select name=kksj><option value="">全部学期</option>
              <option value=synthetic selected>合成学期</option></select>
            <table id=dataList><thead><tr><th>成绩</th><th>课程名称</th><th>学分</th><th>课程代码</th>
              <th>开课学期</th><th>总学时</th><th>绩点</th><th>考试性质</th><th>课程性质</th>
              <th>课程属性</th><th>学号</th></tr></thead>
              <tbody><tr><td><a href="javascript:void(0)">优秀</a><td>合成 &amp; 练习<td>2.0<td>DEMO-1
              <td>合成学期<td>24<td>4.0<td>正常考核<td>通识<td>必修<td>IGNORE-PERSONAL-ATTRIBUTE</tbody>
            </table>
            """)

        #expect(result.rows == [AcademicGrade(courseName: "合成 & 练习", courseCode: "DEMO-1", grade: "优秀",
            term: "合成学期", credits: "2.0", hours: "24", gradePoint: "4.0", examType: "正常考核",
            courseNature: "通识", courseAttribute: "必修")])
        #expect(result.terms == [AcademicOption(value: "", label: "全部学期"), AcademicOption(value: "synthetic", label: "合成学期")])
        #expect(result.selectedTerm == "synthetic")
        let data = try JSONEncoder().encode(result)
        #expect(!String(decoding: data, as: UTF8.self).contains("IGNORE-PERSONAL-ATTRIBUTE"))
        #expect(try JSONDecoder().decode(AcademicGrades.self, from: data) == result)
    }

    @Test func gradesRequireRecognizedHeadersAndDistinguishEmptyFromMalformedRows() throws {
        let header = "<tr><th>课程名称</th><th>课程编号</th><th>成绩</th></tr>"
        let empty = try AcademicHTML.grades("<table id=dataList>\(header)<tr><td colspan=3>暂无数据</td></tr></table>")
        #expect(empty.rows.isEmpty)
        #expect(throws: AcademicHTML.Error.unexpectedPage) {
            try AcademicHTML.grades("<table id=dataList>\(header)<tr><td>合成课程</td><td>DEMO-1</td></tr></table>")
        }
        #expect(throws: AcademicHTML.Error.unexpectedPage) {
            try AcademicHTML.grades("<table id=dataList><tr><td>未查询到数据</td></tr></table>")
        }
    }

    @Test func examsRecognizeTheDocumentedEmptyMessageAndRejectUnknownTables() throws {
        #expect(try AcademicHTML.exams("<p>当前学生没有考试安排。</p>").rows.isEmpty)
        for html in [
            "<script>const unused = '当前学生没有考试安排'</script><p>服务异常</p>",
            "<table id=dataList><tr><th>课程名称</th><th>成绩</th></tr><tr><td>合成课程</td><td>90</td></tr></table>",
            "<table id=dataList><tr><th>课程名称</th><th>考试时间</th></tr><tr><td>合成课程</td></tr></table>",
        ] {
            #expect(throws: AcademicHTML.Error.unexpectedPage) { try AcademicHTML.exams(html) }
        }
    }

    @Test func syntheticExamTableProjectsKnownColumnsInSourceOrder() throws {
        let records = try AcademicHTML.exams("""
            <table id=dataList><tr><th>考试时间</th><th>学号</th><th>课程名称</th><th>考试地点</th></tr>
            <tr><td>09:30</td><td>IGNORE-PERSONAL-ATTRIBUTE</td><td>合成课程</td><td>合成教室</td></tr></table>
            """)
        #expect(records == AcademicRecords(columns: ["考试时间", "课程名称", "考试地点"],
                                           rows: [["09:30", "合成课程", "合成教室"]]))
    }

    @Test func syntheticPlanRequiresARecognizableCurriculumTable() throws {
        let records = try AcademicHTML.plan("""
            <table><tr><th>姓名</th><th>编号</th></tr><tr><td>合成信息</td><td>IGNORE</td></tr></table>
            <table><tr><th>课程名称</th><th>学分</th><th>学生姓名</th><th>课程性质</th><th>建议修读学期</th></tr>
            <tr><td>合成课程</td><td>2</td><td>IGNORE-PERSONAL-ATTRIBUTE</td><td>必修</td><td>3</td></tr></table>
            """)
        #expect(records == AcademicRecords(columns: ["课程名称", "学分", "课程性质", "建议修读学期"],
                                           rows: [["合成课程", "2", "必修", "3"]]))
        #expect(throws: AcademicHTML.Error.unexpectedPage) {
            try AcademicHTML.plan("<h2>培养方案</h2><table><tr><td>未识别的报表</td></tr></table>")
        }
    }

    private static let scheduleForm = """
        <form>
          <select name=xnxq01id><option value=synthetic>合成学期</option></select>
          <select name=zc><option value=1>第1周</option></select>
        </form>
        """

    private static let weekdayHeader = """
        <tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th>
        <th>星期五</th><th>星期六</th><th>星期日</th></tr>
        """

    private static let emptyTimetable = """
        <table id=kbtable>\(weekdayHeader)
        <tr><th>1</th>\(String(repeating: "<td>&nbsp;</td>", count: 7))</tr></table>
        """
}
