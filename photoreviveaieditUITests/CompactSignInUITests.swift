import XCTest

final class CompactSignInUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTenQuickTitleTapsRevealCredentialSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd",
            "-forceSignedOut",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog",
        ]
        app.launch()

        let meTab = app.buttons["Me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 5))
        meTab.tap()

        let title = app.descendants(matching: .any)["sign-in-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        for _ in 0..<9 {
            title.tap()
        }
        XCTAssertFalse(app.textFields["compact-login-email"].exists)

        title.tap()

        let email = app.textFields["compact-login-email"]
        let password = app.secureTextFields["compact-login-password"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        XCTAssertTrue(password.exists)
        XCTAssertFalse(app.buttons["compact-login-submit"].isEnabled)
    }
}
