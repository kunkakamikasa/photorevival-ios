import AVFoundation
import CryptoKit
import SwiftUI
import UIKit

struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.videoGravity = videoGravity
        view.configure(resourceName: resourceName)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.play()
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: Void) {
        uiView.stop()
    }
}

struct RemoteLoopingVideoView: UIViewRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.videoGravity = videoGravity
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.videoGravity = videoGravity
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
            playerLayer.backgroundColor = videoGravity == .resizeAspect
                ? UIColor.black.cgColor
                : UIColor.clear.cgColor
        }
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

        // Start playback immediately. The same URL is cached in the background
        // so opening Try Now can use the completed local file without another download.
        configurePlayer(url: url)
        remoteVideoTask = Task { [weak self] in
            do {
                _ = try await TemplateVideoCache.shared.localURL(for: url)
            } catch {
                // AVPlayer can continue streaming from the remote URL if caching fails.
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

    static func cachedURL(for remoteURL: URL) -> URL? {
        let destinationURL = destinationURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: destinationURL.path)
            ? destinationURL
            : nil
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
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
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
            return destinationURL
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
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemplateVideoCache", isDirectory: true)
            .appendingPathComponent(digest)
            .appendingPathExtension(fileExtension)
    }
}
