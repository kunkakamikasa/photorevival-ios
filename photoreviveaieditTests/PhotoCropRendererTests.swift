import Testing
import UIKit
@testable import photoreviveaiedit

@MainActor
struct PhotoCropRendererTests {
    @Test func cropAspectListIncludesBothVideoOrientations() {
        let labels = PhotoCropAspect.allCases.map(\.rawValue)

        #expect(labels.contains("9:16"))
        #expect(labels.contains("16:9"))
        #expect(labels.first == "ORIGINAL")
        #expect(labels.dropFirst().first == "FREEFORM")
    }

    @Test func portraitNineSixteenCropProducesRequestedAspect() throws {
        let source = solidImage(size: CGSize(width: 1600, height: 900))
        let cropped = try #require(
            PhotoCropRenderer.croppedImage(
                from: source,
                viewportSize: CGSize(width: 900, height: 1600),
                zoom: 1,
                offset: .zero
            )
        )

        #expect(abs(cropped.size.width / cropped.size.height - 9.0 / 16.0) < 0.01)
    }

    @Test func landscapeSixteenNineCropProducesRequestedAspect() throws {
        let source = solidImage(size: CGSize(width: 900, height: 1600))
        let cropped = try #require(
            PhotoCropRenderer.croppedImage(
                from: source,
                viewportSize: CGSize(width: 1600, height: 900),
                zoom: 1,
                offset: .zero
            )
        )

        #expect(abs(cropped.size.width / cropped.size.height - 16.0 / 9.0) < 0.01)
    }

    @Test func rotateClockwiseSwapsImageDimensions() {
        let source = solidImage(size: CGSize(width: 120, height: 80))
        let rotated = PhotoCropRenderer.rotatedClockwise(source)

        #expect(rotated.size.width == 80)
        #expect(rotated.size.height == 120)
    }

    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
