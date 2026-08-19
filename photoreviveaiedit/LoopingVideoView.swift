import AVFoundation
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
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var currentResourceName: String?
    private var currentURL: URL?

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = videoGravity }
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
        configurePlayer(url: url)
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
        player.play()
    }

    func play() {
        queuePlayer?.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLayer.player = nil
        playerLooper = nil
        queuePlayer = nil
        currentResourceName = nil
        currentURL = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? queuePlayer?.pause() : queuePlayer?.play()
    }
}
