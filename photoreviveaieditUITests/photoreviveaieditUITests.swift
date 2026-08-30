//
//  photoreviveaieditUITests.swift
//  photoreviveaieditUITests
//
//  Created by Mayingkun on 2026/8/15.
//

import XCTest

final class photoreviveaieditUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSettingsSupportRowsAndFeedbackForm() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let meTab = app.buttons["Me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 5))
        meTab.tap()

        let settings = app.buttons["Open settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        XCTAssertFalse(app.buttons["settings-row-language"].exists)
        XCTAssertFalse(app.buttons["settings-row-faq"].exists)
        XCTAssertFalse(app.buttons["settings-row-referral-code"].exists)
        XCTAssertTrue(app.buttons["settings-row-rate-us"].exists)
        XCTAssertTrue(app.buttons["settings-row-terms-of-service"].exists)

        let feedback = app.buttons["settings-row-feedback"]
        XCTAssertTrue(feedback.exists)
        feedback.tap()

        XCTAssertTrue(app.staticTexts["Feedback"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["feedback-content"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["feedback-email"].exists)
        XCTAssertTrue(app.buttons["feedback-submit"].exists)
    }

    @MainActor
    func testAccountPageAndDeletionWarning() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Me"].waitForExistence(timeout: 5))
        app.buttons["Me"].tap()
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 3))
        app.buttons["Open settings"].tap()

        let account = app.buttons["settings-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()

        XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Change profile photo"].exists)
        XCTAssertTrue(app.buttons["account-edit-name"].exists)
        attachScreenshot(named: "Account", app: app)

        let delete = app.buttons["account-delete"]
        XCTAssertTrue(delete.exists)
        delete.tap()
        XCTAssertTrue(app.staticTexts["This action is permanent and cannot be undone."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["account-delete-confirm"].exists)
        attachScreenshot(named: "Account Delete Warning", app: app)
    }

    @MainActor
    func testCreditStoreAndExitOfferFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd",
            "-loggedIn",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let meTab = app.buttons["Me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 5))
        meTab.tap()

        let settings = app.buttons["Open settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let creditDetail = app.buttons["settings-row-credit-detail"]
        XCTAssertTrue(creditDetail.waitForExistence(timeout: 3))
        creditDetail.tap()

        let moreCredits = app.buttons["more-credits-button"]
        XCTAssertTrue(moreCredits.waitForExistence(timeout: 3))
        moreCredits.tap()

        XCTAssertTrue(app.descendants(matching: .any)["credit-store-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["credit-pack-creator"].isSelected)
        XCTAssertTrue(app.buttons["credit-pack-starter"].exists)
        XCTAssertTrue(app.buttons["credit-pack-studio"].exists)
        XCTAssertTrue(app.buttons["credit-store-continue"].exists)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        attachScreenshot(named: "Credit Store", app: app)

        app.buttons["credit-store-close"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["credit-exit-offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["credit-exit-offer-claim"].exists)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        XCTAssertTrue(app.staticTexts["377"].exists)
        attachScreenshot(named: "Credit Exit Offer", app: app)

        app.buttons["Close bonus offer"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["credit-exit-offer"].waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testSubscriberRewardsOffersCreditPacks() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-forceSignedOut",
            "-forceSubscriberRewardsOffer",
            "-showRewardsPreview",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let creditPacks = app.buttons["rewards-credit-store-entry"]
        XCTAssertTrue(creditPacks.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Top Up Credits"].exists)
        XCTAssertTrue(app.staticTexts["One-time packs · Never expire"].exists)
        attachScreenshot(named: "Subscriber Rewards Credit Packs", app: app)

        creditPacks.tap()
        XCTAssertTrue(app.descendants(matching: .any)["credit-store-screen"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSubscriberScratchMarketingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd",
            "-forceSubscriberScratchOffer",
            "-simulateSubscriberScratchClaim",
            "-resetSubscriberScratchEligibility",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let freeCard = app.descendants(matching: .any)["subscriber-scratch-card-free"]
        XCTAssertTrue(freeCard.waitForExistence(timeout: 5))
        attachScreenshot(named: "Subscriber Scratch Free Gift", app: app)
        scratch(card: freeCard)

        let claimFree = app.buttons["subscriber-scratch-claim-free"]
        XCTAssertTrue(claimFree.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["They expire 2 hours after you claim them."].exists)
        attachScreenshot(named: "Subscriber Scratch Expiring Reward", app: app)
        claimFree.tap()

        let paidCard = app.descendants(matching: .any)["subscriber-scratch-card-1600"]
        XCTAssertTrue(paidCard.waitForExistence(timeout: 4))
        scratch(card: paidCard)

        let purchase = app.buttons["subscriber-scratch-purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        XCTAssertTrue(app.buttons["subscriber-scratch-close"].exists)
        attachScreenshot(named: "Subscriber Scratch 1600 Offer", app: app)
    }

    @MainActor
    func testLimitedOfferCanCloseWhileConnecting() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-showLimitedOfferPreview",
            "-simulateLimitedOfferConnecting",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let purchase = app.buttons["limited-offer-try-now"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Offer countdown"].exists)
        attachScreenshot(named: "Limited Time Offer Yearly Review", app: app)
        purchase.tap()
        let connecting = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"),
            object: purchase
        )
        XCTAssertEqual(XCTWaiter.wait(for: [connecting], timeout: 2), .completed)

        let close = app.buttons["limited-offer-close"]
        XCTAssertTrue(close.isHittable)
        close.tap()

        let popup = app.descendants(matching: .any)["limited-time-offer-popup"]
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: popup
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["Me"].exists)
    }

    @MainActor
    func testMainNavigationAndCreateFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-forceUnsubscribed",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let photoTab = app.buttons["AI Photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        photoTab.tap()
        XCTAssertTrue(app.buttons["Try AI Photo"].waitForExistence(timeout: 2))

        app.buttons["Open daily gift"].tap()
        XCTAssertTrue(app.staticTexts["Daily Free Credits"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Daily Credits", app: app)
        app.buttons["Close rewards"].tap()

        app.buttons["View credits"].tap()
        XCTAssertTrue(app.staticTexts["Daily Free Credits"].waitForExistence(timeout: 2))
        app.buttons["Close rewards"].tap()

        app.buttons["AI Video"].tap()
        XCTAssertTrue(app.staticTexts["AI Video"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Try One-Tap Restore"].exists)

        app.buttons["Me"].tap()
        let createButton = app.buttons["Create now"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 2))
        createButton.tap()

        XCTAssertTrue(app.staticTexts["Video Generator"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Video Generator", app: app)
    }

    @MainActor
    func testLandscapeAndPortraitTemplateDetails() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        app.buttons["AI Photo"].tap()
        let landscapeCover = app.buttons["Try AI Photo"]
        XCTAssertTrue(landscapeCover.waitForExistence(timeout: 3))
        landscapeCover.tap()

        XCTAssertTrue(app.buttons["Close detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Try Cinematic Memory"].exists)
        app.buttons["Close detail"].firstMatch.tap()

        app.buttons["Home"].tap()

        let memoryCover = app.buttons["template-memory"].firstMatch
        if !memoryCover.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memoryCover.waitForExistence(timeout: 2))
        memoryCover.tap()

        let tryMemory = app.buttons["Try Memory"]
        XCTAssertTrue(tryMemory.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Memory"].exists)
        tryMemory.tap()
        XCTAssertTrue(app.navigationBars["Revive Old Photos"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Revive Old Photos Editor", app: app)
        app.buttons["Edit generation settings"].tap()
        XCTAssertTrue(app.navigationBars["Output Settings"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Output Settings", app: app)
        app.buttons["Save output settings"].tap()
    }

    @MainActor
    func testVideoNoPromptUploadFitsOneScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let memory = app.buttons["template-memory"].firstMatch
        for _ in 0..<6 where !memory.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memory.waitForExistence(timeout: 3))
        memory.tap()

        let tryMemory = app.buttons["Try Memory"]
        XCTAssertTrue(tryMemory.waitForExistence(timeout: 3))
        tryMemory.tap()

        XCTAssertTrue(app.navigationBars["Revive Old Photos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["upload-sample-preview"].exists)
        let primaryAction = app.buttons["creation-primary-action"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(primaryAction.frame.maxY, app.windows.firstMatch.frame.maxY + 1)
        let originalActionY = primaryAction.frame.minY
        app.swipeUp()
        XCTAssertEqual(
            primaryAction.frame.minY,
            originalActionY,
            accuracy: 1,
            "No-prompt upload page should not scroll vertically"
        )
        attachScreenshot(named: "Video No Prompt Upload One Screen", app: app)
    }

    @MainActor
    func testVideoPromptUploadFitsOneScreenWithoutVerticalScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-disableReturningOffer",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let motorcycle = app.buttons["template-motorcycle-boy"].firstMatch
        for _ in 0..<6 where !motorcycle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(motorcycle.waitForExistence(timeout: 3))
        motorcycle.tap()

        let tryMotorcycle = app.buttons["Try Motorcycle Boy"]
        XCTAssertTrue(tryMotorcycle.waitForExistence(timeout: 3))
        let tryMotorcycleReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: tryMotorcycle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [tryMotorcycleReady], timeout: 3), .completed)
        tryMotorcycle.tap()

        XCTAssertTrue(app.navigationBars["Baby Adventure"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["guided-video-editor"].exists)
        XCTAssertTrue(app.staticTexts["Image1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["upload-sample-preview"].exists)

        let settings = app.buttons["Edit generation settings"]
        let primaryAction = app.buttons["creation-primary-action"]
        let chooserTitle = app.staticTexts["Choose Template"]
        let firstTemplate = app.buttons["Select Baby Fly"]
        let templateStrip = app.scrollViews["creation-template-strip"].firstMatch
        let trailingTemplate = app.buttons["Select Playful Cartoon"]
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 3))
        XCTAssertTrue(chooserTitle.exists)
        XCTAssertTrue(firstTemplate.exists)
        XCTAssertTrue(templateStrip.exists)
        XCTAssertTrue(trailingTemplate.exists)

        let windowMaxY = app.windows.firstMatch.frame.maxY + 1
        XCTAssertLessThanOrEqual(settings.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(primaryAction.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(chooserTitle.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(firstTemplate.frame.maxY, windowMaxY)

        let primaryActionY = primaryAction.frame.minY
        let trailingTemplateX = trailingTemplate.frame.minX
        templateStrip.swipeLeft()
        XCTAssertLessThan(trailingTemplate.frame.minX, trailingTemplateX)
        XCTAssertEqual(primaryAction.frame.minY, primaryActionY, accuracy: 1)

        app.swipeUp()
        XCTAssertEqual(primaryAction.frame.minY, primaryActionY, accuracy: 1)
        attachScreenshot(named: "Video Prompt Upload One Screen", app: app)
    }

    @MainActor
    func testColdLaunchOpensTheTappedFilter() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-disableReturningOffer",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let motorcycle = app.buttons["template-motorcycle-boy"]
        XCTAssertTrue(motorcycle.waitForExistence(timeout: 4))
        for _ in 0..<5 where !motorcycle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(motorcycle.isHittable)
        motorcycle.tap()

        XCTAssertTrue(app.buttons["Try Motorcycle Boy"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Try Baby Fly"].exists)
    }

    @MainActor
    func testImageGenerationGroupRouting() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer", "-loggedIn", "-useLocalFeatureCatalog"]
        app.launch()

        app.buttons["AI Photo"].tap()
        let cowboy = app.buttons["template-cowboy-style"].firstMatch
        for _ in 0..<8 where !cowboy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(cowboy.waitForExistence(timeout: 3))
        cowboy.tap()

        XCTAssertTrue(app.buttons["Try Cowboy Style"].waitForExistence(timeout: 2))
        app.buttons["Try Cowboy Style"].tap()

        XCTAssertTrue(app.staticTexts["Upload Image"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Image1"].exists)
        XCTAssertTrue(app.staticTexts["Image2"].exists)
        let generateButton = app.buttons["image-generate-button"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 3))
        let settings = app.buttons["Edit output settings"].firstMatch
        XCTAssertTrue(settings.exists)
        XCTAssertLessThanOrEqual(settings.frame.maxY, generateButton.frame.minY - 1)
        XCTAssertLessThanOrEqual(generateButton.frame.maxY, app.windows.firstMatch.frame.maxY + 1)
        let originalSettingsY = settings.frame.minY
        app.swipeUp()
        XCTAssertEqual(
            settings.frame.minY,
            originalSettingsY,
            accuracy: 1,
            "Image-generation upload page should not scroll vertically"
        )
        attachScreenshot(named: "Image Generation Upload", app: app)
    }

    @MainActor
    func testImageDataNoticeKeepsIconInsideCard() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog",
            "-showImageDataNoticePreview"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["AI Photo"].waitForExistence(timeout: 5))
        app.buttons["AI Photo"].tap()

        let cowboy = app.buttons["template-cowboy-style"].firstMatch
        for _ in 0..<8 where !cowboy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(cowboy.waitForExistence(timeout: 3))
        cowboy.tap()

        XCTAssertTrue(app.buttons["Try Cowboy Style"].waitForExistence(timeout: 3))
        app.buttons["Try Cowboy Style"].tap()

        let notice = app.descendants(matching: .any)["image-ai-data-notice"]
        let icon = app.descendants(matching: .any)["image-ai-data-notice-icon"]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(icon.exists)
        XCTAssertTrue(notice.frame.contains(icon.frame))
        XCTAssertTrue(app.buttons["image-ai-data-notice-agree"].isHittable)
        XCTAssertTrue(app.buttons["image-ai-data-notice-cancel"].isHittable)
        attachScreenshot(named: "AI Data Processing Notice", app: app)
    }

    @MainActor
    func testTemplateDetailVerticalPaging() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-disableReturningOffer",
            "-useLocalFeatureCatalog",
            "-forceTemplateSwipeHint"
        ]
        app.launch()

        app.buttons["AI Photo"].tap()
        let cowboy = app.buttons["template-cowboy-style"].firstMatch
        for _ in 0..<6 where !cowboy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(cowboy.waitForExistence(timeout: 3))
        cowboy.tap()

        let tryCowboy = app.buttons["Try Cowboy Style"]
        XCTAssertTrue(tryCowboy.waitForExistence(timeout: 2))
        XCTAssertTrue(tryCowboy.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["template-swipe-hint"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Template Detail Swipe Hint", app: app)

        app.swipeUp()
        let tryGentleman = app.buttons["Try Gentleman"]
        XCTAssertTrue(tryGentleman.waitForExistence(timeout: 3))
        XCTAssertTrue(tryGentleman.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["template-swipe-hint"].exists)

        app.swipeDown()
        XCTAssertTrue(tryCowboy.waitForExistence(timeout: 3))
        XCTAssertTrue(tryCowboy.isHittable)

        app.swipeUp()
        XCTAssertTrue(tryGentleman.waitForExistence(timeout: 3))
        XCTAssertTrue(tryGentleman.isHittable)
        tryGentleman.tap()
        XCTAssertTrue(app.staticTexts["Upload Image"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gentleman"].exists)
    }

    @MainActor
    func testVideoTemplatePagingContinuesIntoNextSection() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-disableReturningOffer",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        app.buttons["AI Video"].tap()
        let playfulCartoon = app.buttons["template-cartoon-portrait"].firstMatch
        for _ in 0..<6 where !playfulCartoon.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(playfulCartoon.waitForExistence(timeout: 3))
        playfulCartoon.tap()

        let tryPlayfulCartoon = app.buttons["Try Playful Cartoon"]
        XCTAssertTrue(tryPlayfulCartoon.waitForExistence(timeout: 3))

        app.swipeUp()
        let tryMemory = app.buttons["Try Memory"]
        XCTAssertTrue(tryMemory.waitForExistence(timeout: 3))
        XCTAssertTrue(tryMemory.isHittable)

        app.swipeDown()
        XCTAssertTrue(tryPlayfulCartoon.waitForExistence(timeout: 3))

        app.swipeUp()
        XCTAssertTrue(tryMemory.waitForExistence(timeout: 3))
        tryMemory.tap()

        XCTAssertTrue(app.navigationBars["Revive Old Photos"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["guided-video-editor"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["upload-sample-preview"].exists)
    }

    @MainActor
    func testPaywallAndInviteRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-resetLimitedOfferEligibility",
            "-forceLimitedOffer",
            "-loggedIn"
        ]
        app.launch()

        app.buttons["AI Photo"].tap()
        app.buttons["Open Pro membership"].tap()
        XCTAssertTrue(app.buttons["Close membership"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["membership-continue"].exists)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        attachScreenshot(named: "Membership", app: app)

        let proPlus = app.buttons["membership-tier-proPlus"]
        XCTAssertTrue(proPlus.waitForExistence(timeout: 2))
        proPlus.tap()
        XCTAssertTrue(app.staticTexts["900/week"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Membership PRO Plus", app: app)

        app.buttons["Close membership"].tap()

        XCTAssertTrue(app.buttons["Close limited offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["limited-offer-try-now"].exists)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        attachScreenshot(named: "Limited Time Offer", app: app)
        app.buttons["Close limited offer"].tap()

        app.buttons["Open daily gift"].tap()
        XCTAssertTrue(app.staticTexts["Daily Free Credits"].waitForExistence(timeout: 2))
        app.buttons["invite-friends-link"].tap()
        XCTAssertTrue(app.navigationBars["Invite Friends"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Copy invitation code"].exists)
        attachScreenshot(named: "Invite Friends", app: app)
    }

    @MainActor
    func testLoggedInPaywallUsesLoggedProducts() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer", "-loggedIn", "-hideDebugTestControls"]
        app.launch()

        app.buttons["AI Photo"].tap()
        app.buttons["Open Pro membership"].tap()

        let continueButton = app.buttons["membership-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertEqual(continueButton.value as? String, "loged_pro_yearly")
        attachScreenshot(named: "Logged In Membership PRO", app: app)

        app.buttons["membership-billing-weekly"].tap()
        XCTAssertEqual(continueButton.value as? String, "loged_pro_weekly")
        attachScreenshot(named: "Logged In Membership PRO Weekly Review", app: app)

        let proPlus = app.buttons["membership-tier-proPlus"]
        XCTAssertTrue(proPlus.waitForExistence(timeout: 2))
        proPlus.tap()
        XCTAssertEqual(continueButton.value as? String, "loged_proplus_weekly")
        attachScreenshot(named: "Logged In Membership PRO Plus", app: app)

        app.buttons["membership-billing-annual"].tap()
        XCTAssertEqual(continueButton.value as? String, "loged_proplus_yearly")
    }

    @MainActor
    func testSummerHeroOfferRoute() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-hideDebugTestControls",
            "-showSummerOfferPreview",
        ]
        app.launch()

        let close = app.buttons["Close summer offer"]
        let restore = app.buttons["Restore"]
        let weekly = app.buttons["Weekly Plan"]
        let annual = app.buttons["Annual Plan"]
        let continueButton = app.buttons["Continue"]

        XCTAssertTrue(close.waitForExistence(timeout: 3))
        let closeReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: close
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closeReady], timeout: 3), .completed)
        XCTAssertTrue(restore.waitForExistence(timeout: 2))
        XCTAssertTrue(restore.isHittable)
        XCTAssertTrue(weekly.isHittable)
        XCTAssertTrue(annual.isHittable)
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        XCTAssertEqual(annual.value as? String, "Selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_yearly")

        weekly.tap()
        XCTAssertEqual(weekly.value as? String, "Selected")
        XCTAssertEqual(annual.value as? String, "Not selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_weekly")

        annual.tap()
        XCTAssertEqual(annual.value as? String, "Selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_yearly")
        attachScreenshot(named: "Special Gift Yearly Review", app: app)

        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSuggestionRoute() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-loggedIn", "-useLocalFeatureCatalog"]
        app.launch()

        for (tab, screenshotName) in [
            ("Home", "Suggestion from Home"),
            ("AI Photo", "Suggestion from AI Photo"),
            ("AI Video", "Suggestion from AI Video"),
        ] {
            app.buttons[tab].tap()

            let suggestion = app.buttons["suggest-template"]
            for _ in 0..<12 where !suggestion.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(suggestion.waitForExistence(timeout: 2), "Missing suggestion entry on \(tab)")
            XCTAssertTrue(suggestion.isHittable, "Suggestion entry is not reachable on \(tab)")
            suggestion.tap()
            XCTAssertTrue(app.navigationBars["Suggestion"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["FAQ"].exists)
            attachScreenshot(named: screenshotName, app: app)

            app.buttons["Close suggestion"].tap()
            XCTAssertFalse(app.navigationBars["Suggestion"].waitForExistence(timeout: 1))
        }
    }

    @MainActor
    func testPageSnapshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-loggedIn"]
        app.launch()

        attachScreenshot(named: "Home", app: app)

        for tab in ["AI Photo", "AI Video", "Me"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 2))
            button.tap()
            Thread.sleep(forTimeInterval: 0.35)
            attachScreenshot(named: tab, app: app)
        }
    }

    @MainActor
    func testPrimaryPagesStayWithinHorizontalScreenBounds() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let windowFrame = app.windows.firstMatch.frame
        for tab in ["Home", "AI Photo", "AI Video", "Me"] {
            let tabButton = app.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
            tabButton.tap()
            XCTAssertHorizontallyContained(tabButton, in: windowFrame, named: "\(tab) tab")
        }

        app.buttons["AI Photo"].tap()
        let photoHero = app.buttons["Try AI Photo"]
        XCTAssertTrue(photoHero.waitForExistence(timeout: 3))
        XCTAssertHorizontallyContained(photoHero, in: windowFrame, named: "AI Photo hero")

        app.buttons["AI Video"].tap()
        let expectedVideoModes = [
            ("photoToVideo", "Photo To Video"),
            ("textToVideo", "Text To Video")
        ]
        for (featureID, title) in expectedVideoModes {
            let mode = app.buttons["video-mode-\(featureID)"]
            XCTAssertTrue(mode.waitForExistence(timeout: 3), "Missing video mode \(featureID)")
            XCTAssertEqual(mode.label, title)
            XCTAssertHorizontallyContained(mode, in: windowFrame, named: "Video mode \(featureID)")

            mode.tap()
            let videoHero = app.buttons["video-mode-hero-\(featureID)"]
            XCTAssertTrue(videoHero.waitForExistence(timeout: 3), "Missing video hero \(featureID)")
            XCTAssertHorizontallyContained(
                videoHero,
                in: windowFrame,
                named: "AI Video hero \(featureID)"
            )

            let tryNow = app.buttons["video-mode-try-now-\(featureID)"]
            XCTAssertTrue(tryNow.waitForExistence(timeout: 3), "Missing Try Now button \(featureID)")
            XCTAssertGreaterThanOrEqual(
                videoHero.frame.maxX - tryNow.frame.maxX,
                19,
                "Try Now button \(featureID) is too close to the hero's right edge"
            )
        }
        for featureID in ["oneTapRestore", "enhancePhoto", "aiImage"] {
            XCTAssertFalse(app.buttons["video-mode-\(featureID)"].exists)
        }
        attachScreenshot(named: "AI Video Responsive Layout", app: app)

        app.buttons["Me"].tap()
        for label in ["Video", "Photo", "Open settings", "Create now"] {
            let control = app.buttons[label]
            XCTAssertTrue(control.waitForExistence(timeout: 3), "Missing Me control \(label)")
            XCTAssertHorizontallyContained(control, in: windowFrame, named: "Me control \(label)")
        }
    }

    @MainActor
    func testHomeFixedFeatureRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let routes = [
            ("oneTapRestore", "AI One-Tap Restore"),
            ("photoToVideo", "Video Generator"),
            ("aiImage", "AI Image"),
            ("enhancePhoto", "AI Enhance"),
            ("textToVideo", "Video Generator")
        ]
        let strip = app.scrollViews["home-fixed-features"]

        XCTAssertTrue(strip.waitForExistence(timeout: 3))

        for (index, route) in routes.enumerated() {
            if index >= 3 {
                strip.swipeLeft()
            }

            let button = app.buttons["fixed-feature-\(route.0)"]
            XCTAssertTrue(button.waitForExistence(timeout: 2))
            button.tap()
            XCTAssertTrue(app.staticTexts[route.1].waitForExistence(timeout: 3))
            assertFixedFeatureUploadFitsOneScreen(app: app, routeID: route.0)
            attachScreenshot(named: "Fixed Feature \(route.0)", app: app)
            app.buttons["fixed-feature-back-button"].tap()
            XCTAssertTrue(
                app.buttons["fixed-feature-primary-action"].waitForNonExistence(timeout: 3)
            )
            XCTAssertTrue(strip.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testAIImageBackReturnsHomeWhileKeyboardIsVisible() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        let featureStrip = app.scrollViews["home-fixed-features"]
        XCTAssertTrue(featureStrip.waitForExistence(timeout: 3))

        let aiImage = app.buttons["fixed-feature-aiImage"]
        XCTAssertTrue(aiImage.waitForExistence(timeout: 3))
        aiImage.tap()

        XCTAssertTrue(app.staticTexts["AI Image"].waitForExistence(timeout: 3))
        let insertReference = app.buttons["Insert at sign"]
        XCTAssertTrue(insertReference.waitForExistence(timeout: 3))
        insertReference.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        app.buttons["fixed-feature-back-button"].tap()

        XCTAssertTrue(
            app.buttons["fixed-feature-primary-action"].waitForNonExistence(timeout: 3)
        )
        XCTAssertTrue(featureStrip.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["photo-selection-sheet"].exists)
    }

    @MainActor
    func testAIPhotoFixedFeatureRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd"
        ]
        app.launch()

        let photoTab = app.buttons["AI Photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        photoTab.tap()

        let routes = [
            ("oneTapRestore", "AI One-Tap Restore"),
            ("enhancePhoto", "AI Enhance"),
            ("imageToImage", "AI Image")
        ]

        for (index, route) in routes.enumerated() {
            let button = app.buttons["photo-fixed-feature-\(route.0)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing AI Photo route \(route.0)")
            button.tap()
            XCTAssertTrue(app.staticTexts[route.1].waitForExistence(timeout: 3))

            if index == 2 {
                app.buttons["Edit output settings"].tap()
                XCTAssertTrue(app.staticTexts["Resolution"].waitForExistence(timeout: 2))
                XCTAssertTrue(app.staticTexts["Ratio"].exists)
                XCTAssertTrue(app.buttons["21:9"].exists)
                XCTAssertTrue(app.staticTexts["Output Image Number"].exists)
                attachScreenshot(named: "AI Photo image settings", app: app)
                app.buttons["Close output settings"].tap()
            }

            attachScreenshot(named: "AI Photo \(route.0)", app: app)

            app.buttons["Back"].tap()
            XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testAIPhotoLoadsRemoteNewOutfitCatalog() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer"]
        app.launch()

        let photoTab = app.buttons["AI Photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        photoTab.tap()

        let newOutfit = app.staticTexts["New Outfit"]
        for _ in 0..<8 where !newOutfit.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
        }

        XCTAssertTrue(newOutfit.waitForExistence(timeout: 5), "The CMS New Outfit section did not load")
        let fashionDresses = app.buttons["template-photorevival-new-outfit-fashion-dresses"]
        XCTAssertTrue(fashionDresses.waitForExistence(timeout: 3))
        attachScreenshot(named: "AI Photo CMS New Outfit", app: app)
    }

    @MainActor
    func testWelcomeContinueRespondsToDirectTap() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-forceOnboarding",
            "-skipStartupAnimation",
            "-disableReturningOffer"
        ]
        app.launch()

        let continueButton = app.buttons["onboarding-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 4))
        XCTAssertTrue(continueButton.isHittable, "The welcome Continue button must accept direct taps")

        continueButton.tap()

        XCTAssertTrue(app.staticTexts["Bring Memories to Life"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFirstLaunchOnboardingAndGuestRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-forceOnboarding",
            "-skipStartupAnimation",
            "-disableReturningOffer",
            "-resetLimitedOfferEligibility",
            "-forceLimitedOffer",
            "-isLoggedIn",
            "NO"
        ]
        app.launch()

        let continueButton = app.buttons["onboarding-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 4))
        XCTAssertTrue(continueButton.isHittable, "The welcome Continue button must accept direct taps")
        Thread.sleep(forTimeInterval: 0.45)
        attachScreenshot(named: "Onboarding Welcome", app: app)

        continueButton.tap()
        XCTAssertTrue(app.staticTexts["Bring Memories to Life"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Onboarding Restore", app: app)

        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["See Your Pet Again"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Onboarding Pet", app: app)

        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Bring Your\nFamily Together"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Onboarding Fusion", app: app)

        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["Close membership"].waitForExistence(timeout: 3))
        attachScreenshot(named: "Initial Membership", app: app)
        app.buttons["Close membership"].tap()

        XCTAssertTrue(app.buttons["Close limited offer"].waitForExistence(timeout: 3))
        app.buttons["Close limited offer"].tap()

        let freeUse = app.buttons["Free Use"]
        XCTAssertTrue(freeUse.waitForExistence(timeout: 3))
        attachScreenshot(named: "Guest Home", app: app)

        freeUse.tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["sign-in-legal-agreement"].exists)
        attachScreenshot(named: "Sign In", app: app)
        app.buttons["Close sign in"].tap()
    }

    @MainActor
    func testGuestProtectedHomeEntryPointsRequireLogin() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-forceSignedOut",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        assertRequiresLogin(app.buttons["Free Use"], app: app)
        assertRequiresLogin(app.buttons["Open daily gift"], app: app)
        assertRequiresLogin(app.buttons["Me"], app: app)
    }

    @MainActor
    func testGuestUploadActionsRequireLogin() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-forceSignedOut",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog"
        ]
        app.launch()

        app.buttons["AI Photo"].tap()
        let cowboy = app.buttons["template-cowboy-style"].firstMatch
        for _ in 0..<8 where !cowboy.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(cowboy.waitForExistence(timeout: 3))
        cowboy.tap()
        app.buttons["Try Cowboy Style"].tap()
        XCTAssertTrue(app.buttons["image-generate-button"].waitForExistence(timeout: 3))
        assertRequiresLogin(app.buttons["image-generate-button"], app: app)

        app.terminate()
        app.launch()

        let memory = app.buttons["template-memory"].firstMatch
        for _ in 0..<6 where !memory.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memory.waitForExistence(timeout: 3))
        memory.tap()
        app.buttons["Try Memory"].tap()
        XCTAssertTrue(app.buttons["creation-primary-action"].waitForExistence(timeout: 3))
        assertRequiresLogin(app.buttons["creation-primary-action"], app: app)
    }

    @MainActor
    func testReturningUserOfferFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-forceReturningOffer",
            "-hideDebugTestControls",
            "-forceFamilyExclusiveReturningOffer"
        ]
        app.launch()

        let familyClose = app.buttons["returning-offer-close"]
        XCTAssertTrue(familyClose.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["returning-offer-privacy"].exists)
        XCTAssertTrue(app.buttons["returning-offer-terms"].exists)
        XCTAssertTrue(app.staticTexts["$8.99/week"].waitForExistence(timeout: 15))
        attachScreenshot(named: "Family Exclusive Weekly Review", app: app)
        familyClose.tap()

        let trialStart = app.buttons["returning-trial-start"]
        XCTAssertTrue(trialStart.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["returning-offer-privacy"].exists)
        XCTAssertTrue(app.buttons["returning-offer-terms"].exists)
        attachScreenshot(named: "Returning Offer Free Trial", app: app)
        app.buttons["returning-trial-close"].tap()
    }

    @MainActor
    func testDirectThreeDayTrialNeverFlashesFamilyOffer() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd"
        ]
        app.launch()

        let debugBubble = app.buttons["debug-test-bubble"]
        XCTAssertTrue(debugBubble.waitForExistence(timeout: 4))
        debugBubble.tap()

        let directTrialPreview = app.buttons["Paywall Close · 3-Day Free Trial"]
        if !directTrialPreview.waitForExistence(timeout: 2) || !directTrialPreview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(directTrialPreview.waitForExistence(timeout: 2))
        directTrialPreview.tap()

        let familyClose = app.buttons["returning-offer-close"]
        XCTAssertFalse(
            familyClose.exists,
            "The family offer must never appear while direct trial eligibility is loading"
        )
        let eligibilityLoading = app.descendants(matching: .any)["returning-trial-eligibility-loading"]
        let trialStart = app.buttons["returning-trial-start"]
        XCTAssertTrue(
            eligibilityLoading.exists || trialStart.exists,
            "The direct trial route should show only eligibility loading or the trial offer"
        )

        let familyFlash = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: familyClose
        )
        familyFlash.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [familyFlash], timeout: 3), .completed)

        if trialStart.exists {
            app.buttons["returning-trial-close"].tap()
        }
    }

    @MainActor
    func testReturningRetentionOfferDisclosures() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-disableReturningOffer"
        ]
        app.launch()

        let debugBubble = app.buttons["debug-test-bubble"]
        XCTAssertTrue(debugBubble.waitForExistence(timeout: 4))
        debugBubble.tap()

        let retentionPreview = app.buttons["Family Exclusive · Second Follow-Up"]
        if !retentionPreview.waitForExistence(timeout: 2) || !retentionPreview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(retentionPreview.waitForExistence(timeout: 2))
        retentionPreview.tap()

        XCTAssertTrue(app.buttons["returning-retention-continue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["returning-retention-subscription-details"].exists)
        XCTAssertTrue(app.buttons["returning-retention-restore"].isHittable)
        XCTAssertTrue(app.buttons["returning-retention-privacy"].isHittable)
        XCTAssertTrue(app.buttons["returning-retention-terms"].isHittable)
        attachScreenshot(named: "Returning Retention Subscription Disclosures", app: app)
    }

    @MainActor
    func testReturningSuperPrizeOffer() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-forceReturningOffer",
            "-hideDebugTestControls",
            "-showSuperPrizePreview",
            "-forceSuperPrizeReturningOffer"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["super-prize-continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Close super prize"].exists)
        XCTAssertTrue(app.buttons["legal-privacy-policy"].exists)
        XCTAssertTrue(app.buttons["legal-terms-of-service"].exists)
        XCTAssertTrue(app.staticTexts["Then $9.99/week"].waitForExistence(timeout: 15))
        attachScreenshot(named: "Super Prize Weekly Review", app: app)
    }

    @MainActor
    func testGeneratedVideoResultRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-loggedIn",
            "-forceUnsubscribed",
            "-resetLimitedOfferEligibility",
            "-forceLimitedOffer",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog",
            "-showGeneratedVideoPreview"
        ]
        app.launch()

        let memoryCover = app.buttons["template-memory"].firstMatch
        if !memoryCover.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memoryCover.waitForExistence(timeout: 2))
        memoryCover.tap()
        app.buttons["Try Memory"].tap()

        XCTAssertTrue(app.staticTexts["Please wait (1-3 min)"].waitForExistence(timeout: 3))
        let removeWatermark = app.buttons["Remove watermark"]
        XCTAssertTrue(removeWatermark.waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["generated-video-player"].exists)
        let playVideo = app.buttons["Play generated video"]
        XCTAssertTrue(playVideo.exists)

        let windowFrame = app.windows.firstMatch.frame
        for label in ["Delete generation", "WhatsApp", "TikTok"] {
            let element = app.buttons[label]
            XCTAssertTrue(element.exists, "Missing \(label)")
            XCTAssertGreaterThanOrEqual(element.frame.minX, windowFrame.minX - 1)
            XCTAssertLessThanOrEqual(element.frame.maxX, windowFrame.maxX + 1)
        }
        app.buttons["Delete generation"].tap()
        XCTAssertTrue(app.staticTexts["Permanently delete this creation?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This creation will be permanently deleted and cannot be recovered."].exists)
        XCTAssertTrue(app.buttons["Delete Permanently"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete generation"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Generated Video Result", app: app)

        playVideo.tap()
        XCTAssertTrue(playVideo.waitForNonExistence(timeout: 2))

        removeWatermark.tap()
        XCTAssertTrue(app.buttons["Close membership"].waitForExistence(timeout: 2))
        app.buttons["Close membership"].tap()
        XCTAssertTrue(app.buttons["Close limited offer"].waitForExistence(timeout: 3))
        app.buttons["Close limited offer"].tap()

        let maximize = app.buttons["Maximize generated video"]
        let maximizeReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: maximize
        )
        XCTAssertEqual(XCTWaiter.wait(for: [maximizeReady], timeout: 3), .completed)
        maximize.tap()
        XCTAssertTrue(app.descendants(matching: .any)["generated-video-player-fullscreen"].waitForExistence(timeout: 2))
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 2))
        regenerate.tap()
        XCTAssertTrue(app.navigationBars["Revive Old Photos"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHistoryResultUsesCompactPlayableLayout() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipStartupAnimation",
            "-skipOnboarding",
            "-disableReturningOffer",
            "-disableAppOpenAd",
            "-loggedIn",
            "-forceUnsubscribed",
            "-hideDebugTestControls",
            "-useLocalFeatureCatalog",
            "-showHistoryResultPreview"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Me"].waitForExistence(timeout: 5))
        app.buttons["Me"].tap()

        let card = app.descendants(matching: .any)["history-result-card-history-result-preview"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Revive Old Photos"].exists)
        XCTAssertTrue(app.staticTexts["Memory"].exists)
        XCTAssertTrue(app.staticTexts["Today"].exists)

        let windowFrame = app.windows.firstMatch.frame
        for label in ["Save generated video", "Share generated video"] {
            let element = app.buttons[label]
            XCTAssertTrue(element.exists, "Missing \(label)")
            XCTAssertGreaterThanOrEqual(element.frame.minX, windowFrame.minX - 1)
            XCTAssertLessThanOrEqual(element.frame.maxX, windowFrame.maxX + 1)
        }
        for label in ["Remove watermark", "Messages", "WhatsApp", "Facebook", "Instagram", "Messenger", "TikTok"] {
            XCTAssertFalse(app.buttons[label].exists, "Unexpected \(label)")
        }

        app.buttons["Delete generation"].tap()
        XCTAssertTrue(app.staticTexts["Permanently delete this creation?"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["This creation will be permanently deleted and cannot be recovered."].exists)
        XCTAssertTrue(app.buttons["Delete Permanently"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        attachScreenshot(named: "Compact History Result", app: app)

        let play = app.buttons["Play generated video"]
        XCTAssertTrue(play.exists)
        play.tap()
        XCTAssertTrue(play.waitForNonExistence(timeout: 2))

        let maximize = app.buttons["Maximize creation"]
        XCTAssertTrue(maximize.isHittable)
        maximize.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history-video-player"].waitForExistence(timeout: 2))
        let closePreview = app.buttons["Close preview"]
        XCTAssertTrue(closePreview.exists)

        let fullScreenFrame = app.windows.firstMatch.frame
        let portraitVideoHeight = min(fullScreenFrame.height, fullScreenFrame.width * 16 / 9)
        let portraitVideoMinY = fullScreenFrame.midY - portraitVideoHeight / 2
        XCTAssertGreaterThanOrEqual(
            closePreview.frame.minY,
            portraitVideoMinY,
            "Close preview button overlaps the top letterbox"
        )
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func XCTAssertHorizontallyContained(
        _ element: XCUIElement,
        in container: CGRect,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            element.frame.minX,
            container.minX - 1,
            "\(name) extends beyond the left screen edge",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            element.frame.maxX,
            container.maxX + 1,
            "\(name) extends beyond the right screen edge",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertFixedFeatureUploadFitsOneScreen(
        app: XCUIApplication,
        routeID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let primaryAction = app.buttons["fixed-feature-primary-action"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 3), file: file, line: line)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(primaryAction.frame.maxY, windowFrame.maxY + 1, file: file, line: line)

        let tipElements = app.descendants(matching: .any).matching(identifier: "fixed-photo-tip-row")
        let hasTips = tipElements.count > 0
        if hasTips {
            let tipMaxY = (0..<tipElements.count)
                .map { tipElements.element(boundBy: $0).frame.maxY }
                .max() ?? 0
            XCTAssertLessThanOrEqual(
                tipMaxY,
                primaryAction.frame.minY - 1,
                "\(routeID) tip icons overlap the primary action",
                file: file,
                line: line
            )
        }

        let settings = app.buttons["Edit output settings"].firstMatch
        if settings.exists {
            XCTAssertLessThanOrEqual(
                settings.frame.maxY,
                primaryAction.frame.minY - 1,
                "\(routeID) settings overlap the primary action",
                file: file,
                line: line
            )
        }

    }

    @MainActor
    private func assertRequiresLogin(_ entryPoint: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(entryPoint.waitForExistence(timeout: 3))
        entryPoint.tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 2))
        app.buttons["Close sign in"].tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("-skipOnboarding")
            app.launch()
        }
    }

    private func scratch(card: XCUIElement) {
        let yOffsets: [CGFloat] = [0.20, 0.36, 0.52, 0.68, 0.82]
        for (index, y) in yOffsets.enumerated() {
            guard card.exists else { break }
            let left = card.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: y))
            let right = card.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: y))
            if index.isMultiple(of: 2) {
                left.press(forDuration: 0.04, thenDragTo: right)
            } else {
                right.press(forDuration: 0.04, thenDragTo: left)
            }
        }
    }
}
