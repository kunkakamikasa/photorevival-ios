import AVFoundation
import AVKit
import CryptoKit
import SwiftUI
import UIKit

/// Generated output is user content, so it must never wait behind the decoder
/// budget used by the auto-playing template catalog. AVPlayerViewController also
/// gives the result a familiar play/pause scrubber and audio playback controls.
struct GeneratedVideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var autoplay = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = videoGravity
        controller.view.backgroundColor = .black
        context.coordinator.configure(
            controller: controller,
            url: url,
            autoplay: autoplay
        )
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        controller.videoGravity = videoGravity
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.configure(
            controller: controller,
            url: url,
            autoplay: autoplay
        )
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        coordinator.stop(controller: controller)
    }

    final class Coordinator {
        private(set) var currentURL: URL?
        private var playbackEndedObserver: NSObjectProtocol?
        private var timeControlObservation: NSKeyValueObservation?
        private weak var player: AVPlayer?
        private weak var playButton: UIButton?

        func configure(
            controller: AVPlayerViewController,
            url: URL,
            autoplay: Bool
        ) {
            stop(controller: controller)

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            player.preventsDisplaySleepDuringVideoPlayback = false
            controller.player = player
            self.player = player
            currentURL = url
            installPlayButtonIfNeeded(in: controller)

            timeControlObservation = player.observe(
                \.timeControlStatus,
                options: [.initial, .new]
            ) { [weak self] player, _ in
                DispatchQueue.main.async {
                    self?.playButton?.isHidden = player.timeControlStatus == .playing
                }
            }

            playbackEndedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }

            if autoplay {
                player.play()
            }
        }

        private func installPlayButtonIfNeeded(in controller: AVPlayerViewController) {
            guard playButton == nil, let overlay = controller.contentOverlayView else { return }

            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(UIImage(systemName: "play.fill"), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.58)
            button.layer.cornerRadius = 29
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
            button.accessibilityLabel = "Play generated video"
            button.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
            overlay.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 58),
                button.heightAnchor.constraint(equalToConstant: 58),
            ])
            playButton = button
        }

        @objc private func togglePlayback() {
            guard let player else { return }
            if player.timeControlStatus == .playing {
                player.pause()
            } else {
                player.play()
            }
        }

        func stop(controller: AVPlayerViewController) {
            if let playbackEndedObserver {
                NotificationCenter.default.removeObserver(playbackEndedObserver)
                self.playbackEndedObserver = nil
            }
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            controller.player?.pause()
            controller.player?.replaceCurrentItem(with: nil)
            controller.player = nil
            player = nil
            playButton?.isHidden = false
            currentURL = nil
        }

        deinit {
            timeControlObservation?.invalidate()
            if let playbackEndedObserver {
                NotificationCenter.default.removeObserver(playbackEndedObserver)
            }
        }
    }
}

struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var aspectFitBackgroundColor: UIColor = .black
    var videoAspectRatio: CGFloat? = nil
    var preservesPlaybackWhenInactive = false
    var onReadyForDisplay: (() -> Void)? = nil

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.videoGravity = videoGravity
        view.aspectFitBackgroundColor = aspectFitBackgroundColor
        view.videoAspectRatio = videoAspectRatio
        view.preservesPlaybackWhenInactive = preservesPlaybackWhenInactive
        view.onReadyForDisplay = onReadyForDisplay
        view.configure(resourceName: resourceName)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.aspectFitBackgroundColor = aspectFitBackgroundColor
        uiView.videoAspectRatio = videoAspectRatio
        uiView.preservesPlaybackWhenInactive = preservesPlaybackWhenInactive
        uiView.onReadyForDisplay = onReadyForDisplay
        uiView.refreshPlaybackState()
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
    private var playbackRequestTask: Task<Void, Never>?
    private var playbackPermitID: UUID?
    private var hasPlaybackPermit = false
    private var currentResourceName: String?
    private var currentURL: URL?
    private var playbackURL: URL?

    private let playerLayer = AVPlayerLayer()

    var preservesPlaybackWhenInactive = false
    var onReadyForDisplay: (() -> Void)?

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillStopBeingActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
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

    /// When supplied, the player layer fits this source ratio without cropping
    /// and pins the visible video to the top of the view.
    var videoAspectRatio: CGFloat? {
        didSet { setNeedsLayout() }
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
        playbackURL = url
        refreshPlaybackState()
    }

    func configure(url: URL) {
        guard currentURL != url else {
            refreshPlaybackState()
            return
        }

        stop()
        currentURL = url
        if let cachedURL = TemplateVideoCache.cachedURL(for: url) {
            TemplateMediaMetrics.shared.record(.disk, media: .video)
            playbackURL = cachedURL
            refreshPlaybackState()
            return
        }

        // Start visible playback from the remote asset. A cache copy is considered
        // only after the first frame has remained visible; starting a second full
        // transfer here would make every briefly-created scroll card compete with
        // the video the user is actually watching.
        TemplateMediaMetrics.shared.record(.network, media: .video)
        playbackURL = url
        refreshPlaybackState()
    }

    func refreshPlaybackState() {
        if preservesPlaybackWhenInactive, isTemporarilyInactiveButVisible {
            // ATT and first-network system sheets make the scene inactive. Keep
            // the configured player/layer intact so its current launch-video
            // frame remains visible (and can keep animating when iOS permits).
            return
        }

        guard isEligibleForPlayback else {
            suspendPlayback()
            return
        }

        if let queuePlayer {
            playerLayer.isHidden = !playerLayer.isReadyForDisplay
            queuePlayer.play()
            return
        }

        guard playbackRequestTask == nil, let playbackURL else { return }
        let permitID = UUID()
        playbackPermitID = permitID
        playbackRequestTask = Task { [weak self] in
            let acquired = await TemplatePlaybackGate.shared.acquire(id: permitID)
            guard acquired else { return }
            guard !Task.isCancelled,
                  let self,
                  self.playbackPermitID == permitID,
                  self.playbackURL == playbackURL,
                  self.isEligibleForPlayback else {
                await TemplatePlaybackGate.shared.release()
                return
            }

            self.hasPlaybackPermit = true
            self.playbackRequestTask = nil
            self.configurePlayer(url: playbackURL)
        }
    }

    private func configurePlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        // These are muted, looping previews rather than long-form playback.
        // Prefer a quick first frame over building a large startup buffer while
        // several cards share the same screen.
        item.preferredForwardBufferDuration = 0.5
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer = player
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
        playerLayer.isHidden = true
        readyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            self?.playerLayer.isHidden = !layer.isReadyForDisplay
            if layer.isReadyForDisplay {
                DispatchQueue.main.async { [weak self] in
                    self?.onReadyForDisplay?()
                }
            }
            // Bundled launch/onboarding videos use the same player view but are
            // not part of Home media performance.
            if layer.isReadyForDisplay, let remoteURL = self?.currentURL {
                TemplateMediaMetrics.shared.markVideoFrameDisplayed()
                self?.scheduleVideoPersistence(for: remoteURL)
            }
        }
        if isEligibleForPlayback {
            player.play()
        }
    }

    func play() {
        refreshPlaybackState()
    }

    func stop() {
        remoteVideoTask?.cancel()
        remoteVideoTask = nil
        suspendPlayback()
        currentResourceName = nil
        currentURL = nil
        playbackURL = nil
    }

    private func suspendPlayback() {
        remoteVideoTask?.cancel()
        remoteVideoTask = nil
        playbackRequestTask?.cancel()
        playbackRequestTask = nil
        playbackPermitID = nil
        releasePlaybackPermit()

        queuePlayer?.pause()
        readyForDisplayObservation?.invalidate()
        readyForDisplayObservation = nil
        playerLayer.isHidden = true
        playerLayer.player = nil
        playerLooper = nil
        queuePlayer?.removeAllItems()
        queuePlayer = nil
    }

    /// Only optimized preview files are small enough to duplicate into the
    /// app-owned cache while the same asset is already streaming through
    /// AVPlayer. CMS source uploads can exceed 10 MB for a five-second card and
    /// must first be processed by the preview pipeline instead.
    static func shouldPersistRemoteVideo(at url: URL) -> Bool {
        url.path.contains("/optimized-previews/")
    }

    private func scheduleVideoPersistence(for remoteURL: URL) {
        guard currentURL == remoteURL,
              remoteVideoTask == nil,
              Self.shouldPersistRemoteVideo(at: remoteURL),
              TemplateVideoCache.cachedURL(for: remoteURL) == nil else {
            return
        }

        remoteVideoTask = Task { [weak self] in
            defer {
                if self?.currentURL == remoteURL {
                    self?.remoteVideoTask = nil
                }
            }
            do {
                // Fast scrolling should never start a complete duplicate
                // download. Cache only a preview the user actually watches.
                try await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.currentURL == remoteURL,
                      self.isEligibleForPlayback else {
                    return
                }
                _ = try await TemplateVideoCache.shared.localURL(for: remoteURL)
            } catch {
                // Streaming remains available if persistence is cancelled or
                // the optional cache write fails.
            }
        }
    }

    private func releasePlaybackPermit() {
        guard hasPlaybackPermit else { return }
        hasPlaybackPermit = false
        Task { await TemplatePlaybackGate.shared.release() }
    }

    private var isEligibleForPlayback: Bool {
        guard let window,
              isVisiblyPresented(in: window) else {
            return false
        }
        if let windowScene = window.windowScene {
            return windowScene.activationState == .foregroundActive
        }
        return UIApplication.shared.applicationState == .active
    }

    private var isTemporarilyInactiveButVisible: Bool {
        // A system permission sheet can appear as the window's frontmost
        // presentation, so the launch player is intentionally no longer a
        // descendant of that frontmost controller. Scene state is the reliable
        // signal here; requiring frontmost ancestry would tear down the exact
        // background frame the sheet is meant to cover.
        guard let window,
              bounds.width > 0,
              bounds.height > 0 else {
            return false
        }
        if let windowScene = window.windowScene {
            return windowScene.activationState == .foregroundInactive
        }
        return UIApplication.shared.applicationState == .inactive
    }

    private func isVisiblyPresented(in window: UIWindow) -> Bool {
        bounds.width > 0
            && bounds.height > 0
            && visibleFraction(in: window) >= 0.15
            && isInsideFrontmostPresentation(in: window)
    }

    /// A full-screen SwiftUI presentation keeps the covered view hierarchy
    /// attached to the same window. Geometry alone therefore reports Home and
    /// detail previews as visible even while a newer Try Now screen completely
    /// covers them. Only the frontmost presentation may retain decoder permits.
    private func isInsideFrontmostPresentation(in window: UIWindow) -> Bool {
        guard let rootViewController = window.rootViewController else { return true }

        var frontmostViewController = rootViewController
        while let presentedViewController = frontmostViewController.presentedViewController,
              !presentedViewController.isBeingDismissed {
            frontmostViewController = presentedViewController
        }

        guard frontmostViewController !== rootViewController else { return true }
        return isDescendant(of: frontmostViewController.view)
    }

    /// SwiftUI keeps nearby horizontal and vertical scroll items attached to the
    /// window after they leave the viewport. `window != nil` therefore is not a
    /// useful visibility test: an off-screen preview could hold a decoder permit
    /// forever and leave a visible Home shortcut on its poster.
    private func visibleFraction(in window: UIWindow) -> CGFloat {
        var visibleRect = convert(bounds, to: window).intersection(window.bounds)
        guard !visibleRect.isNull, !visibleRect.isEmpty else { return 0 }

        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { return 0 }

            if view !== self, view.clipsToBounds || view is UIScrollView {
                let clippingRect = view.convert(view.bounds, to: window)
                visibleRect = visibleRect.intersection(clippingRect)
                guard !visibleRect.isNull, !visibleRect.isEmpty else { return 0 }
            }
            ancestor = view.superview
        }

        let totalArea = bounds.width * bounds.height
        let visibleArea = visibleRect.width * visibleRect.height
        return totalArea > 0 ? visibleArea / totalArea : 0
    }

    @objc private func applicationDidBecomeActive() {
        refreshPlaybackState()
    }

    @objc private func applicationWillStopBeingActive() {
        if preservesPlaybackWhenInactive {
            // iOS can clear AVPlayerLayer's drawable while a system permission
            // sheet owns the foreground. Reveal the poster extracted from the
            // same launch video instead of exposing the black player surface.
            playerLayer.isHidden = true
            return
        }
        suspendPlayback()
    }

    @objc private func applicationDidEnterBackground() {
        suspendPlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = fittedVideoFrame
        CATransaction.commit()
    }

    private var fittedVideoFrame: CGRect {
        guard let videoAspectRatio,
              videoAspectRatio > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let availableAspectRatio = bounds.width / bounds.height
        if videoAspectRatio >= availableAspectRatio {
            return CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: bounds.width / videoAspectRatio
            )
        }

        let fittedWidth = bounds.height * videoAspectRatio
        return CGRect(
            x: (bounds.width - fittedWidth) / 2,
            y: 0,
            width: fittedWidth,
            height: bounds.height
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            TemplatePlaybackVisibilityMonitor.shared.unregister(self)
            suspendPlayback()
        } else {
            TemplatePlaybackVisibilityMonitor.shared.register(self)
            refreshPlaybackState()
        }
    }

    deinit {
        TemplatePlaybackVisibilityMonitor.shared.unregister(self)
        NotificationCenter.default.removeObserver(self)
        playbackRequestTask?.cancel()
        remoteVideoTask?.cancel()
        releasePlaybackPermit()
        queuePlayer?.pause()
        readyForDisplayObservation?.invalidate()
        playerLayer.player = nil
        playerLooper = nil
        queuePlayer?.removeAllItems()
        queuePlayer = nil
    }
}

