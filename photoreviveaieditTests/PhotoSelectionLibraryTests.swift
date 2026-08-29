import Testing
@testable import photoreviveaiedit

struct PhotoSelectionLibraryTests {
    @Test func createdTabOnlyIncludesCompletedImageResults() {
        let completedImage = historyTask(
            id: "completed-image",
            status: "completed",
            outputURL: "https://example.com/photo.jpg",
            contentType: "image"
        )
        let completedVideo = historyTask(
            id: "completed-video",
            status: "completed",
            outputURL: "https://example.com/video.mp4",
            contentType: "video"
        )
        let failedImage = historyTask(
            id: "failed-image",
            status: "failed",
            outputURL: "https://example.com/failed.jpg",
            contentType: "image"
        )
        let missingResult = historyTask(
            id: "missing-result",
            status: "completed",
            outputURL: nil,
            contentType: "image"
        )

        let result = PhotoSelectionLibrary.createdPhotoTasks(
            from: [completedImage, completedVideo, failedImage, missingResult]
        )

        #expect(result.map(\.id) == ["completed-image"])
    }

    private func historyTask(
        id: String,
        status: String,
        outputURL: String?,
        contentType: String
    ) -> GenerationHistoryTask {
        GenerationHistoryTask(
            id: id,
            scene: "test",
            status: status,
            outputURL: outputURL,
            convertedURL: nil,
            thumbnailURL: nil,
            thumbnailSource: nil,
            creditsUsed: 1,
            createdAt: "2026-08-29T00:00:00Z",
            contentType: contentType,
            sectionMenu: contentType,
            errorMessage: nil
        )
    }
}
