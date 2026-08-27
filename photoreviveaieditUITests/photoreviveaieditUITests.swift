//
//  photoreviveaieditUITests.swift
//  photoreviveaieditUITests
//
//  Created by 马颖昆 on 2026/8/15.
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
    func testMainNavigationAndCreateFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-loggedIn"]
        app.launch()

        let photoTab = app.buttons["AI Photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        photoTab.tap()
        XCTAssertTrue(app.buttons["Try AI Photo"].waitForExistence(timeout: 2))

        app.buttons["Open daily gift"].tap()
        XCTAssertTrue(app.staticTexts["Daily Free Credits"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Daily Credits", app: app)
        app.buttons["daily-check-in"].tap()
        XCTAssertTrue(app.buttons["Dismiss check-in success"].waitForExistence(timeout: 2))
        app.buttons["Dismiss check-in success"].tap()
        app.buttons["Close rewards"].tap()

        app.buttons["View credits"].tap()
        XCTAssertTrue(app.staticTexts["Daily Free Credits"].waitForExistence(timeout: 2))
        app.buttons["Close rewards"].tap()

        app.buttons["AI Video"].tap()
        XCTAssertTrue(app.buttons["Try AI Video"].waitForExistence(timeout: 2))

        app.buttons["Me"].tap()
        let createButton = app.buttons["Create now"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 2))
        createButton.tap()

        XCTAssertTrue(app.navigationBars["Create with AI"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Create with AI", app: app)
    }

    @MainActor
    func testLandscapeAndPortraitTemplateDetails() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skipOnboarding")
        app.launch()

        let landscapeCover = app.buttons["Photo To Video"]
        XCTAssertTrue(landscapeCover.waitForExistence(timeout: 3))
        landscapeCover.tap()

        XCTAssertTrue(app.buttons["Close detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Try School Days"].exists)
        app.buttons["Close detail"].tap()

        let memoryCover = app.buttons["template-memory"]
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
        tryMotorcycle.tap()

        XCTAssertTrue(app.navigationBars["Baby Adventure"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["guided-video-editor"].exists)
        XCTAssertTrue(app.staticTexts["Image1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["upload-sample-preview"].exists)

        let settings = app.buttons["Edit generation settings"]
        let primaryAction = app.buttons["creation-primary-action"]
        let chooserTitle = app.staticTexts["Choose Template"]
        let firstTemplate = app.buttons["Select Baby Fly"]
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(primaryAction.exists)
        XCTAssertTrue(chooserTitle.exists)
        XCTAssertTrue(firstTemplate.exists)

        let windowMaxY = app.windows.firstMatch.frame.maxY + 1
        XCTAssertLessThanOrEqual(settings.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(primaryAction.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(chooserTitle.frame.maxY, windowMaxY)
        XCTAssertLessThanOrEqual(firstTemplate.frame.maxY, windowMaxY)

        let primaryActionY = primaryAction.frame.minY
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
        XCTAssertTrue(app.buttons["image-generate-button"].exists)
        attachScreenshot(named: "Image Generation Upload", app: app)

        app.buttons["image-generate-button"].tap()
        if app.staticTexts["AI Data Processing\nNotice"].waitForExistence(timeout: 1) {
            app.buttons["Agree and Continue"].tap()
        }

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Photo"].exists)

        let generatedCard = app.buttons["Generated image"]
        XCTAssertTrue(generatedCard.waitForExistence(timeout: 4))
        generatedCard.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 2))
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 2))
        app.buttons["image-to-video-button"].tap()
        XCTAssertTrue(app.staticTexts["Video Generator"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Describe motion you want to add to your photo"].exists)
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
        let tryMangaRider = app.buttons["Try Manga Rider"]
        XCTAssertTrue(tryMangaRider.waitForExistence(timeout: 3))
        XCTAssertTrue(tryMangaRider.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["template-swipe-hint"].exists)

        app.swipeDown()
        XCTAssertTrue(tryCowboy.waitForExistence(timeout: 3))
        XCTAssertTrue(tryCowboy.isHittable)

        app.swipeUp()
        XCTAssertTrue(tryMangaRider.waitForExistence(timeout: 3))
        XCTAssertTrue(tryMangaRider.isHittable)
        tryMangaRider.tap()
        XCTAssertTrue(app.staticTexts["Upload Image"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["upload-sample-preview"].exists)
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
        let tryBelovedBaby = app.buttons["Try Beloved Baby"]
        XCTAssertTrue(tryBelovedBaby.waitForExistence(timeout: 3))
        XCTAssertTrue(tryBelovedBaby.isHittable)

        app.swipeDown()
        XCTAssertTrue(tryPlayfulCartoon.waitForExistence(timeout: 3))

        app.swipeUp()
        XCTAssertTrue(tryBelovedBaby.waitForExistence(timeout: 3))
        tryBelovedBaby.tap()

        XCTAssertTrue(app.navigationBars["Dear Baby"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["guided-video-editor"].exists)
        XCTAssertTrue(app.staticTexts["Image1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["upload-sample-preview"].exists)
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
        attachScreenshot(named: "Membership", app: app)

        let proPlus = app.buttons["membership-tier-proPlus"]
        XCTAssertTrue(proPlus.waitForExistence(timeout: 2))
        proPlus.tap()
        XCTAssertTrue(app.staticTexts["900"].waitForExistence(timeout: 2))
        attachScreenshot(named: "Membership PRO Plus", app: app)

        app.buttons["Close membership"].tap()

        XCTAssertTrue(app.buttons["Close limited offer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["limited-offer-try-now"].exists)
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
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer", "-loggedIn"]
        app.launch()

        app.buttons["AI Photo"].tap()
        app.buttons["Open Pro membership"].tap()

        let continueButton = app.buttons["membership-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertEqual(continueButton.value as? String, "loged_pro_yearly")
        attachScreenshot(named: "Logged In Membership PRO", app: app)

        app.buttons["membership-billing-weekly"].tap()
        XCTAssertEqual(continueButton.value as? String, "loged_pro_weekly")

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
            "-showSummerOfferPreview",
        ]
        app.launch()

        let close = app.buttons["Close summer offer"]
        let restore = app.buttons["Restore"]
        let weekly = app.buttons["Weekly Plan"]
        let annual = app.buttons["Annual Plan"]
        let continueButton = app.buttons["Continue"]

        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(restore.waitForExistence(timeout: 2))
        XCTAssertTrue(restore.isHittable)
        XCTAssertTrue(weekly.isHittable)
        XCTAssertTrue(annual.isHittable)
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertEqual(annual.value as? String, "Selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_yearly")

        weekly.tap()
        XCTAssertEqual(weekly.value as? String, "Selected")
        XCTAssertEqual(annual.value as? String, "Not selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_weekly")

        annual.tap()
        XCTAssertEqual(annual.value as? String, "Selected")
        XCTAssertEqual(continueButton.value as? String, "special_gift_yearly")
        attachScreenshot(named: "Summer 65 Percent Component Offer", app: app)

        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSuggestionRoute() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-loggedIn"]
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
    func testHomeFixedFeatureRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skipOnboarding")
        app.launch()

        let routes = [
            ("oneTapRestore", "AI One-Tap Restore"),
            ("enhanceVideo", "Enhance Video"),
            ("photoToVideo", "Video Generator"),
            ("aiImage", "AI Image"),
            ("fusion", "Fusion"),
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
            attachScreenshot(named: "Fixed Feature \(route.0)", app: app)
            app.buttons["Back"].tap()
            XCTAssertTrue(strip.waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testAIPhotoFixedFeatureRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skipOnboarding")
        app.launch()

        let photoTab = app.buttons["AI Photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 3))
        photoTab.tap()

        let routes = [
            ("oneTapRestore", "AI One-Tap Restore"),
            ("enhancePhoto", "AI Enhance"),
            ("imageToImage", "AI Image"),
            ("textToImage", "AI Image")
        ]

        for (index, route) in routes.enumerated() {
            let button = app.buttons["photo-fixed-feature-\(route.0)"]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing AI Photo route \(route.0)")
            button.tap()
            XCTAssertTrue(app.staticTexts[route.1].waitForExistence(timeout: 3))

            if index == 2 {
                XCTAssertTrue(app.buttons["ai-image-model-picker"].waitForExistence(timeout: 2))
                app.buttons["ai-image-model-picker"].tap()
                XCTAssertTrue(app.buttons["ai-image-model-GPT Image 2"].waitForExistence(timeout: 2))
                attachScreenshot(named: "AI Photo model menu", app: app)
                app.buttons["ai-image-model-GPT Image 2"].tap()

                app.buttons["Edit output settings"].tap()
                XCTAssertTrue(app.staticTexts["Resolution"].waitForExistence(timeout: 2))
                XCTAssertTrue(app.staticTexts["Output Image Number"].exists)
                attachScreenshot(named: "AI Photo image settings", app: app)
                app.buttons["Close output settings"].tap()
            }

            if index == 3 {
                XCTAssertTrue(app.buttons["feature-mode-Text to Image"].waitForExistence(timeout: 2))
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
    func testFirstLaunchOnboardingAndGuestRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-forceOnboarding",
            "-skipStartupAnimation",
            "-disableReturningOffer",
            "-resetLimitedOfferEligibility",
            "-forceLimitedOffer"
        ]
        app.launch()

        let continueButton = app.buttons["onboarding-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 4))
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

        let freeUse = app.buttons["Free Use"]
        XCTAssertTrue(freeUse.waitForExistence(timeout: 3))
        attachScreenshot(named: "Guest Home", app: app)

        XCTAssertTrue(app.buttons["Close limited offer"].waitForExistence(timeout: 3))
        app.buttons["Close limited offer"].tap()

        freeUse.tap()
        XCTAssertTrue(app.staticTexts["Welcome to\nPhoto Revive AI"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["sign-in-google"].exists)
        attachScreenshot(named: "Sign In", app: app)
        app.buttons["Close sign in"].tap()

        let discountBanner = app.buttons["home-discount-banner"]
        XCTAssertTrue(discountBanner.waitForExistence(timeout: 2))
        discountBanner.tap()
        XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testGuestProtectedHomeEntryPointsRequireLogin() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer", "-useLocalFeatureCatalog"]
        app.launch()

        assertRequiresLogin(app.buttons["Free Use"], app: app)
        assertRequiresLogin(app.buttons["Open daily gift"], app: app)
        assertRequiresLogin(app.buttons["Open 65% summer offer"], app: app)
        assertRequiresLogin(app.buttons["home-discount-banner"], app: app)
        assertRequiresLogin(app.buttons["Me"], app: app)
    }

    @MainActor
    func testGuestUploadActionsRequireLogin() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-disableReturningOffer", "-useLocalFeatureCatalog"]
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

        let memory = app.buttons["template-memory"]
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
            "-forceFamilyExclusiveReturningOffer"
        ]
        app.launch()

        let familyClose = app.buttons["returning-offer-close"]
        XCTAssertTrue(familyClose.waitForExistence(timeout: 4))
        attachScreenshot(named: "Returning Offer Family", app: app)
        familyClose.tap()

        let trialStart = app.buttons["returning-trial-start"]
        XCTAssertTrue(trialStart.waitForExistence(timeout: 2))
        attachScreenshot(named: "Returning Offer Free Trial", app: app)
        app.buttons["returning-trial-close"].tap()
    }

    @MainActor
    func testReturningSuperPrizeOffer() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-skipOnboarding",
            "-forceReturningOffer",
            "-forceSuperPrizeReturningOffer"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["super-prize-continue"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Close super prize"].exists)
        attachScreenshot(named: "Returning Offer Super Prize", app: app)
        app.buttons["Close super prize"].tap()
        XCTAssertTrue(app.buttons["returning-trial-start"].waitForExistence(timeout: 2))
        app.buttons["returning-trial-close"].tap()
    }

    @MainActor
    func testGeneratedVideoResultRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipOnboarding", "-loggedIn"]
        app.launch()

        app.buttons["Open daily gift"].tap()
        app.buttons["daily-check-in"].tap()
        app.buttons["Dismiss check-in success"].tap()

        app.buttons["invite-friends-link"].tap()
        let redemptionCode = app.textFields["Invitation Code"]
        XCTAssertTrue(redemptionCode.waitForExistence(timeout: 2))
        redemptionCode.tap()
        redemptionCode.typeText("local-flow")
        app.buttons["Redeem"].tap()
        app.alerts["Credits added"].buttons["OK"].tap()
        app.navigationBars["Invite Friends"].buttons.firstMatch.tap()
        app.buttons["Close rewards"].tap()

        let memoryCover = app.buttons["template-memory"]
        if !memoryCover.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(memoryCover.waitForExistence(timeout: 2))
        memoryCover.tap()
        app.buttons["Try Memory"].tap()

        let generate = app.buttons["creation-primary-action"]
        XCTAssertTrue(generate.waitForExistence(timeout: 2))
        generate.tap()

        XCTAssertTrue(app.staticTexts["Please wait (1-3 min)"].waitForExistence(timeout: 2))
        let removeWatermark = app.buttons["Remove watermark"]
        XCTAssertTrue(removeWatermark.waitForExistence(timeout: 4))
        attachScreenshot(named: "Generated Video Result", app: app)

        removeWatermark.tap()
        XCTAssertTrue(app.buttons["Close membership"].waitForExistence(timeout: 2))
        app.buttons["Close membership"].tap()

        app.buttons["Maximize generated video"].tap()
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 2))
        regenerate.tap()
        XCTAssertTrue(app.navigationBars["Revive Old Photos"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
}
