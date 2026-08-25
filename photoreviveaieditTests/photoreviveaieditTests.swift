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

    @MainActor
    @Test func videoGenerationOptionsEncodeEveryUploadSetting() throws {
        let options = PhotoReviveVideoGenerationOptions(
            resolution: "480p",
            aspectRatio: "9:16",
            duration: 8,
            sound: true,
            multiShot: true
        )

        let data = try JSONEncoder().encode(options)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["resolution"] as? String == "480p")
        #expect(object["aspect_ratio"] as? String == "9:16")
        #expect(object["duration"] as? Int == 8)
        #expect(object["sound"] as? Bool == true)
        #expect(object["multi_shot"] as? Bool == true)
    }

    @Test func cmsFixedFeatureRegistryMapsAllEightDestinationsExactly() throws {
        let keys = [
            "restore",
            "enhance_video",
            "photo_to_video",
            "ai_image",
            "enhance_photo",
            "text_to_video",
            "image_to_image",
            "text_to_image"
        ]

        let features = try keys.map { key in
            try #require(FixedFeature(cmsKey: key))
        }

        #expect(features == [
            .oneTapRestore,
            .enhanceVideo,
            .photoToVideo,
            .aiImage,
            .enhancePhoto,
            .textToVideo,
            .imageToImage,
            .textToImage
        ])
        #expect(FixedFeature(cmsKey: "unknown") == nil)
    }

    @Test func carouselCanTargetFixedFeatureWithoutTryNowItem() {
        let entry = TemplateDetailEntry(
            displayItem: TemplateItem(id: "fixed", title: "AI Image"),
            tryNowItem: nil,
            fixedFeatureTarget: .aiImage
        )

        #expect(entry.tryNowItem == nil)
        #expect(entry.fixedFeatureTarget == .aiImage)
    }

    @Test func carouselTryNowUsesConfiguredFilterPreviewAndFullTemplateList() throws {
        let targetPreviewURL = try #require(URL(string: "https://example.com/relife.mp4"))
        let targetItem = TemplateItem(
            id: "relife",
            title: "Relife",
            coverVideoURL: targetPreviewURL,
            generationKind: .video,
            imageReferenceCount: 2,
            detailGroupID: "cms-section-42",
            detailGroupTitle: "Revive Old Photos",
            promptTemplate: "Configured prompt",
            estimatedCredits: 60,
            modelType: "video",
            modelID: "configured-model"
        )
        let siblingItem = TemplateItem(
            id: "happy-moments",
            title: "Happy Moments",
            generationKind: .video,
            detailGroupID: "cms-section-42",
            detailGroupTitle: "Revive Old Photos"
        )

        let launch = TemplateCreationLaunch(
            template: targetItem,
            templates: [targetItem, siblingItem]
        )

        #expect(launch.template.id == "relife")
        #expect(launch.template.coverVideoURL == targetPreviewURL)
        #expect(launch.template.detailGroupTitle == "Revive Old Photos")
        #expect(launch.templates.map(\.id) == ["relife", "happy-moments"])
    }

    @Test func imageUploadCountSupportsFusionThreeSlotLayout() {
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
        let threeImages = TemplateItem(
            id: "three-images",
            title: "Three Images",
            generationKind: .image,
            imageReferenceCount: 3
        )
        let invalidFourImages = TemplateItem(
            id: "invalid-four-images",
            title: "Invalid Four Images",
            generationKind: .image,
            imageReferenceCount: 4
        )

        #expect(oneImage.imageUploadCount == 1)
        #expect(twoImages.imageUploadCount == 2)
        #expect(threeImages.imageUploadCount == 3)
        #expect(invalidFourImages.imageUploadCount == 3)
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
            promptIsEditable: true,
            promptTemplate: "Use both references."
        )

        #expect(noPrompt.showsPrompt == false)
        #expect(noPrompt.imageUploadCount == 1)
        #expect(promptWithTwoImages.showsPrompt == true)
        #expect(promptWithTwoImages.promptIsEditable == true)
        #expect(promptWithTwoImages.imageUploadCount == 2)
        #expect(promptWithTwoImages.promptTemplate == "Use both references.")
    }

    @Test func sectionPromptSwitchAppliesToEveryFilterRegardlessOfPromptContent() {
        let configuredPrompt = TemplateItem(
            id: "configured-prompt",
            title: "Configured Prompt",
            showsPrompt: true,
            promptTemplate: "Keep this generation prompt."
        )
        let emptyPrompt = TemplateItem(
            id: "empty-prompt",
            title: "Empty Prompt",
            showsPrompt: false,
            promptTemplate: nil
        )

        let hiddenSection = TemplateSection(
            "Hidden",
            showsPrompt: false,
            items: [configuredPrompt, emptyPrompt]
        )
        let visibleSection = TemplateSection(
            "Visible",
            showsPrompt: true,
            promptIsEditable: true,
            items: [configuredPrompt, emptyPrompt]
        )

        #expect(hiddenSection.items.allSatisfy { !$0.showsPrompt })
        #expect(visibleSection.items.allSatisfy { $0.showsPrompt })
        #expect(visibleSection.items.allSatisfy { $0.promptIsEditable })
        #expect(visibleSection.items[1].promptTemplate == nil)
    }

    @Test func uploadPlaceholderImagesStayAlignedWithImageReferences() throws {
        let first = try #require(URL(string: "https://example.com/woman.jpg"))
        let third = try #require(URL(string: "https://example.com/mountain.jpg"))
        let item = TemplateItem(
            id: "fusion",
            title: "Fusion",
            imageReferenceCount: 3,
            promptTemplate: "@Image1 rides @Image2 through @Image3",
            uploadPlaceholderURLs: [first, nil, third]
        )

        #expect(item.imageUploadCount == 3)
        #expect(item.uploadPlaceholderURL(at: 0) == first)
        #expect(item.uploadPlaceholderURL(at: 1) == nil)
        #expect(item.uploadPlaceholderURL(at: 2) == third)
        #expect(item.uploadPlaceholderURL(at: 3) == nil)
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
        let automatic = TemplateSection("Automatic", badge: "auto", items: [])
        let configured = TemplateSection("Configured", badge: "new", items: [])
        let hidden = TemplateSection("Hidden", badge: "off", items: [])

        #expect(TemplateSectionBadgePolicy.badge(for: first, at: 0, on: .home) == "HOT")
        #expect(TemplateSectionBadgePolicy.badge(for: second, at: 1, on: .home) == "NEW")
        #expect(TemplateSectionBadgePolicy.badge(for: first, at: 0, on: .photo) == "HOT")
        #expect(TemplateSectionBadgePolicy.badge(for: second, at: 1, on: .photo) == "NEW")
        #expect(TemplateSectionBadgePolicy.badge(for: first, at: 0, on: .video) == "HOT")
        #expect(TemplateSectionBadgePolicy.badge(for: automatic, at: 1, on: .home) == "NEW")
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

    @Test func googleNonceSendsHashToGoogleAndRawValueToBackend() {
        let nonce = PhotoReviveGoogleNonce(rawValue: "test-nonce")

        #expect(nonce.rawValue == "test-nonce")
        #expect(nonce.hashedValue == "ed04c4e9ea6c49cf9ceb39098787c5b9842524f96b07ef45305476a11caec9b4")
        #expect(nonce.hashedValue != nonce.rawValue)
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

    @MainActor
    @Test func serverCreditBalanceDecodesFromUserStatus() throws {
        let data = try #require("""
        {
          "subscription_status": "active",
          "credits_balance": 735,
          "is_anonymous": false
        }
        """.data(using: .utf8))

        let status = try JSONDecoder().decode(PhotoReviveUserStatus.self, from: data)

        #expect(status.creditsBalance == 735)
        #expect(status.subscriptionStatus == "active")
        #expect(status.isAnonymous == false)
    }

    @MainActor
    @Test func referralStatusSupportsNestedCodeAndMissingRedemption() throws {
        let data = try #require("""
        {
          "code": { "code": "REVIVE88" },
          "reward_config": {
            "signup_referrer_credits": 80,
            "signup_referred_credits": 40,
            "subscription_referrer_credits": 200
          },
          "stats": {
            "invited_count": 3,
            "subscription_rewarded_count": 1
          }
        }
        """.data(using: .utf8))

        let status = try JSONDecoder().decode(ReferralStatus.self, from: data)

        #expect(status.invitationCode == "REVIVE88")
        #expect(status.rewardConfig?.signupReferrerCredits == 80)
        #expect(status.stats.invitedCount == 3)
        #expect(status.hasRedeemedReferral == false)
        #expect(status.isActive)
        #expect(status.sortOrder == 30)
    }

    @MainActor
    @Test func rewardCenterConfigurationDecodesGroupAndItemOrdering() throws {
        let data = try #require("""
        {
          "groups": [
            { "group_key": "special_offer", "title": "Special Offer", "sort_order": 2, "is_active": false },
            { "group_key": "daily_free_credits", "title": "Daily Free Credits", "sort_order": 1, "is_active": true },
            { "group_key": "one_time_rewards", "title": "One-Time Rewards", "sort_order": 3, "is_active": true }
          ],
          "special_offer": { "is_active": false, "sort_order": 1 },
          "tasks": [
            {
              "app_id": "photorevival",
              "task_code": "share_creation",
              "title": "Share a Creation",
              "reward_credits": 10,
              "verification_mode": "client_attested",
              "repeat_policy": "daily",
              "reward_center_group": "daily_free_credits",
              "sort_order": 2,
              "claim": null
            }
          ]
        }
        """.data(using: .utf8))

        let status = try JSONDecoder().decode(RewardTasksStatus.self, from: data)

        #expect(status.groups?.count == 3)
        #expect(status.groups?.first?.isActive == false)
        #expect(status.specialOffer?.isActive == false)
        #expect(status.tasks.first?.rewardCenterGroup == .dailyFreeCredits)
        #expect(status.tasks.first?.sortOrder == 2)
    }

    @MainActor
    @Test func dailyCheckinAndInviteDisplayControlsDecode() throws {
        let checkinData = try #require("""
        {
          "is_active": true,
          "signed_today": false,
          "claimable_day": 1,
          "claimable_credits": 20,
          "current_streak_day": 0,
          "sort_order": 1,
          "rewards": [
            { "day": 1, "credits": 20, "status": "claimable" },
            { "day": 2, "credits": 20, "status": "locked" },
            { "day": 3, "credits": 50, "status": "locked" },
            { "day": 4, "credits": 30, "status": "locked" },
            { "day": 5, "credits": 30, "status": "locked" },
            { "day": 6, "credits": 30, "status": "locked" },
            { "day": 7, "credits": 100, "status": "locked" }
          ]
        }
        """.data(using: .utf8))
        let referralData = try #require("""
        {
          "code": { "code": "REVIVE88" },
          "is_active": false,
          "sort_order": 3,
          "reward_config": null,
          "stats": { "invited_count": 0, "subscription_rewarded_count": 0 }
        }
        """.data(using: .utf8))

        let checkin = try JSONDecoder().decode(DailyCheckInStatus.self, from: checkinData)
        let referral = try JSONDecoder().decode(ReferralStatus.self, from: referralData)

        #expect(checkin.rewards.reduce(0) { $0 + $1.credits } == 280)
        #expect(checkin.sortOrder == 1)
        #expect(!referral.isActive)
    }

    @MainActor
    @Test func videoHistoryUsesServerFirstFrameAsCover() throws {
        let data = try #require("""
        {
          "id": "task-1",
          "scene": "photo_to_video",
          "status": "completed",
          "output_url": "https://cdn.example.com/result.mp4",
          "converted_url": null,
          "thumbnail_url": "https://cdn.example.com/result-first-frame.jpg",
          "thumbnail_source": "video_first_frame",
          "credits_used": 20,
          "created_at": "2026-08-25T00:00:00Z",
          "content_type": "video",
          "section_menu": "video",
          "error_message": null
        }
        """.data(using: .utf8))

        let task = try JSONDecoder().decode(GenerationHistoryTask.self, from: data)

        #expect(task.isVideo)
        #expect(task.coverURL?.absoluteString == "https://cdn.example.com/result-first-frame.jpg")
        #expect(task.resultURL?.absoluteString == "https://cdn.example.com/result.mp4")
    }

}
