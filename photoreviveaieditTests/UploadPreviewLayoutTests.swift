import CoreGraphics
import Testing
@testable import photoreviveaiedit

struct UploadPreviewLayoutTests {
    @Test func previewFrameUsesStableFourByThreeRatio() {
        #expect(UploadPreviewLayout.aspectRatio == 4.0 / 3.0)
    }

    @Test func portraitPhotoUsesFullPreviewHeightAndKeepsItsRatio() {
        let size = UploadPreviewLayout.foregroundSize(
            for: CGSize(width: 900, height: 1_600),
            in: CGSize(width: 360, height: 270)
        )

        #expect(size.height == 270)
        #expect(size.width == 151.875)
    }

    @Test func widePhotoUsesFullPreviewHeightWithoutExpandingTheFrame() {
        let size = UploadPreviewLayout.foregroundSize(
            for: CGSize(width: 2_000, height: 1_000),
            in: CGSize(width: 360, height: 270)
        )

        #expect(size.height == 270)
        #expect(size.width == 540)
    }

    @Test func everyUploadPageLayoutFitsCompactPhoneHeights() {
        let viewportSizes = [
            CGSize(width: 320, height: 430),
            CGSize(width: 350, height: 520),
            CGSize(width: 390, height: 700),
        ]

        for viewportSize in viewportSizes {
            let photo = FixedPhotoUploadLayout(viewportSize: viewportSize)
            let video = FixedVideoUploadLayout(viewportSize: viewportSize)
            let template = ImageTemplateUploadLayout(viewportSize: viewportSize)
            let aiImage = FixedAIImageUploadLayout(
                viewportSize: viewportSize,
                showsTabs: true,
                includesUploads: true
            )
            let aiText = FixedAIImageUploadLayout(
                viewportSize: viewportSize,
                showsTabs: true,
                includesUploads: false
            )

            #expect(photo.occupiedHeight <= viewportSize.height + 0.001)
            #expect(video.occupiedHeight <= viewportSize.height + 0.001)
            #expect(template.occupiedHeight <= viewportSize.height + 0.001)
            #expect(aiImage.occupiedHeight <= viewportSize.height + 0.001)
            #expect(aiText.occupiedHeight <= viewportSize.height + 0.001)
        }
    }

    @Test func flexibleUploadRegionsShrinkTogetherToExactBudget() {
        let sizes = UploadPageFlexibleLayout.fittedSizes(
            availableHeight: 280,
            preferred: [302, 188],
            minimum: [140, 100]
        )

        #expect(sizes.count == 2)
        #expect(abs(sizes.reduce(0, +) - 280) < 0.001)
        #expect(sizes[0] > sizes[1])
        #expect(sizes.allSatisfy { $0 > 0 })
    }
}
