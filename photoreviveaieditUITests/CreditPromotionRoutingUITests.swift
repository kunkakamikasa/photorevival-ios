import XCTest

final class CreditPromotionRoutingUITests: XCTestCase {
    @MainActor
    func testSubscribedCreditPromotionsOpenCreditStore() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableSubscriberScratchOffer",
            "-loggedIn",
            "-hideDebugTestControls",
            "-debugTestUserStateOverrideEnabled", "YES",
            "-isSubscribed", "YES"
        ]
        app.launch()

        let bottomBanner = app.buttons["home-discount-banner"]
        XCTAssertTrue(bottomBanner.waitForExistence(timeout: 10))
        bottomBanner.tap()
        assertCreditStoreOpens(in: app)
        closeCreditStore(in: app)

        let heroPromotion = app.buttons["Open credit store"].firstMatch
        XCTAssertTrue(heroPromotion.waitForExistence(timeout: 5))
        heroPromotion.tap()
        assertCreditStoreOpens(in: app)
    }

    @MainActor
    private func assertCreditStoreOpens(in app: XCUIApplication) {
        let creditStore = app.descendants(matching: .any)["credit-store-screen"]
        XCTAssertTrue(
            creditStore.waitForExistence(timeout: 3),
            "The credit promotion must open the paid credit store, not the free rewards center."
        )
        XCTAssertFalse(app.staticTexts["Earn Free Credits"].exists)
    }

    @MainActor
    private func closeCreditStore(in app: XCUIApplication) {
        app.buttons["credit-store-close"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["credit-store-screen"]
                .waitForNonExistence(timeout: 3)
        )
    }
}
