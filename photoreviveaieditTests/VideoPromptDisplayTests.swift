import Foundation
import Testing
@testable import photoreviveaiedit

@MainActor
struct VideoPromptDisplayTests {
    @Test func twoStageTemplateDisplaysOnlyVideoMotionPrompt() {
        let item = TemplateItem(
            id: "love-in-titanic",
            title: "Love in Titanic",
            promptTemplate: """
            Compose @Image1 and @Image2 into one cinematic couple portrait.

            VIDEO MOTION:
            The couple gently leans into the wind while the camera slowly pulls back.
            """
        )

        #expect(
            item.displayedPromptTemplate
                == "The couple gently leans into the wind while the camera slowly pulls back."
        )
    }

    @Test func singleStageTemplateKeepsItsOriginalPrompt() {
        let item = TemplateItem(
            id: "single-stage-video",
            title: "Single Stage",
            promptTemplate: "Preserve the subject while the camera slowly moves forward."
        )

        #expect(
            item.displayedPromptTemplate
                == "Preserve the subject while the camera slowly moves forward."
        )
    }

    @Test func emptySecondStageFallsBackToOriginalPrompt() {
        let prompt = "Compose both subjects.\n\nVIDEO MOTION:\n"
        let item = TemplateItem(
            id: "incomplete-two-stage-video",
            title: "Incomplete Two Stage",
            promptTemplate: prompt
        )

        #expect(item.displayedPromptTemplate == prompt)
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
    }
}
