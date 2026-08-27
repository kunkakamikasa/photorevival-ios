import XCTest

final class DebugTestControlsUITests: XCTestCase {
    @MainActor
    func testCanSimulateSignedInUser() throws {
        let app = launchApp()

        let bubble = app.buttons["debug-test-bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.tap()

        let statePicker = app.buttons["debug-user-state-picker"]
        XCTAssertTrue(statePicker.waitForExistence(timeout: 3))
        statePicker.tap()

        var signedInState = app.buttons["已登录用户（未订阅）"]
        XCTAssertTrue(signedInState.waitForExistence(timeout: 3))
        if signedInState.isSelected {
            app.buttons["未登录用户"].tap()
            XCTAssertTrue(statePicker.waitForExistence(timeout: 3))
            statePicker.tap()
            signedInState = app.buttons["已登录用户（未订阅）"]
            XCTAssertTrue(signedInState.waitForExistence(timeout: 3))
        }
        signedInState.tap()

        let loginState = app.descendants(matching: .any)["debug-current-login-state"]
        XCTAssertTrue(loginState.waitForExistence(timeout: 3))
        XCTAssertEqual(loginState.value as? String, "signed-in")

        let subscriptionState = app.descendants(matching: .any)["debug-current-subscription-state"]
        XCTAssertTrue(subscriptionState.exists)
        XCTAssertEqual(subscriptionState.value as? String, "unsubscribed")
    }

    @MainActor
    func testDebugBubblePresentsSubscriberPromotion() throws {
        let app = launchApp()

        let bubble = app.buttons["debug-test-bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.tap()

        let subscriberPromotion = app.buttons["积分刮刮卡促销"]
        XCTAssertTrue(subscriberPromotion.waitForExistence(timeout: 3))
        subscriberPromotion.tap()

        XCTAssertTrue(app.scrollViews["subscriber-scratch-flow"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-skipTrackingAuthorization",
            "-useLocalFeatureCatalog"
        ]
        app.launch()
        return app
    }
}
