import XCTest

final class FirstLaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testHomeOpensWithoutAnAccountAndExplainsTheCourseSchedule() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-local-authorization")
        app.launch()

        XCTAssertTrue(app.staticTexts["应刻"].waitForExistence(timeout: 8))
        let schedule = app.buttons["home.schedule"]
        XCTAssertTrue(schedule.exists)
        attachScreenshot(named: "首页", of: app)
        schedule.tap()

        XCTAssertTrue(app.navigationBars["强智教务"].waitForExistence(timeout: 5))
        let bind = app.buttons["academic.bind"]
        XCTAssertTrue(bind.waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        bind.tap()
        XCTAssertTrue(app.navigationBars["教务账号授权"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["academic.rememberSession"].exists)
        XCTAssertTrue(app.staticTexts["合成授权页"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(bind.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccountsListShowsFourSeparateUnboundPlatforms() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["校园账号"].tap()

        XCTAssertTrue(app.staticTexts["校园账号"].waitForExistence(timeout: 5))
        for id in ["academic", "chaoxing", "campusSSO", "secondClassroom"] {
            let row = app.buttons["accounts.\(id)"]
            assertStatus("未绑定", for: row)
        }

        attachScreenshot(named: "校园账号", of: app)
        app.buttons["accounts.secondClassroom"].tap()
        XCTAssertTrue(app.navigationBars["到梦空间"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当前版本暂未开放绑定"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnlinkRequiresConfirmationAndOnlyChangesTheSelectedPlatform() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-bound-accounts")
        app.launch()
        app.tabBars.buttons["校园账号"].tap()

        let academic = app.buttons["accounts.academic"]
        assertStatus("已绑定", for: academic)
        academic.tap()

        let unlink = app.buttons["解绑账号"]
        XCTAssertTrue(unlink.waitForExistence(timeout: 5))
        unlink.tap()
        let confirm = app.buttons["解绑并清理本机数据"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["已绑定"].exists)

        unlink.tap()
        confirm.tap()
        XCTAssertTrue(app.staticTexts["当前版本暂未开放绑定"].waitForExistence(timeout: 5))
        app.navigationBars["强智教务"].buttons.firstMatch.tap()
        assertStatus("未绑定", for: academic)
        assertStatus("已绑定", for: app.buttons["accounts.chaoxing"])
    }

    @MainActor
    func testTimetableIsFullScreenAndSwipesFromTheCurrentWeek() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-bound-accounts")
        app.launch()
        openTimetableFromHome(app)

        let timetable = app.navigationBars["课程表"]
        XCTAssertTrue(timetable.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["首页"].isHittable)
        let week = app.buttons["academic.schedule.week"]
        assertValue("第3周", for: week)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "同步于")).firstMatch.exists)

        // The fixture serves one whole-semester payload and rejects week-specific requests.
        let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.46))
        let otherSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.19, dy: 0.46))
        page.press(forDuration: 0.05, thenDragTo: otherSide)
        assertValue("第4周", for: week)
        XCTAssertTrue(app.staticTexts["本周没有课程"].waitForExistence(timeout: 5))
        otherSide.press(forDuration: 0.05, thenDragTo: page)
        assertValue("第3周", for: week)
        XCTAssertTrue(app.buttons["academic.schedule.lesson.0"].isHittable)

        timetable.buttons.firstMatch.tap()
        openTimetableFromHome(app)
        assertValue("第3周", for: app.buttons["academic.schedule.week"])
        XCTAssertTrue(app.buttons["academic.schedule.lesson.0"].isHittable)
    }

    @MainActor
    func testAcademicScheduleShowsClassesAndAnEmptyWeek() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-bound-accounts")
        app.launch()
        openTimetableFromHome(app)
        let lesson = app.buttons["academic.schedule.lesson.0"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        attachScreenshot(named: "课表周视图", of: app)
        lesson.tap()
        let detail = app.navigationBars["课程详情"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["教学楼 A302"].exists)
        attachScreenshot(named: "课程详情", of: app)
        detail.buttons["完成"].tap()
        app.buttons["academic.schedule.mode.day"].tap()
        XCTAssertTrue(app.buttons["academic.schedule.lesson.0"].waitForExistence(timeout: 5))
        attachScreenshot(named: "课表单日视图", of: app)
        app.buttons["academic.schedule.day.2"].tap()
        XCTAssertTrue(app.staticTexts["academic.schedule.dayEmpty"].exists)
        app.buttons["academic.schedule.mode.week"].tap()
        XCTAssertTrue(app.buttons["academic.schedule.day.7"].isHittable)
        app.buttons["academic.schedule.nextWeek"].tap()
        XCTAssertTrue(app.staticTexts["本周没有课程"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["academic.schedule.freshness"].exists)

        app.buttons["academic.schedule.term"].tap()
        app.buttons["下一学期"].tap()
        let weekPicker = app.buttons["academic.schedule.week"]
        let newWeek = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "第1周"), object: weekPicker)
        XCTAssertEqual(XCTWaiter.wait(for: [newWeek], timeout: 5), .completed)

        app.navigationBars["课程表"].buttons.firstMatch.tap()
        app.tabBars.buttons["校园账号"].tap()
        app.buttons["accounts.academic"].tap()
        app.buttons["解绑账号"].tap()
        app.buttons["解绑并清理本机数据"].tap()
        XCTAssertTrue(app.staticTexts["未绑定"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        app.buttons["home.schedule"].tap()
        XCTAssertTrue(app.navigationBars["强智教务"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["academic.service.schedule"].exists)
        XCTAssertFalse(lesson.exists)
    }

    @MainActor
    func testFailedTermSwitchDoesNotOfferWeeksFromThePreviousTerm() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-bound-accounts")
        app.launch()
        openTimetableFromHome(app)

        let term = app.buttons["academic.schedule.term"]
        XCTAssertTrue(term.waitForExistence(timeout: 5))
        term.tap()
        app.buttons["暂不可用学期"].tap()
        XCTAssertTrue(app.staticTexts["academic.schedule.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(term.isEnabled)
        XCTAssertFalse(app.buttons["academic.schedule.lesson.0"].exists)
        XCTAssertFalse(app.buttons["academic.schedule.week"].exists)
        XCTAssertFalse(app.buttons["academic.schedule.nextWeek"].exists)

        term.tap()
        app.buttons["示例学期"].tap()
        XCTAssertTrue(app.buttons["academic.schedule.lesson.0"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openTimetableFromHome(_ app: XCUIApplication) {
        let entry = app.buttons["home.schedule"]
        assertStatus("查看本周课程安排", for: entry)
        entry.tap()
    }

    @MainActor
    private func assertValue(_ value: String, for element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func assertStatus(_ status: String, for row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == true AND label CONTAINS %@", status)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func attachScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
