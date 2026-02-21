#if os(macOS)
import AVFoundation
import AppKit
import SwiftUI

struct WorkspacePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> WorkspacePlayerNSView {
        let view = WorkspacePlayerNSView()
        view.setPlayer(player)
        return view
    }

    func updateNSView(_ nsView: WorkspacePlayerNSView, context: Context) {
        nsView.setPlayer(player)
    }
}

final class WorkspacePlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func setPlayer(_ player: AVPlayer) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }
}
#endif
