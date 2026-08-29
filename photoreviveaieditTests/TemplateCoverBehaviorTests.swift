import Foundation
import Testing
@testable import photoreviveaiedit

@MainActor
struct TemplateCoverBehaviorTests {
    @Test func onlyProcessedPreviewVideosArePersistedDuringAutoplay() throws {
        let optimized = try #require(URL(string:
            "https://example.supabase.co/storage/v1/object/public/cms/apps/photorevival/optimized-previews/v2/item/preview.mp4"
        ))
        let sourceUpload = try #require(URL(string:
            "https://example.supabase.co/storage/v1/object/public/cms/apps/photorevival/files/source-video.mp4"
        ))

        #expect(LoopingPlayerUIView.shouldPersistRemoteVideo(at: optimized))
        #expect(!LoopingPlayerUIView.shouldPersistRemoteVideo(at: sourceUpload))
    }

    @Test func fixedFeatureDestinationReusesQuickActionCoverItem() throws {
        let posterURL = try #require(URL(string: "https://example.com/restore.jpg"))
        let videoURL = try #require(URL(string: "https://example.com/restore.mp4"))
        let coverItem = TemplateItem(
            id: "cms-fixed-feature-restore",
            title: "One-Tap Restore",
            coverImageURL: posterURL,
            coverVideoURL: videoURL,
            orientation: .landscape
        )
        let action = HomeQuickAction(feature: .oneTapRestore, item: coverItem)

        let resolvedItem = try #require(
            FixedFeatureCoverResolver.item(for: .oneTapRestore, in: [action])
        )

        #expect(resolvedItem == coverItem)
        #expect(resolvedItem.coverImageURL == posterURL)
        #expect(resolvedItem.coverVideoURL == videoURL)
    }

    @Test func fixedFeatureDestinationKeepsBundledFallbackWithoutConfiguredMedia() {
        let emptyItem = TemplateItem(
            id: "local-fixed-restore",
            title: "One-Tap Restore",
            orientation: .landscape
        )
        let action = HomeQuickAction(feature: .oneTapRestore, item: emptyItem)

        #expect(FixedFeatureCoverResolver.item(for: .oneTapRestore, in: [action]) == nil)
    }
}
