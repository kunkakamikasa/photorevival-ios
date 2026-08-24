//
//  photoreviveaieditTests.swift
//  photoreviveaieditTests
//
//  Created by 马颖昆 on 2026/8/15.
//

import Foundation
import Testing
@testable import photoreviveaiedit

struct photoreviveaieditTests {

    @Test func tryNowTemplateUsesTheDisplayedPreviewMedia() throws {
        let displayedVideoURL = try #require(URL(string: "https://example.com/carousel.mp4"))
        let displayedImageURL = try #require(URL(string: "https://example.com/carousel.jpg"))
        let displayedItem = TemplateItem(
            id: "carousel",
            title: "Carousel",
            coverImageURL: displayedImageURL,
            coverVideoURL: displayedVideoURL,
            orientation: .landscape
        )
        let targetItem = TemplateItem(
            id: "target",
            title: "Target",
            generationKind: .video,
            imageReferenceCount: 2,
            promptTemplate: "Configured prompt",
            estimatedCredits: 60,
            modelType: "video",
            modelID: "configured-model"
        )

        let resolvedItem = targetItem.withPreviewMedia(from: displayedItem)

        #expect(resolvedItem.coverImageURL == displayedImageURL)
        #expect(resolvedItem.coverVideoURL == displayedVideoURL)
        #expect(resolvedItem.orientation == .landscape)
        #expect(resolvedItem.id == targetItem.id)
        #expect(resolvedItem.promptTemplate == targetItem.promptTemplate)
        #expect(resolvedItem.imageReferenceCount == targetItem.imageReferenceCount)
        #expect(resolvedItem.estimatedCredits == targetItem.estimatedCredits)
        #expect(resolvedItem.modelType == targetItem.modelType)
        #expect(resolvedItem.modelID == targetItem.modelID)
    }

    @Test func imageUploadCountUsesOneOrTwoSlots() {
        let oneImage = TemplateItem(
            id: "one-image",
            title: "One Image",
            generationKind: .image,
            imageReferenceCount: 1
        )
        let twoImages = TemplateItem(
            id: "two-images",
            title: "Two Images",
            generationKind: .image,
            imageReferenceCount: 2
        )
        let invalidThreeImages = TemplateItem(
            id: "invalid-three-images",
            title: "Invalid Three Images",
            generationKind: .image,
            imageReferenceCount: 3
        )

        #expect(oneImage.imageUploadCount == 1)
        #expect(twoImages.imageUploadCount == 2)
        #expect(invalidThreeImages.imageUploadCount == 2)
    }

    @Test func videoTemplatePromptSwitchIsStoredAtTemplateLevel() {
        let noPrompt = TemplateItem(
            id: "no-prompt-video",
            title: "No Prompt",
            generationKind: .video,
            imageReferenceCount: 1,
            showsPrompt: false
        )
        let promptWithTwoImages = TemplateItem(
            id: "prompt-video",
            title: "Prompt",
            generationKind: .video,
            imageReferenceCount: 2,
            showsPrompt: true,
            promptTemplate: "Use both references."
        )

        #expect(noPrompt.showsPrompt == false)
        #expect(noPrompt.imageUploadCount == 1)
        #expect(promptWithTwoImages.showsPrompt == true)
        #expect(promptWithTwoImages.imageUploadCount == 2)
        #expect(promptWithTwoImages.promptTemplate == "Use both references.")
    }

