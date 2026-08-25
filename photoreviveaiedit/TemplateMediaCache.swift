import CryptoKit
import Foundation
import UIKit

/// A process-wide memory cache plus an app-owned disk cache. The CMS image
/// endpoints currently return `no-cache`, so relying on URLCache alone causes
/// already-rendered covers to be fetched again after their SwiftUI view is
/// recreated.
final class TemplateImageMemoryCache: @unchecked Sendable {
    static let shared = TemplateImageMemoryCache()

    private let storage: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 160 * 1_024 * 1_024
        return cache
    }()

    private init() {}

    func image(for url: URL) -> UIImage? {
        storage.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        storage.setObject(image, forKey: url as NSURL, cost: width * height * 4)
    }
}

actor TemplateImageRepository {
    static let shared = TemplateImageRepository()

    private let session: URLSession
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

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

    func image(for url: URL) async throws -> UIImage {
        if let image = await TemplateImageMemoryCache.shared.image(for: url) {
            return image
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let session = session
        let task = Task(priority: .userInitiated) {
            try await Self.loadImage(for: url, using: session)
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            inFlight[url] = nil
            await TemplateImageMemoryCache.shared.insert(image, for: url)
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private static func loadImage(for originalURL: URL, using session: URLSession) async throws -> UIImage {
        let diskURL = cacheURL(for: originalURL)
        if let data = try? Data(contentsOf: diskURL, options: .mappedIfSafe),
           let image = UIImage(data: data) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: diskURL.path
            )
            return image
        }

        await TemplateMediaTransferGate.shared.acquire()
        do {
            let requestURL = optimizedRequestURL(for: originalURL)
            let loaded: (Data, UIImage)
            do {
                loaded = try await downloadImage(at: requestURL, using: session)
            } catch where requestURL != originalURL {
                // Image transformations may be disabled per Supabase project.
                // Falling back keeps the card functional in that deployment.
                loaded = try await downloadImage(at: originalURL, using: session)
            }

            await TemplateMediaTransferGate.shared.release()
            persist(loaded.0, at: diskURL)
            return loaded.1
        } catch {
            await TemplateMediaTransferGate.shared.release()
            throw error
        }
    }

    private static func downloadImage(at url: URL, using session: URLSession) async throws -> (Data, UIImage) {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 45
        )
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return (data, image)
    }

    /// Supabase's render endpoint transfers a card-sized version instead of a
    /// multi-megabyte original. The original URL remains the cache key, so all
    /// screens still share one rendered result.
    private static func optimizedRequestURL(for url: URL) -> URL {
        guard url.host?.hasSuffix(".supabase.co") == true,
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
            URLQueryItem(name: "width", value: "540"),
            URLQueryItem(name: "height", value: "960"),
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

    private static func cacheURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(digest).appendingPathExtension("image")
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemplateImageCache", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
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
