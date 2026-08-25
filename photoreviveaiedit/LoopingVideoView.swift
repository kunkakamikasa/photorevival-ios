import AVFoundation
import CryptoKit
import SwiftUI
import UIKit

struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var aspectFitBackgroundColor: UIColor = .black

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.videoGravity = videoGravity
        view.aspectFitBackgroundColor = aspectFitBackgroundColor
        view.configure(resourceName: resourceName)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.aspectFitBackgroundColor = aspectFitBackgroundColor
        uiView.play()
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: Void) {
        uiView.stop()
    }
}

struct RemoteLoopingVideoView: UIViewRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var aspectFitBackgroundColor: UIColor = .black

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.videoGravity = videoGravity
        view.aspectFitBackgroundColor = aspectFitBackgroundColor
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.aspectFitBackgroundColor = aspectFitBackgroundColor
        uiView.configure(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: Void) {
        uiView.stop()
    }
}

final class LoopingPlayerUIView: UIView {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var remoteVideoTask: Task<Void, Never>?
    private var currentResourceName: String?
    private var currentURL: URL?

    private let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        preparePlayerLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        preparePlayerLayer()
    }

    private func preparePlayerLayer() {
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        playerLayer.backgroundColor = UIColor.clear.cgColor
        layer.addSublayer(playerLayer)
    }

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            playerLayer.videoGravity = videoGravity
            updatePlayerBackground()
        }
    }

    var aspectFitBackgroundColor: UIColor = .black {
        didSet { updatePlayerBackground() }
    }

    private func updatePlayerBackground() {
        playerLayer.backgroundColor = videoGravity == .resizeAspect
            ? aspectFitBackgroundColor.cgColor
            : UIColor.clear.cgColor
    }

    func configure(resourceName: String) {
        guard currentResourceName != resourceName else {
            play()
            return
        }

        stop()
        currentResourceName = resourceName

        let bundledURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "mp4",
            subdirectory: "TemplateVideos"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "mp4")

        guard let url = bundledURL else { return }
        configurePlayer(url: url)
    }

    func configure(url: URL) {
        guard currentURL != url else {
            play()
            return
        }

        stop()
        currentURL = url
        if let cachedURL = TemplateVideoCache.cachedURL(for: url) {
            configurePlayer(url: cachedURL)
            return
        }

        // Download once, then play the local file. Previously AVPlayer streamed
        // the remote URL while a second task downloaded the same video for the
        // cache, doubling bandwidth exactly while image covers were loading.
        remoteVideoTask = Task { [weak self] in
            do {
                let localURL = try await TemplateVideoCache.shared.localURL(for: url)
                guard !Task.isCancelled, self?.currentURL == url else { return }
                self?.configurePlayer(url: localURL)
            } catch {
                guard !Task.isCancelled, self?.currentURL == url else { return }
                // If persistence is unavailable, retain streaming as a final
                // fallback so a transient disk error does not hide the preview.
                self?.configurePlayer(url: url)
            }
            self?.remoteVideoTask = nil
        }
    }

    private func configurePlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        queuePlayer = player
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
        playerLayer.isHidden = true
        readyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            self?.playerLayer.isHidden = !layer.isReadyForDisplay
        }
        player.play()
    }

    func play() {
        queuePlayer?.play()
    }

    func stop() {
        remoteVideoTask?.cancel()
        remoteVideoTask = nil
        queuePlayer?.pause()
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        playerLayer.isHidden = true
        playerLayer.player = nil
        playerLooper = nil
        queuePlayer = nil
        currentResourceName = nil
        currentURL = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? queuePlayer?.pause() : queuePlayer?.play()
    }
}

private actor TemplateVideoCache {
    static let shared = TemplateVideoCache()

    private var downloads: [URL: Task<URL, Error>] = [:]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        configuration.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: configuration)
    }()

    private init() {
        Task.detached(priority: .background) {
            Self.trimDiskCacheIfNeeded()
        }
    }

    static func cachedURL(for remoteURL: URL) -> URL? {
        let destinationURL = destinationURL(for: remoteURL)
        guard FileManager.default.fileExists(atPath: destinationURL.path) else { return nil }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    func localURL(for remoteURL: URL) async throws -> URL {
        if let cachedURL = Self.cachedURL(for: remoteURL) {
            return cachedURL
        }
        let destinationURL = Self.destinationURL(for: remoteURL)

        if let download = downloads[remoteURL] {
            return try await download.value
        }

        let download = Task.detached(priority: .utility) {
            await TemplateVideoTransferGate.shared.acquire()
            do {
                let (temporaryURL, response) = try await Self.session.download(from: remoteURL)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.removeItem(at: temporaryURL)
                } else {
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                }
                await TemplateVideoTransferGate.shared.release()
                return destinationURL
            } catch {
                await TemplateVideoTransferGate.shared.release()
                throw error
            }
        }
        downloads[remoteURL] = download

        do {
            let localURL = try await download.value
            downloads[remoteURL] = nil
            return localURL
        } catch {
            downloads[remoteURL] = nil
            throw error
        }
    }

    private static func destinationURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileExtension = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
        return cacheDirectory
            .appendingPathComponent(digest)
            .appendingPathExtension(fileExtension)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemplateVideoCache", isDirectory: true)
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
        let limit = 768 * 1_024 * 1_024
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limit else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) where total > limit * 3 / 4 {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// Catalog videos are substantially larger than their still covers. Bounded
/// downloading keeps a row of autoplay previews from starving every image on
/// the screen; completed files remain available through TemplateVideoCache.
private actor TemplateVideoTransferGate {
    static let shared = TemplateVideoTransferGate()

    private let limit = 2
    private var activeTransfers = 0
    private var waiters = [CheckedContinuation<Void, Never>]()

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
