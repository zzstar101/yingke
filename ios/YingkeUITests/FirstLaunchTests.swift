import XCTest

final class FirstLaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testHomeOpensWithoutAnAccountAndExplainsTheCourseSchedule() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["应刻"].waitForExistence(timeout: 8))
        let schedule = app.buttons["home.schedule"]
        XCTAssertTrue(schedule.exists)
        attachScreenshot(named: "首页", of: app)
        schedule.tap()

        XCTAssertTrue(app.navigationBars["强智教务"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当前版本暂未开放绑定"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
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
