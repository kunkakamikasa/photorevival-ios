import CryptoKit
import Foundation
import ImageIO
import os
import UIKit

/// Process-wide startup/cache counters. Firebase receives only four bounded
/// milestones per process and never receives a media URL.
nonisolated final class TemplateMediaMetrics: @unchecked Sendable {
    enum MediaKind { case image, video }
    enum CacheTier { case memory, disk, network }

    static let shared = TemplateMediaMetrics()

    private struct Snapshot {
        var catalogSource: String?
        var imageMemoryHits = 0
        var imageDiskHits = 0
        var imageNetworkLoads = 0
        var videoDiskHits = 0
        var videoNetworkLoads = 0
    }

    private let lock = NSLock()
    private let startedAt = ContinuousClock.now
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoRevival", category: "HomeMedia")
    private var snapshot = Snapshot()
    private var emittedMilestones = Set<String>()
    private var displayedPosterURLs = Set<URL>()

    private init() {}

    func record(_ tier: CacheTier, media: MediaKind) {
        lock.withLock {
            switch (media, tier) {
            case (.image, .memory): snapshot.imageMemoryHits += 1
            case (.image, .disk): snapshot.imageDiskHits += 1
            case (.image, .network): snapshot.imageNetworkLoads += 1
            case (.video, .disk): snapshot.videoDiskHits += 1
            case (.video, .network): snapshot.videoNetworkLoads += 1
            case (.video, .memory): break
            }
        }
    }

    func markCatalogAvailable(source: String) {
        lock.withLock {
            if snapshot.catalogSource == nil { snapshot.catalogSource = source }
        }
        emitOnce("catalog_ready")
    }

    func markPosterDisplayed(for url: URL) {
        let displayedCount = lock.withLock {
            displayedPosterURLs.insert(url)
            return displayedPosterURLs.count
        }
        if displayedCount == 1 {
            emitOnce("first_poster")
        }
        if displayedCount >= 9 {
            emitOnce("first_screen_posters_ready")
        }
    }

    func markVideoFrameDisplayed() {
        emitOnce("first_video_frame")
    }

    private func emitOnce(_ milestone: String) {
        let payload: (Snapshot, Int)? = lock.withLock {
            guard emittedMilestones.insert(milestone).inserted else { return nil }
            let elapsed = startedAt.duration(to: .now)
            let milliseconds = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            return (snapshot, max(0, milliseconds))
        }
        guard let (snapshot, elapsedMilliseconds) = payload else { return }

        logger.info("\(milestone, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) catalog=\(snapshot.catalogSource ?? "unknown", privacy: .public) image_memory=\(snapshot.imageMemoryHits, privacy: .public) image_disk=\(snapshot.imageDiskHits, privacy: .public) image_network=\(snapshot.imageNetworkLoads, privacy: .public) video_disk=\(snapshot.videoDiskHits, privacy: .public) video_network=\(snapshot.videoNetworkLoads, privacy: .public)")
        Task { @MainActor in
            AppAnalytics.homeMediaMilestone(
                milestone,
                elapsedMilliseconds: elapsedMilliseconds,
                catalogSource: snapshot.catalogSource,
                imageMemoryHits: snapshot.imageMemoryHits,
                imageDiskHits: snapshot.imageDiskHits,
                imageNetworkLoads: snapshot.imageNetworkLoads,
                videoDiskHits: snapshot.videoDiskHits,
                videoNetworkLoads: snapshot.videoNetworkLoads
            )
        }
    }
}

/// A process-wide memory cache plus an app-owned disk cache. The CMS image
/// endpoints currently return `no-cache`, so relying on URLCache alone causes
/// already-rendered covers to be fetched again after their SwiftUI view is
/// recreated.
final class TemplateImageMemoryCache: @unchecked Sendable {
    static let shared = TemplateImageMemoryCache()

    private let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 160 * 1_024 * 1_024
        return cache
    }()

    private init() {}

    func image(for url: URL, maxPixelSize: Int = 960) -> UIImage? {
        storage.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize))
    }

    func insert(_ image: UIImage, for url: URL, maxPixelSize: Int = 960) {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        let frameCount = max(image.images?.count ?? 1, 1)
        storage.setObject(
            image,
            forKey: cacheKey(for: url, maxPixelSize: maxPixelSize),
            cost: width * height * 4 * frameCount
        )
    }

    private func cacheKey(for url: URL, maxPixelSize: Int) -> NSString {
        "\(maxPixelSize)|\(url.absoluteString)" as NSString
    }
}