    @Test func localPhotoHeroTryNowItemsUseImageUploadFlow() {
        #expect(TemplateCatalog.localPhotoHeroEntries.allSatisfy {
            $0.displayItem.generationKind == .image && $0.tryNowItem?.generationKind == .image
        })
    }

    @Test func localVideoCatalogIncludesDearBabyFilters() throws {
        let dearBaby = try #require(TemplateCatalog.videoSections.first { $0.title == "Dear Baby" })

        #expect(dearBaby.items.map(\.title) == [
            "Beloved Baby",
            "Our Children",
            "Grow up",
            "Birthday"
        ])
        #expect(dearBaby.items.allSatisfy { $0.generationKind == .video })
        #expect(dearBaby.items.allSatisfy { $0.videoName?.hasPrefix("dear_baby_") == true })
    }

    @Test func templateBadgesFollowTemplatePosition() {
        let first = TemplateItem(id: "first", title: "First")
        let second = TemplateItem(id: "second", title: "Second")

        #expect(TemplateBadgePolicy.badge(for: first, at: 0, on: .home) == "HOT")
        #expect(TemplateBadgePolicy.badge(for: second, at: 1, on: .home) == "NEW")
        #expect(TemplateBadgePolicy.badge(for: first, at: 0, on: .photo) == "HOT")
        #expect(TemplateBadgePolicy.badge(for: second, at: 1, on: .photo) == nil)
        #expect(TemplateBadgePolicy.badge(for: first, at: 0, on: .video) == nil)
    }

    @Test func cmsTemplateBadgeOverridesPositionDefault() {
        let newItem = TemplateItem(id: "new", title: "Configured New", badge: "new")
        let hiddenItem = TemplateItem(id: "hidden", title: "Configured Off", badge: "none")

        #expect(TemplateBadgePolicy.badge(for: newItem, at: 0, on: .home) == "NEW")
        #expect(TemplateBadgePolicy.badge(for: hiddenItem, at: 0, on: .photo) == nil)
        #expect(TemplateBadgeValue.normalized(" off ") == nil)
        #expect(TemplateBadgeValue.normalized(" hot ") == "HOT")
    }

    @Test func templateListBadgesFollowCmsOrder() {
        let first = TemplateSection("First", items: [])
        let second = TemplateSection("Second", items: [])
        let configured = TemplateSection("Configured", badge: "new", items: [])
        let hidden = TemplateSection("Hidden", badge: "off", items: [])

        #expect(TemplateSectionBadgePolicy.badge(for: first, at: 0, on: .home) == "HOT")
        #expect(TemplateSectionBadgePolicy.badge(for: second, at: 1, on: .home) == "NEW")
        #expect(TemplateSectionBadgePolicy.badge(for: first, at: 0, on: .photo) == "HOT")
        #expect(TemplateSectionBadgePolicy.badge(for: second, at: 1, on: .photo) == nil)
        #expect(TemplateSectionBadgePolicy.badge(for: configured, at: 0, on: .home) == "NEW")
        #expect(TemplateSectionBadgePolicy.badge(for: hidden, at: 0, on: .home) == nil)
    }

    @Test func homeSectionsMergeVideoAndImageMenusByCmsOrder() {
        let videoFirst = TemplateSection(
            "Video First",
            items: [TemplateItem(id: "video-first", title: "Video First")],
            generationKind: .video,
            sortOrder: 1
        )
        let videoTie = TemplateSection(
            "Video Tie",
            items: [TemplateItem(id: "video-tie", title: "Video Tie")],
            generationKind: .video,
            sortOrder: 5
        )
        let imageTie = TemplateSection(
            "Image Tie",
            items: [TemplateItem(id: "image-tie", title: "Image Tie")],
            generationKind: .image,
            sortOrder: 5
        )
        let imageLast = TemplateSection(
            "Image Last",
            items: [TemplateItem(id: "image-last", title: "Image Last")],
            generationKind: .image,
            sortOrder: 6
        )

        let merged = TemplateSection.mergedForHome(
            videoSections: [videoFirst, videoTie],
            imageSections: [imageTie, imageLast]
        )

        #expect(merged.map(\.title) == ["Video First", "Video Tie", "Image Tie", "Image Last"])
        #expect(merged.map(\.generationKind) == [.video, .video, .image, .image])
    }

    @Test func trackingAuthorizationBypassArguments() {
        #expect(!TrackingAuthorizationPolicy.shouldBypassSystemPrompt(arguments: []))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-skipTrackingAuthorization"]
        ))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-skipOnboarding"]
        ))
        #expect(TrackingAuthorizationPolicy.shouldBypassSystemPrompt(
            arguments: ["-forceOnboarding"]
        ))
    }

    @Test func returningOfferEligibility() {
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: false,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: false,
            arguments: []
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: true,
            isLoggedIn: true,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: false,
            isSubscribed: false,
            isLoggedIn: false,
            arguments: ["-forceReturningOffer"]
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            hasOpenedMainExperience: true,
            isSubscribed: false,
            isLoggedIn: true,
            arguments: ["-skipOnboarding"]
        ))
    }

    @Test func subscriptionProductIDs() {
        #expect(SubscriptionProductID.proYearly.rawValue == "pro_yearly")
        #expect(SubscriptionProductID.proWeekly.rawValue == "pro_weekly")
        #expect(SubscriptionProductID.proPlusYearly.rawValue == "proplus_yearly")
        #expect(SubscriptionProductID.proPlusWeekly.rawValue == "proplus_weekly")
        #expect(SubscriptionProductID.loggedProYearly.rawValue == "loged_pro_yearly")
        #expect(SubscriptionProductID.loggedProWeekly.rawValue == "loged_pro_weekly")
        #expect(SubscriptionProductID.loggedProPlusYearly.rawValue == "loged_proplus_yearly")
        #expect(SubscriptionProductID.loggedProPlusWeekly.rawValue == "loged_proplus_weekly")
        #expect(SubscriptionProductID.limitedTimeOfferYearly.rawValue == "limited_time_offer_yearly")
        #expect(SubscriptionProductID.specialGiftYearly.rawValue == "special_gift_yearly")
        #expect(SubscriptionProductID.specialGiftWeekly.rawValue == "special_gift_weekly")
        #expect(SubscriptionProductID.familyExclusiveWeekly.rawValue == "family_exclusive_weekly")
        #expect(SubscriptionProductID.superPrizeWeekly.rawValue == "super_prize_weekly")
        #expect(SubscriptionProductID.threeDayFreeTrialYearly.rawValue == "3dayfreetrial_yearly")
    }

    @Test func returningOfferVariantSelection() {
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceSuperPrizeReturningOffer"],
            randomValue: false
        ) == .superPrize)
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceFamilyExclusiveReturningOffer"],
            randomValue: true
        ) == .familyExclusive)
        #expect(ReturningOfferVariant.select(arguments: [], randomValue: true) == .superPrize)
        #expect(ReturningOfferVariant.select(arguments: [], randomValue: false) == .familyExclusive)
    }

    @Test func limitedOfferIsDaily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dayKey = LimitedOfferEligibility.dayKey(for: date, calendar: calendar)

        #expect(!LimitedOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date,
            calendar: calendar
        ))
        #expect(LimitedOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date.addingTimeInterval(86_400),
            calendar: calendar
        ))
    }

    @Test func returningOfferIsDaily() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dayKey = calendar.startOfDay(for: date).timeIntervalSince1970

        #expect(ReturningOfferEligibility.canPresent(
            lastPresentedDay: 0,
            now: date,
            calendar: calendar
        ))
        #expect(!ReturningOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date,
            calendar: calendar
        ))
        #expect(ReturningOfferEligibility.canPresent(
            lastPresentedDay: dayKey,
            now: date.addingTimeInterval(86_400),
            calendar: calendar
        ))
    }

}
