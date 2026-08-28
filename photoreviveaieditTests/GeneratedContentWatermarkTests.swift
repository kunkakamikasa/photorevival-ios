import CoreGraphics
import Testing
@testable import photoreviveaiedit

struct GeneratedContentWatermarkTests {
    @Test func watermarkIsOnlyVisibleForFreeUsers() {
        #expect(GeneratedContentWatermarkPolicy.isVisible(isSubscribed: false))
        #expect(!GeneratedContentWatermarkPolicy.isVisible(isSubscribed: true))
    }

    @Test func watermarkPatternCoversPortraitAndLandscapeResults() {
        for size in [
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390)
        ] {
            let placements = GeneratedContentWatermarkLayout.placements(in: size)

            #expect(placements.count >= 15)
            #expect(placements.contains { $0.x < size.width * 0.25 })
            #expect(placements.contains { $0.x > size.width * 0.75 })
            #expect(placements.contains { $0.y < size.height * 0.25 })
            #expect(placements.contains { $0.y > size.height * 0.75 })
        }
    }

    @Test func watermarkLayoutRejectsEmptyMediaBounds() {
        #expect(GeneratedContentWatermarkLayout.placements(in: .zero).isEmpty)
    }
}
