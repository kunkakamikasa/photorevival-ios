import Foundation
import Testing
@testable import photoreviveaiedit

@MainActor
struct VideoPromptDisplayTests {
    @Test func twoStageTemplateDisplaysItsCuratedVideoOnlyBrief() throws {
        let item = TemplateItem(
            id: "photorevival-classic-films-love-in-titanic",
            title: "Love in Titanic",
            promptTemplate: """
            Compose @Image1 and @Image2 into one cinematic couple portrait.

            VIDEO MOTION:
            The couple gently leans into the wind while the camera slowly pulls back.
            """
        )

        let displayedPrompt = try #require(item.displayedPromptTemplate)
        #expect(displayedPrompt.contains("iconic bow pose"))
        #expect(displayedPrompt.contains("front subject keeps both arms extended"))
        #expect(displayedPrompt.contains("light breeze through hair and fabric"))
        #expect(!displayedPrompt.contains("Compose @Image1"))
        #expect(!displayedPrompt.contains("The couple gently leans into the wind"))
    }

    @Test func singleStageTemplateReceivesItsOwnRelevantRewrite() throws {
        let canonicalPrompt = "The person is surfing joyfully on the sea."
        let item = TemplateItem(
            id: "photorevival-summer-beach-surfing",
            title: "Surfing",
            promptTemplate: canonicalPrompt
        )

        let displayedPrompt = try #require(item.displayedPromptTemplate)
        #expect(displayedPrompt.contains("rides a wave"))
        #expect(displayedPrompt.contains("surfing posture"))
        #expect(displayedPrompt != canonicalPrompt)
        #expect(!displayedPrompt.contains(canonicalPrompt))
    }

    @Test func unknownTemplateNeverFallsBackToExposingTheOriginalPrompt() {
        let prompt = "Compose both subjects.\n\nVIDEO MOTION:\n"
        let item = TemplateItem(
            id: "incomplete-two-stage-video",
            title: "Incomplete Two Stage",
            promptTemplate: prompt
        )

        #expect(item.displayedPromptTemplate == nil)
    }

    @Test func imageCompositionPromptIsNeverPreparedForVideoDisplay() {
        let item = TemplateItem(
            id: "image-composition",
            title: "Image Composition",
            generationKind: .image,
            promptTemplate: "Combine @Image1 and @Image2 into one portrait."
        )

        #expect(item.displayedPromptTemplate == nil)
    }

    @Test func untouchedDisplaySummaryNeverOverridesCanonicalServerPrompt() {
        let defaultPrompt = "Bring the \u{201C}Birthday\u{201D} scene to life with warm celebration details."

        #expect(
            VideoPromptSubmission.userOverride(
                displayedPrompt: defaultPrompt,
                defaultDisplayedPrompt: defaultPrompt,
                isEditable: true
            ) == nil
        )
        #expect(
            VideoPromptSubmission.userOverride(
                displayedPrompt: "Make the candlelight softer.",
                defaultDisplayedPrompt: defaultPrompt,
                isEditable: true
            ) == "Make the candlelight softer."
        )
        #expect(
            VideoPromptSubmission.userOverride(
                displayedPrompt: "Make the candlelight softer.",
                defaultDisplayedPrompt: defaultPrompt,
                isEditable: false
            ) == nil
        )
    }

    @Test func currentVideoCatalogHasARelevantBriefForEveryLiveTemplate() {
        #expect(VideoPromptDisplayCatalog.templateIDs.count == 118)
    }

    @Test func cmsTitlesNeverExposeHanCharacters() {
        let section = TemplateSection(
            "\u{8D85}\u{6A21}\u{8D70}\u{79C0}",
            id: "cms-section-6561",
            items: [
                TemplateItem(
                    id: "mixed-title",
                    title: "God-tier Live\u{5ACC}\u{7591}\u{72AF}"
                )
            ]
        )

        #expect(section.title == "Supermodel Runway")
        #expect(section.items.first?.title == "God-tier Live")
        #expect(!EnglishDisplayText.hasHanCharacters(section.title))
        #expect(section.items.allSatisfy { !EnglishDisplayText.hasHanCharacters($0.title) })
    }

    @Test func cmsPromptWithHanCharactersIsNotDisplayed() {
        let item = TemplateItem(
            id: "configured-prompt",
            title: "Configured Prompt",
            promptTemplate: "VIDEO MOTION:\n\u{65E0}"
        )

        #expect(item.displayedPromptTemplate == nil)
        #expect(item.promptTemplate != nil)
    }

    @Test func userFacingMessagesNeverExposeHanCharacters() {
        let fallback = "Image generation failed. Please try again."
        let providerMessage = "Seedream 4.5 \u{56FE}\u{751F}\u{56FE} \u{751F}\u{6210}\u{5931}\u{8D25}"

        #expect(
            EnglishDisplayText.userFacingMessage(providerMessage, fallback: fallback)
                == fallback
        )
        #expect(
            EnglishDisplayText.userFacingMessage(
                "The image service is temporarily unavailable.",
                fallback: fallback
            ) == "The image service is temporarily unavailable."
        )
        #expect(!EnglishDisplayText.hasHanCharacters(fallback))
    }

    @Test func apiAndAuthenticationErrorsUseEnglishFallbacks() {
        let serverMessage = "\u{670D}\u{52A1}\u{6682}\u{65F6}\u{4E0D}\u{53EF}\u{7528}"
        let apiError = PhotoReviveAPIError.requestFailed(
            statusCode: 500,
            message: serverMessage
        )
        let authError = PhotoReviveAuthError.requestFailed(
            statusCode: 500,
            message: serverMessage
        )

        #expect(apiError.errorDescription == "The request failed. Please try again.")
        #expect(authError.errorDescription == "Sign-in failed. Please try again.")
    }

    @Test func imageGenerationUsesProviderDefaultResolution() throws {
        let options = PhotoReviveImageGenerationOptions(
            resolution: PhotoReviveImageGenerationOptions.providerDefaultResolution,
            aspectRatio: "9:16",
            outputCount: 1
        )
        let data = try JSONEncoder().encode(options)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(PhotoReviveImageGenerationOptions.providerDefaultResolution == "2K")
        #expect(object["resolution"] as? String == "2K")
        #expect(object["aspect_ratio"] as? String == "9:16")
    }

    @Test func imageGenerationOmitsAspectRatioForUnverifiedModels() throws {
        let options = PhotoReviveImageGenerationOptions(
            resolution: PhotoReviveImageGenerationOptions.providerDefaultResolution,
            aspectRatio: nil,
            outputCount: 1
        )
        let data = try JSONEncoder().encode(options)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["aspect_ratio"] == nil)
    }
}
