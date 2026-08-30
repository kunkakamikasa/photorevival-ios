//
//  photoreviveaieditTests.swift
//  photoreviveaieditTests
//
//  Created by Mayingkun on 2026/8/15.
//

import Foundation
import Testing
import UIKit
@testable import photoreviveaiedit

struct photoreviveaieditTests {

    @MainActor
    @Test func catalogCanRetryAfterEveryInitialRequestFails() async {
        let fetchCounter = CatalogFetchCounter()
        let store = FeatureConfigStore(
            fetchCatalogData: { _ in
                await fetchCounter.recordFailure()
            },
            restoresCatalogSnapshot: false
        )

        await store.load()
        let firstAttemptCount = await fetchCounter.count
        await store.load()
        let secondAttemptCount = await fetchCounter.count

        #expect(firstAttemptCount == 4)
        #expect(secondAttemptCount == 8)
        #expect(!store.isLoading)
    }

    @Test func selectingShareActivityIsEnoughToClaimReward() {
        #expect(
            RewardShareSelectionPolicy.shouldClaim(
                activityType: .message,
                completed: false
            )
        )
        #expect(
            RewardShareSelectionPolicy.shouldClaim(
                activityType: .copyToPasteboard,
                completed: false
            )
        )
        #expect(
            RewardShareSelectionPolicy.shouldClaim(
                activityType: nil,
                completed: true
            )
        )
        #expect(
            !RewardShareSelectionPolicy.shouldClaim(
                activityType: nil,
                completed: false
            )
        )
    }

    @MainActor
    @Test func socialShareRoutesTargetTheSelectedPlatform() throws {
        let resultURL = try #require(URL(string: "https://cdn.example.com/generated/result.mp4"))

        let whatsAppURL = try #require(GeneratedSocialShareRouter.whatsAppURL(for: resultURL))
        let whatsAppComponents = try #require(URLComponents(url: whatsAppURL, resolvingAgainstBaseURL: false))
        #expect(whatsAppComponents.scheme == "whatsapp")
        #expect(whatsAppComponents.host == "send")
        #expect(whatsAppComponents.queryItems?.first(where: { $0.name == "text" })?.value?.contains(resultURL.absoluteString) == true)

        let facebookURL = try #require(GeneratedSocialShareRouter.facebookURL(for: resultURL))
        let facebookComponents = try #require(URLComponents(url: facebookURL, resolvingAgainstBaseURL: false))
        #expect(facebookComponents.host == "www.facebook.com")
        #expect(facebookComponents.path == "/sharer/sharer.php")
        #expect(facebookComponents.queryItems?.first(where: { $0.name == "u" })?.value == resultURL.absoluteString)

        let localURL = URL(fileURLWithPath: "/tmp/result.mp4")
        #expect(GeneratedSocialShareRouter.whatsAppURL(for: localURL) == nil)
        #expect(GeneratedSocialShareRouter.facebookURL(for: localURL) == nil)
    }

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

    @Test func liveSeedanceOptionsMatchTheEndToEndProviderContract() {
        let options = VideoGenerationOptionCapabilities.current(
            forModelID: "doubao-seedance-1-5-pro-251215"
        )

        #expect(options.supportsSound)
        #expect(options.supportsMultiShot)
        #expect(options.resolutions == ["480p", "720p", "1080p"])
        #expect(options.durations == ["5s", "8s", "10s"])
        #expect(options.aspectRatios == ["16:9", "1:1", "9:16", "4:3", "3:4"])
        #expect(!options.aspectRatios.contains("21:9"))
    }

    @Test func liveGrokVideoDoesNotAdvertiseUnsupportedMultiShot() {
        let options = VideoGenerationOptionCapabilities.current(
            forModelID: "text-grok-video-3"
        )

        #expect(options.supportsSound)
        #expect(!options.supportsMultiShot)
        #expect(options.normalizedResolution("540p") == "480p")
        #expect(options.normalizedAspectRatio("21:9") == "16:9")
    }

    @Test func unknownVideoModelsReceiveOnlyConservativeOptions() {
        let options = VideoGenerationOptionCapabilities.current(
            forModelID: "future-unreviewed-model"
        )

        #expect(!options.supportsSound)
        #expect(!options.supportsMultiShot)
        #expect(options.durations == ["5s"])
        #expect(options.resolutions == ["480p"])
        #expect(options.aspectRatios == ["9:16"])
    }

    @Test func seedream45AdvertisesOnlyItsVerifiedImageOptions() {
        let options = ImageGenerationOptionCapabilities.current(
            forModelID: "doubao-seedream-4-5-251128"
        )

        #expect(options.resolutions == ["2K"])
        #expect(options.outputCounts == ["1"])
        #expect(options.aspectRatios == [
            "1:1", "4:3", "3:4", "16:9", "9:16", "3:2", "2:3", "21:9",
        ])
        #expect(options.normalizedAspectRatio("21:9") == "21:9")
    }

    @Test func unverifiedImageModelsDoNotInheritSeedreamRatios() {
        let options = ImageGenerationOptionCapabilities.current(
            forModelID: "grok-3-image"
        )

        #expect(options.aspectRatios.isEmpty)
        #expect(options.normalizedAspectRatio("9:16") == nil)
    }

    @MainActor
    @Test func longRunningGenerationRequestsAllowServerSidePreprocessing() {
        #expect(PhotoReviveAPIClient.longRunningGenerationTimeout == 300)
    }

    @MainActor
    @Test func cmsCreditPricingMatchesEveryRequestedVideoCombination() throws {
        let json = """
        {
          "one_tap_restore_credits": 35,
          "video_base_credits": 40,
          "video_default_duration_seconds": 5,
          "video_extra_duration_credits_per_second": 8,
          "video_sound_credits": 20,
          "video_multi_shot_credits": 20,
          "video_720p_extra_credits_per_second": 4,
          "video_1080p_extra_credits_per_second": 12,
          "other_video_credits": 60,
          "enhance_photo_credits": 30,
          "image_to_image_credits": 30,
          "text_to_image_credits": 30,
          "other_image_credits": 30,
          "default_video_resolution": "480p",
          "default_video_sound": false,
          "default_video_multi_shot": false
        }
        """
        let pricing = try JSONDecoder().decode(AppCreditPricing.self, from: Data(json.utf8))

        #expect(pricing.videoGenerationCredits(duration: 5, resolution: "480p", sound: false, multiShot: false) == 40)
        #expect(pricing.videoGenerationCredits(duration: 8, resolution: "480p", sound: false, multiShot: false) == 64)
        #expect(pricing.videoGenerationCredits(duration: 10, resolution: "480p", sound: false, multiShot: false) == 80)
        #expect(pricing.videoGenerationCredits(duration: 5, resolution: "720p", sound: false, multiShot: false) == 60)
        #expect(pricing.videoGenerationCredits(duration: 5, resolution: "1080p", sound: true, multiShot: true) == 140)
        #expect(pricing.videoGenerationCredits(duration: 8, resolution: "720p", sound: false, multiShot: false) == 96)
        #expect(pricing.videoGenerationCredits(duration: 8, resolution: "1080p", sound: false, multiShot: false) == 160)
        #expect(pricing.otherVideoCredits == 60)
        #expect(pricing.imageToImageCredits == 30)
        #expect(pricing.textToImageCredits == 30)
    }

    @MainActor
    @Test func legacyCMSVideoResolutionNormalizesTo480p() {
        let pricing = AppCreditPricing(defaultVideoResolution: "540p")

        #expect(pricing.defaultVideoResolution == "480p")
    }

    @Test func cmsFixedFeatureRegistryMapsAllSevenDestinationsExactly() throws {
        let keys = [
            "restore",
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
            .photoToVideo,
            .aiImage,
            .enhancePhoto,
            .textToVideo,
            .imageToImage,
            .textToImage
        ])
        #expect(FixedFeature(cmsKey: "unknown") == nil)
    }

    @MainActor
    @Test func aiVideoModesFollowConfiguredVideoEntriesAndOrder() {
        let configured = [
            FixedFeature.oneTapRestore,
            .textToVideo,
            .enhancePhoto,
            .photoToVideo,
            .aiImage
        ].map { feature in
            HomeQuickAction(
                feature: feature,
                title: "CMS \(feature.title)",
                item: TemplateItem(id: "test-\(feature.id)", title: feature.title)
            )
        }

        let displayed = FeatureConfigStore.displayedVideoModeActions(configured: configured)

        #expect(displayed.map(\.feature) == [.textToVideo, .photoToVideo])
        #expect(displayed.map(\.title) == ["CMS Text To Video", "CMS Photo To Video"])

        let oneConfiguredMode = FeatureConfigStore.displayedVideoModeActions(
            configured: configured.filter { $0.feature == .photoToVideo }
        )
        #expect(oneConfiguredMode.map(\.feature) == [.photoToVideo])
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

    @MainActor
    @Test func aiImageQuickActionResolvesBothGenerationEndpoints() {
        let imageTarget = FeatureGenerationTarget(
            itemID: "image-item",
            endpoint: "image-to-image",
            modelType: "image_to_image",
            modelID: "image-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let textTarget = FeatureGenerationTarget(
            itemID: "text-item",
            endpoint: "text-to-image",
            modelType: "text_to_image",
            modelID: "text-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let action = HomeQuickAction(
            feature: .aiImage,
            item: TemplateItem(id: "ai-image", title: "AI Image"),
            generationTargets: [imageTarget, textTarget]
        )

        #expect(action.generationTarget(endpoint: "image-to-image") == imageTarget)
        #expect(action.generationTarget(endpoint: "text-to-image") == textTarget)
        #expect(action.generationTarget == imageTarget)
    }

    @MainActor
    @Test func aiImageQuickActionAlsoPowersDedicatedPhotoTools() {
        let imageTarget = FeatureGenerationTarget(
            itemID: "image-item",
            endpoint: "image-to-image",
            modelType: "image_to_image",
            modelID: "image-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let textTarget = FeatureGenerationTarget(
            itemID: "text-item",
            endpoint: "text-to-image",
            modelType: "text_to_image",
            modelID: "text-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let quickActions = [
            HomeQuickAction(
                feature: .aiImage,
                item: TemplateItem(id: "ai-image", title: "AI Image"),
                generationTargets: [imageTarget, textTarget]
            )
        ]

        #expect(FixedFeatureGenerationTargetResolver.target(
            for: .imageToImage,
            endpoint: "image-to-image",
            in: quickActions
        ) == imageTarget)
        #expect(FixedFeatureGenerationTargetResolver.target(
            for: .textToImage,
            endpoint: "text-to-image",
            in: quickActions
        ) == textTarget)
    }

    @MainActor
    @Test func dedicatedPhotoToolTargetOverridesAIImageAlias() {
        let combinedTarget = FeatureGenerationTarget(
            itemID: "combined-text-item",
            endpoint: "text-to-image",
            modelType: "text_to_image",
            modelID: "combined-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let dedicatedTarget = FeatureGenerationTarget(
            itemID: "dedicated-text-item",
            endpoint: "text-to-image",
            modelType: "text_to_image",
            modelID: "dedicated-model",
            estimatedCredits: 30,
            promptTemplate: nil
        )
        let quickActions = [
            HomeQuickAction(
                feature: .aiImage,
                item: TemplateItem(id: "ai-image", title: "AI Image"),
                generationTargets: [combinedTarget]
            ),
            HomeQuickAction(
                feature: .textToImage,
                item: TemplateItem(id: "text-to-image", title: "Text to Image"),
                generationTarget: dedicatedTarget
            )
        ]

        #expect(FixedFeatureGenerationTargetResolver.target(
            for: .textToImage,
            endpoint: "text-to-image",
            in: quickActions
        ) == dedicatedTarget)
    }

    @MainActor
    @Test func aiImageFixedFeaturePayloadDecodesBothGenerationTargets() throws {
        let data = try #require("""
        {
          "items": [
            {
              "feature_key": "ai_image",
              "title": "AI Image",
              "cover_type": "video",
              "cover_video_url": "https://example.com/ai-image.mp4",
              "generation_target": {
                "item_id": "image-item",
                "endpoint": "image-to-image",
                "model_type": "image_to_image",
                "model_id": "image-model",
                "estimated_credits": 30,
                "prompt_template": null
              },
              "generation_targets": [
                {
                  "item_id": "image-item",
                  "endpoint": "image-to-image",
                  "model_type": "image_to_image",
                  "model_id": "image-model",
                  "estimated_credits": 30,
                  "prompt_template": null
                },
                {
                  "item_id": "text-item",
                  "endpoint": "text-to-image",
                  "model_type": "text_to_image",
                  "model_id": "text-model",
                  "estimated_credits": 30,
                  "prompt_template": null
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))
        let payload = try JSONDecoder().decode(RemoteFixedFeatureResponse.self, from: data)
        let action = try #require(payload.items.first?.quickAction)

        #expect(action.feature == .aiImage)
        #expect(action.generationTargets.map(\.endpoint) == [
            "image-to-image",
            "text-to-image"
        ])
    }

    @MainActor
    @Test func homeHeroDoesNotExposeTemplateFallbackBeforeCarouselResolves() {
        let fallback = TemplateItem(id: "fallback", title: "First Filter")

        #expect(FeatureConfigStore.displayedHeroEntries(
            configured: [],
            fallbackItems: [fallback],
            waitsForRemoteCarousel: true
        ).isEmpty)

        #expect(FeatureConfigStore.displayedHeroEntries(
            configured: [],
            fallbackItems: [fallback],
            waitsForRemoteCarousel: false
        ).map(\.displayItem.id) == ["fallback"])
    }

    @Test func homeHeroPromotionTargetsTheCurrentSubscriptionAudience() throws {
        let imageURL = try #require(URL(string: "https://example.com/promotion.jpg"))
        let coupon = CMSCouponOffer(
            id: "coupon",
            placement: "hero",
            coverImageURL: imageURL,
            weeklyPlan: CMSCouponPlan(productID: "weekly"),
            annualPlan: CMSCouponPlan(productID: "annual")
        )
        let creditPurchase = CMSCreditPurchasePromotion(
            id: "credit-purchase",
            coverImageURL: imageURL
        )

        #expect(CMSHomeHeroPromotion.visible(
            isSubscribed: false,
            coupon: coupon,
            creditPurchase: creditPurchase
        ) == .subscriptionCoupon(coupon))
        #expect(CMSHomeHeroPromotion.visible(
            isSubscribed: true,
            coupon: coupon,
            creditPurchase: creditPurchase
        ) == .creditPurchase(creditPurchase))
        #expect(CMSHomeHeroPromotion.visible(
            isSubscribed: true,
            coupon: coupon,
            creditPurchase: nil
        ) == nil)
        #expect(CMSHomeHeroPromotion.visible(
            isSubscribed: false,
            coupon: nil,
            creditPurchase: creditPurchase
        ) == nil)
    }

    @Test func gifDecoderPreservesEveryAnimationFrame() throws {
        let encoded = "R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQADAAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQBEgABACwAAAAAAgACAIEAAP8AAAAAAAAAAAAIBgABCAQQEAA7"
        let data = try #require(Data(base64Encoded: encoded))
        let image = try #require(TemplateImageDecoder.image(from: data))

        #expect(image.images?.count == 2)
        #expect(abs(image.duration - 0.3) < 0.001)
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

    @Test func imageUploadCountSupportsThreeReferenceSlots() {
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
            id: "multi-reference",
            title: "Multi Reference",
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

    @Test func startupAnimationWaitsForFourSecondsAndFirstInstallNetwork() {
        #expect(StartupAnimationPolicy.minimumDisplayNanoseconds == 4_000_000_000)
        #expect(StartupAnimationPolicy.shouldKeepShowing(
            minimumDurationElapsed: false,
            isFirstInstall: true,
            hasUsableNetworkPath: true
        ))
        #expect(StartupAnimationPolicy.shouldKeepShowing(
            minimumDurationElapsed: true,
            isFirstInstall: true,
            hasUsableNetworkPath: false
        ))
        #expect(!StartupAnimationPolicy.shouldKeepShowing(
            minimumDurationElapsed: true,
            isFirstInstall: true,
            hasUsableNetworkPath: true
        ))
        #expect(!StartupAnimationPolicy.shouldKeepShowing(
            minimumDurationElapsed: true,
            isFirstInstall: false,
            hasUsableNetworkPath: false
        ))
    }

    @Test func launchPricePreloadIncludesEveryKnownStoreProduct() {
        let preloadedIDs = Set(StoreProductPreloadCatalog.knownProductIDs)
        let subscriptionIDs = Set(SubscriptionProductID.allCases.map(\.rawValue))
        let creditIDs = Set(CreditProductCatalog.allProductIDs)

        #expect(subscriptionIDs.isSubset(of: preloadedIDs))
        #expect(creditIDs.isSubset(of: preloadedIDs))
        #expect(preloadedIDs.count == subscriptionIDs.union(creditIDs).count)
    }

    @Test func googleNonceSendsHashToGoogleAndRawValueToBackend() {
        let nonce = PhotoReviveGoogleNonce(rawValue: "test-nonce")

        #expect(nonce.rawValue == "test-nonce")
        #expect(nonce.hashedValue == "ed04c4e9ea6c49cf9ceb39098787c5b9842524f96b07ef45305476a11caec9b4")
        #expect(nonce.hashedValue != nonce.rawValue)
    }

    @Test func returningOfferEligibility() {
        #expect(!ReturningOfferEligibility.shouldPresent(
            isReturningSession: false,
            isSubscribed: false,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: false,
            arguments: []
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: true,
            arguments: []
        ))
        #expect(ReturningOfferEligibility.shouldPresent(
            isReturningSession: false,
            isSubscribed: false,
            arguments: ["-forceReturningOffer"]
        ))
        #expect(!ReturningOfferEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: false,
            arguments: ["-skipOnboarding"]
        ))
    }

    @MainActor
    @Test func startupPromotionEvaluationCanOnlyBeClaimedOncePerLaunch() {
        let gate = StartupPromotionSessionGate()

        #expect(gate.claimAutomaticEvaluation())
        #expect(!gate.claimAutomaticEvaluation())
    }

    @MainActor
    @Test func debugPromotionPreviewSuppressesAutomaticStartupPromotion() {
        let gate = StartupPromotionSessionGate()

        gate.suppressAutomaticPromotionsForCurrentLaunch()

        #expect(gate.suppressesAutomaticPromotions)
        #expect(!gate.claimAutomaticEvaluation())
    }

    @Test func subscriberScratchEligibility() {
        #expect(SubscriberScratchCampaign.freeCreditLifetime == 7_200)
        #expect(SubscriberScratchEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: true,
            completedCampaignVersion: 0,
            arguments: []
        ))
        #expect(!SubscriberScratchEligibility.shouldPresent(
            isReturningSession: false,
            isSubscribed: true,
            completedCampaignVersion: 0,
            arguments: []
        ))
        #expect(!SubscriberScratchEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: false,
            completedCampaignVersion: 0,
            arguments: []
        ))
        #expect(!SubscriberScratchEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: true,
            completedCampaignVersion: SubscriberScratchCampaign.version,
            arguments: []
        ))
        #expect(SubscriberScratchEligibility.shouldPresent(
            isReturningSession: false,
            isSubscribed: false,
            completedCampaignVersion: SubscriberScratchCampaign.version,
            arguments: ["-forceSubscriberScratchOffer"]
        ))
        #expect(!SubscriberScratchEligibility.shouldPresent(
            isReturningSession: true,
            isSubscribed: true,
            completedCampaignVersion: 0,
            arguments: ["-skipOnboarding"]
        ))
    }

    @Test func creditProductCatalogUsesAppStoreProductIDs() {
        #expect(CreditProductCatalog.packs.map(\.credits) == [300, 900, 1_400])
        #expect(CreditProductCatalog.packs.map(\.productID) == [
            "basic300credits",
            "basic900credits",
            "basic1400credits"
        ])
        #expect(CreditProductCatalog.exitOfferBonus == 77)
        #expect(CreditProductCatalog.exitOfferPack.credits == 377)
        #expect(CreditProductCatalog.exitOfferPack.productID == "callback377")
        #expect(CreditProductCatalog.subscriberReturnOffer.credits == 1_600)
        #expect(CreditProductCatalog.subscriberReturnOffer.productID == "surprise1600credits")
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

    @Test func subscriptionUpgradeLevels() {
        #expect(SubscriptionPlanLevel(productID: "loged_pro_weekly") == .proWeekly)
        #expect(SubscriptionPlanLevel(productID: "pro_yearly") == .proAnnual)
        #expect(SubscriptionPlanLevel(productID: "loged_proplus_weekly") == .proPlusWeekly)
        #expect(SubscriptionPlanLevel(productID: "proplus_yearly") == .proPlusAnnual)
        #expect(SubscriptionPlanLevel(productID: "special_gift_yearly") == .proAnnual)
        #expect(SubscriptionPlanLevel.proPlusAnnual.isHighest)
        #expect(SubscriptionPlanLevel.proWeekly < SubscriptionPlanLevel.proPlusAnnual)
    }

    @Test func returningOfferVariantSelection() {
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceSuperPrizeReturningOffer"],
            limitedTimeAvailable: true,
            randomIndex: 0
        ) == .superPrize)
        #expect(ReturningOfferVariant.select(
            arguments: ["-forceFamilyExclusiveReturningOffer"],
            limitedTimeAvailable: true,
            randomIndex: 2
        ) == .familyExclusive)
        #expect(ReturningOfferVariant.select(
            arguments: [],
            limitedTimeAvailable: true,
            randomIndex: 0
        ) == .familyExclusive)
        #expect(ReturningOfferVariant.select(
            arguments: [],
            limitedTimeAvailable: true,
            randomIndex: 1
        ) == .superPrize)
        #expect(ReturningOfferVariant.select(
            arguments: [],
            limitedTimeAvailable: true,
            randomIndex: 2
        ) == .limitedTime)
        #expect(ReturningOfferVariant.select(
            arguments: [],
            limitedTimeAvailable: false,
            randomIndex: 2
        ) == .familyExclusive)
    }

    @Test func directTrialPresentationNeverUsesFamilyOfferAsItsInitialScreen() {
        #expect(ReturningOfferInitialPresentation.select(
            startsAtTrial: true,
            startsAtRetention: false
        ) == .checkingTrialEligibility)
        #expect(ReturningOfferInitialPresentation.select(
            startsAtTrial: false,
            startsAtRetention: true
        ) == .retention)
        #expect(ReturningOfferInitialPresentation.select(
            startsAtTrial: false,
            startsAtRetention: false
        ) == .family)
    }

    @Test func paywallFollowUpSelectionRespectsDailyLimitedOffer() {
        #expect(PaywallFollowUpOffer.select(
            limitedTimeAvailable: true,
            arguments: [],
            randomValue: true
        ) == .limitedTime)
        #expect(PaywallFollowUpOffer.select(
            limitedTimeAvailable: true,
            arguments: [],
            randomValue: false
        ) == .threeDayTrial)
        #expect(PaywallFollowUpOffer.select(
            limitedTimeAvailable: false,
            arguments: [],
            randomValue: true
        ) == .threeDayTrial)
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
    @Test func subscriptionVerificationImmediatelyUpdatesDisplayedCredits() {
        let store = AppAccountStore()
        let verification = SubscriptionVerificationResult(
            success: true,
            subscriptionStatus: "active",
            subscriptionExpireAt: nil,
            planType: "pro_weekly",
            productID: "pro_weekly",
            creditsBalance: 400,
            creditsGranted: 400,
            message: nil
        )

        store.applySubscriptionVerification(verification)

        #expect(store.creditsBalance == 400)
        #expect(store.hasLoadedCredits)
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

    @Test func rewardCenterSpecialOfferAlwaysRoutesSubscribersToCreditPacks() {
        #expect(
            RewardCenterSpecialOfferDestination.resolve(
                isSubscribed: true,
                isActive: true,
                hasMembershipOffer: false
            ) == .creditStore
        )
        #expect(
            RewardCenterSpecialOfferDestination.resolve(
                isSubscribed: false,
                isActive: true,
                hasMembershipOffer: true
            ) == .membership
        )
        #expect(
            RewardCenterSpecialOfferDestination.resolve(
                isSubscribed: false,
                isActive: true,
                hasMembershipOffer: false
            ) == .hidden
        )
        #expect(
            RewardCenterSpecialOfferDestination.resolve(
                isSubscribed: true,
                isActive: false,
                hasMembershipOffer: true
            ) == .hidden
        )
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

    @MainActor
    @Test func privacyPolicyUsesProductionURL() {
        #expect(
            LegalDocument.privacyPolicy.url.absoluteString
                == "https://www.alihantakaz.site/PhotoRevival-Privacy-policy.html"
        )
    }

    @MainActor
    @Test func termsOfServiceUsesAppleStandardEULA() {
        #expect(
            LegalDocument.termsOfService.url.absoluteString
                == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )
    }

}

private actor CatalogFetchCounter {
    private(set) var count = 0

    func recordFailure() -> Data? {
        count += 1
        return nil
    }
}
