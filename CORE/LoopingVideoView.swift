import SwiftUI
import AVFoundation
import UIKit

struct LoopingVideoView: UIViewRepresentable {
    let filename: String
    let fileExtension: String

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(filename: filename, fileExtension: fileExtension)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.play()
    }
}

final class LoopingPlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(filename: String, fileExtension: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(Color.sdsSubtleSurface)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        configurePlayer(filename: filename, fileExtension: fileExtension)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func play() {
        player?.play()
    }

    private func configurePlayer(filename: String, fileExtension: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.play()

        playerLayer.player = queuePlayer
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
    }
}
