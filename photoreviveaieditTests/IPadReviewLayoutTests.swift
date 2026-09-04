import CoreGraphics
import Testing
@testable import photoreviveaiedit

struct IPadReviewLayoutTests {
    @Test func portraitCompatibilityWindowKeepsPaywallActionOnScreen() {
        let viewport = CGSize(width: 430, height: 766)
        let contentHeight: CGFloat = 875
        let scale = PaywallLayoutPolicy.scale(
            containerSize: viewport,
            designWidth: 430,
            contentHeight: contentHeight
        )

        #expect(contentHeight * scale <= viewport.height)
        #expect(64 * scale >= 44)
    }

    @Test func nativeIPadDoesNotEnlargePhoneDesignedPaywall() {
        let scale = PaywallLayoutPolicy.scale(
            containerSize: CGSize(width: 820, height: 1180),
            designWidth: 430,
            contentHeight: 875
        )

        #expect(scale == 1)
    }

    @Test func shortLandscapeWindowKeepsControlsReadableAndScrollable() {
        let scale = PaywallLayoutPolicy.scale(
            containerSize: CGSize(width: 932, height: 430),
            designWidth: 430,
            contentHeight: 875
        )

        #expect(scale == PaywallLayoutPolicy.minimumReadableScale)
        #expect(64 * scale >= 44)
    }

    @Test func portraitMembershipReservesRoomBelowLegalLinks() {
        let fullHeight: CGFloat = 852
        let bottomClearance: CGFloat = 34
        let contentHeight: CGFloat = 932
        let scale = PaywallLayoutPolicy.scale(
            containerSize: CGSize(width: 430, height: fullHeight - bottomClearance),
            designWidth: 430,
            contentHeight: contentHeight
        )

        #expect(contentHeight * scale + bottomClearance <= fullHeight)
        #expect(64 * scale >= 44)
    }

    @Test func returningOfferFitsTheCompleteCanvasInPortraitCompatibilityMode() {
        let layout = ReturningOfferCanvasLayout(
            source: CGSize(width: 430, height: 932),
            destination: CGSize(width: 430, height: 766)
        )

        #expect(abs(layout.scale - (766.0 / 932.0)) < 0.001)
        #expect(abs(layout.origin.y) < 0.001)
        #expect(layout.point(CGPoint(x: 215, y: 890)).y <= 766)
    }

    @Test func returningOfferUsesVerticalScrollingInsteadOfTinyLandscapeControls() {
        let layout = ReturningOfferCanvasLayout(
            source: CGSize(width: 430, height: 932),
            destination: CGSize(width: 932, height: 430)
        )

        #expect(layout.scale == 1)
        #expect(layout.contentHeight == 932)
        #expect(58 * layout.scale >= 44)
    }

    @Test func homePromotionIsBoundedInWideAndShortWindows() {
        let portraitWidth = HomeOverlayLayoutPolicy.bannerWidth(
            in: CGSize(width: 820, height: 1180)
        )
        let landscapeWidth = HomeOverlayLayoutPolicy.bannerWidth(
            in: CGSize(width: 932, height: 430)
        )

        #expect(portraitWidth == HomeOverlayLayoutPolicy.maximumBannerWidth)
        #expect(landscapeWidth / 3 <= 430 * 0.25)
    }
}
