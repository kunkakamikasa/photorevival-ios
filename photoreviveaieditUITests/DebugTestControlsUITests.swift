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

        var signedInState = app.buttons["Signed-In User (Not Subscribed)"]
        XCTAssertTrue(signedInState.waitForExistence(timeout: 3))
        if signedInState.isSelected {
            app.buttons["Signed-Out User"].tap()
            XCTAssertTrue(statePicker.waitForExistence(timeout: 3))
            statePicker.tap()
            signedInState = app.buttons["Signed-In User (Not Subscribed)"]
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

        let subscriberPromotion = revealButton("Returning Subscriber · Credit Scratch Card", in: app)
        XCTAssertTrue(subscriberPromotion.waitForExistence(timeout: 3))
        XCTAssertTrue(subscriberPromotion.isHittable)
        subscriberPromotion.tap()

        XCTAssertTrue(app.scrollViews["subscriber-scratch-flow"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDebugBubblePresentsCreditExitOffer() throws {
        let app = launchApp()

        let bubble = app.buttons["debug-test-bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.tap()

        let creditExitOffer = revealButton("Credit Purchase Exit Offer", in: app)
        XCTAssertTrue(creditExitOffer.waitForExistence(timeout: 3))
        XCTAssertTrue(creditExitOffer.isHittable)
        creditExitOffer.tap()

        let offer = app.descendants(matching: .any)["credit-exit-offer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5))
    }

    @MainActor
    private func revealButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<5 {
            if button.exists, button.isHittable { return button }
            app.swipeUp()
        }
        return button
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