/// A single low-frequency display link rechecks every attached preview while a
/// scroll view moves. UIKit does not call `didMoveToWindow` when an attached
/// child merely crosses a scroll viewport, so lifecycle callbacks alone cannot
/// release decoder permits from off-screen cards.
private final class TemplatePlaybackVisibilityMonitor {
    static let shared = TemplatePlaybackVisibilityMonitor()

    private let views = NSHashTable<LoopingPlayerUIView>.weakObjects()
    private var displayLink: CADisplayLink?

    private init() {}

    func register(_ view: LoopingPlayerUIView) {
        views.add(view)
        guard displayLink == nil else { return }

        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(refreshPlaybackStates)
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 2,
            maximum: 4,
            preferred: 4
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func unregister(_ view: LoopingPlayerUIView) {
        views.remove(view)
        stopIfEmpty()
    }

    @objc private func refreshPlaybackStates() {
        let attachedViews = views.allObjects.filter { $0.window != nil }
        for view in attachedViews {
            view.refreshPlaybackState()
        }
        stopIfEmpty(attachedViews: attachedViews)
    }

    private func stopIfEmpty(attachedViews: [LoopingPlayerUIView]? = nil) {
        let hasAttachedView = attachedViews.map { !$0.isEmpty }
            ?? views.allObjects.contains { $0.window != nil }
        guard !hasAttachedView else { return }

        displayLink?.invalidate()
        displayLink = nil
    }
}

/// Every AVPlayer consumes decoder and CoreMedia resources. Keep one shared
/// budget for bundled, cached, and streaming videos so a long scrolling session
/// cannot accumulate an unbounded number of active decoders.
private actor TemplatePlaybackGate {
    static let shared = TemplatePlaybackGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    // The Home viewport can legitimately contain one hero, three fixed-feature
    // previews, and three catalog cards at the same time. A budget of four made
    // later visible cards wait forever on their posters even though off-screen
    // players are now suspended by the visibility monitor.
    private let limit = 8
    private var activePlayers = 0
    private var waiters = [Waiter]()

    func acquire(id: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        if activePlayers < limit {
            activePlayers += 1
            return true
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            activePlayers = max(0, activePlayers - 1)
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
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
