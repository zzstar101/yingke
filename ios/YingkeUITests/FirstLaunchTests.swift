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
    func testAcademicScheduleShowsClassesAndCachedEmptyWeek() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-bound-accounts")
        app.launch()
        app.buttons["home.schedule"].tap()
        let schedule = app.buttons["academic.service.schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.staticTexts["示例课程"].waitForExistence(timeout: 5))
        app.buttons["academic.schedule.week"].tap()
        app.buttons["第4周"].tap()
        XCTAssertTrue(app.staticTexts["当前筛选没有课程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["academic.schedule.freshness"].label.contains("缓存"))

        app.buttons["academic.schedule.term"].tap()
        app.buttons["下一学期"].tap()
        let weekPicker = app.buttons["academic.schedule.week"]
        let newWeek = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "第1周"), object: weekPicker)
        XCTAssertEqual(XCTWaiter.wait(for: [newWeek], timeout: 5), .completed)

        app.tabBars.buttons["校园账号"].tap()
        app.buttons["accounts.academic"].tap()
        app.buttons["解绑账号"].tap()
        app.buttons["解绑并清理本机数据"].tap()
        XCTAssertTrue(app.staticTexts["未绑定"].waitForExistence(timeout: 5))
        app.tabBars.buttons["首页"].tap()
        let removed = app.staticTexts["教务账号已解绑"]
        if !removed.waitForExistence(timeout: 4) {
            // SwiftUI can pop the old destination when its originating link is removed.
            XCTAssertTrue(app.navigationBars["强智教务"].exists)
        }
        XCTAssertFalse(app.staticTexts["academic.schedule.freshness"].exists)
        XCTAssertFalse(app.staticTexts["示例课程"].exists)
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
