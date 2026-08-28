import AVFoundation
import Photos
import SwiftUI
import UIKit

enum GeneratedMediaExportError: LocalizedError {
    case mediaUnavailable
    case photoAccessDenied
    case imageEncodingFailed
    case videoExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .mediaUnavailable:
            "The generated media is not available yet."
        case .photoAccessDenied:
            "Photo access is required to save this creation. You can enable it in Settings."
        case .imageEncodingFailed:
            "The generated image could not be prepared for export."
        case .videoExportFailed(let message):
            "The generated video could not be prepared: \(message)"
        }
    }
}

@MainActor
enum GeneratedMediaExporter {
    static func prepareImage(_ image: UIImage, addsWatermark: Bool) throws -> URL {
        let exportImage = addsWatermark ? watermarkedImage(image) : image
        guard let data = exportImage.jpegData(compressionQuality: 0.94) else {
            throw GeneratedMediaExportError.imageEncodingFailed
        }
        let url = temporaryURL(extension: "jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func prepareVideo(from sourceURL: URL, addsWatermark: Bool) async throws -> URL {
        let localURL = try await localVideoURL(from: sourceURL)
        guard addsWatermark else { return localURL }

        let asset = AVURLAsset(url: localURL)
        let composition = AVMutableVideoComposition(propertiesOf: asset)
        let renderSize = composition.renderSize
        guard renderSize.width > 0, renderSize.height > 0 else {
            throw GeneratedMediaExportError.videoExportFailed("invalid video size")
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let fontSize = min(max(min(renderSize.width, renderSize.height) * 0.04, 18), 52)
        for placement in GeneratedContentWatermarkLayout.placements(in: renderSize) {
            let layer = CATextLayer()
            layer.string = PhotoRevivalBrand.fullName
            layer.font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            layer.fontSize = fontSize
            layer.alignmentMode = .center
            layer.foregroundColor = UIColor.white.withAlphaComponent(0.26).cgColor
            layer.contentsScale = 2
            layer.bounds = CGRect(x: 0, y: 0, width: fontSize * 7.5, height: fontSize * 1.5)
            layer.position = placement
            layer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 9))
            parentLayer.addSublayer(layer)
        }

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw GeneratedMediaExportError.videoExportFailed("export session unavailable")
        }

        let outputURL = temporaryURL(extension: "mp4")
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = composition
        try await exporter.export(to: outputURL, as: .mp4)
        return outputURL
    }

    static func saveImage(at fileURL: URL) async throws {
        try await requirePhotoAddPermission()
        try await performPhotoLibraryChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }

    static func saveVideo(at fileURL: URL) async throws {
        try await requirePhotoAddPermission()
        try await performPhotoLibraryChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }

    private static func localVideoURL(from sourceURL: URL) async throws -> URL {
        guard !sourceURL.isFileURL else { return sourceURL }
        let (downloadURL, response) = try await URLSession.shared.download(from: sourceURL)
        let responseExtension = response.suggestedFilename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let outputURL = temporaryURL(extension: responseExtension ?? "mp4")
        try FileManager.default.moveItem(at: downloadURL, to: outputURL)
        return outputURL
    }

    private static func requirePhotoAddPermission() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            : current
        guard status == .authorized || status == .limited else {
            throw GeneratedMediaExportError.photoAccessDenied
        }
    }

    private static func performPhotoLibraryChanges(
        _ changes: @escaping () -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GeneratedMediaExportError.mediaUnavailable)
                }
            }
        }
    }

    private static func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-revival-export-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func watermarkedImage(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let fontSize = min(max(min(image.size.width, image.size.height) * 0.04, 14), 42)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.26),
                .strokeColor: UIColor.black.withAlphaComponent(0.20),
                .strokeWidth: -1
            ]
            let text = PhotoRevivalBrand.fullName as NSString
            let textSize = text.size(withAttributes: attributes)
            for placement in GeneratedContentWatermarkLayout.placements(in: image.size) {
                let context = UIGraphicsGetCurrentContext()
                context?.saveGState()
                context?.translateBy(x: placement.x, y: placement.y)
                context?.rotate(by: -.pi / 9)
                text.draw(
                    at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                    withAttributes: attributes
                )
                context?.restoreGState()
            }
        }
    }
}

struct GeneratedMediaActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