enum TemplateImageDecoder {
    /// ImageIO performs both decompression and display-size downsampling on the
    /// repository's worker task instead of making SwiftUI decode full originals
    /// while laying out a scrolling row.
    nonisolated static func image(from data: Data, maxPixelSize: Int = 960) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            guard let cgImage = thumbnail(at: 0, in: source, maxPixelSize: maxPixelSize) else {
                return UIImage(data: data)
            }
            return UIImage(cgImage: cgImage)
        }

        var frames = [UIImage]()
        var duration = 0.0
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            guard let cgImage = thumbnail(at: index, in: source, maxPixelSize: maxPixelSize) else {
                continue
            }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(at: index, in: source)
        }

        guard frames.count > 1 else { return frames.first ?? UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1 * Double(frames.count)))
    }

    private nonisolated static func thumbnail(
        at index: Int,
        in source: CGImageSource,
        maxPixelSize: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private nonisolated static func frameDuration(at index: Int, in source: CGImageSource) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

actor TemplateImageRepository {
    static let shared = TemplateImageRepository()

    private struct RequestKey: Hashable, Sendable {
        let url: URL
        let maxPixelSize: Int
    }

    private let session: URLSession
    private var inFlight: [RequestKey: Task<UIImage, Error>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024
        )
        session = URLSession(configuration: configuration)

        Task.detached(priority: .background) {
            Self.trimDiskCacheIfNeeded()
        }
    }

    func image(for url: URL, maxPixelSize: Int = 960) async throws -> UIImage {
        let key = RequestKey(url: url, maxPixelSize: maxPixelSize)
        if let image = await TemplateImageMemoryCache.shared.image(
            for: url,
            maxPixelSize: maxPixelSize
        ) {
            TemplateMediaMetrics.shared.record(.memory, media: .image)
            return image
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let session = session
        let task = Task(priority: .userInitiated) {
            try await Self.loadImage(for: url, maxPixelSize: maxPixelSize, using: session)
        }
        inFlight[key] = task

        do {
            let image = try await task.value
            inFlight[key] = nil
            await TemplateImageMemoryCache.shared.insert(
                image,
                for: url,
                maxPixelSize: maxPixelSize
            )
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private static func loadImage(
        for originalURL: URL,
        maxPixelSize: Int,
        using session: URLSession
    ) async throws -> UIImage {
        let diskURL = cacheURL(for: originalURL, maxPixelSize: maxPixelSize)
        if let data = try? Data(contentsOf: diskURL, options: .mappedIfSafe),
           let image = TemplateImageDecoder.image(from: data, maxPixelSize: maxPixelSize) {
            TemplateMediaMetrics.shared.record(.disk, media: .image)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: diskURL.path
            )
            return image
        }

        await TemplateMediaTransferGate.shared.acquire()
        do {
            let requestURL = optimizedRequestURL(for: originalURL, maxPixelSize: maxPixelSize)
            let loaded: (Data, UIImage)
            do {
                loaded = try await downloadImage(
                    at: requestURL,
                    maxPixelSize: maxPixelSize,
                    using: session
                )
            } catch where requestURL != originalURL {
                // Image transformations may be disabled per Supabase project.
                // Falling back keeps the card functional in that deployment.
                loaded = try await downloadImage(
                    at: originalURL,
                    maxPixelSize: maxPixelSize,
                    using: session
                )
            }

            await TemplateMediaTransferGate.shared.release()
            persist(loaded.0, at: diskURL)
            return loaded.1
        } catch {
            await TemplateMediaTransferGate.shared.release()
            throw error
        }
    }

    private static func downloadImage(
        at url: URL,
        maxPixelSize: Int,
        using session: URLSession
    ) async throws -> (Data, UIImage) {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 45
        )
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let image = TemplateImageDecoder.image(from: data, maxPixelSize: maxPixelSize) else {
            throw URLError(.cannotDecodeContentData)
        }
        TemplateMediaMetrics.shared.record(.network, media: .image)
        return (data, image)
    }

    /// Supabase's render endpoint transfers a card-sized version instead of a
    /// multi-megabyte original. The original URL remains the cache key, so all
    /// screens still share one rendered result.
    private static func optimizedRequestURL(for url: URL, maxPixelSize: Int) -> URL {
        guard url.pathExtension.lowercased() != "gif",
              url.host?.hasSuffix(".supabase.co") == true,
              url.path.contains("/storage/v1/object/public/") else {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = url.path.replacingOccurrences(
            of: "/storage/v1/object/public/",
            with: "/storage/v1/render/image/public/"
        )
        var queryItems = components?.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "width", value: String(maxPixelSize)),
            URLQueryItem(name: "height", value: String(maxPixelSize)),
            URLQueryItem(name: "resize", value: "contain"),
            URLQueryItem(name: "quality", value: "65")
        ])
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private static func persist(_ data: Data, at url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)
        } catch {
            // A cache write must never turn a successfully downloaded cover
            // into a UI failure.
        }
    }

    private static func cacheURL(for url: URL, maxPixelSize: Int) -> URL {
        let cacheIdentity = "\(maxPixelSize)|\(url.absoluteString)"
        let digest = SHA256.hash(data: Data(cacheIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("image")
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemplateImageCache", isDirectory: true)
            .appendingPathComponent("v3", isDirectory: true)
    }

    private static func trimDiskCacheIfNeeded() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        let limit = 384 * 1_024 * 1_024
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limit else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) where total > limit * 3 / 4 {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

actor TemplateMediaTransferGate {
    static let shared = TemplateMediaTransferGate(limit: 4)

    private let limit: Int
    private var activeTransfers = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if activeTransfers < limit {
            activeTransfers += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeTransfers = max(0, activeTransfers - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum TemplateMediaPreloader {
    static func prefetchImages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task(priority: .utility) {
            await TemplateMediaPreloadQueue.shared.enqueue(urls)
        }
    }
}

private actor TemplateMediaPreloadQueue {
    static let shared = TemplateMediaPreloadQueue()

    private var pending = [URL]()
    private var known = Set<URL>()
    private var isRunning = false

    func enqueue(_ urls: [URL]) async {
        for url in urls {
            guard await TemplateImageMemoryCache.shared.image(for: url) == nil else { continue }
            guard known.insert(url).inserted else { continue }
            pending.append(url)
        }
        guard !isRunning, !pending.isEmpty else { return }
        isRunning = true

        Task(priority: .utility) {
            await drain()
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let url = pending.removeFirst()
            _ = try? await TemplateImageRepository.shared.image(for: url)
        }
        isRunning = false
    }
}
