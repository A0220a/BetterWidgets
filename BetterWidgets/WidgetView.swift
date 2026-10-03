//
//  WidgetView.swift
//  BetterWidgets
//

import AppKit
import AVFoundation
import ImageIO
import SwiftUI

struct WidgetView: View {
    let model: WidgetModel
    let videoPlaybackController: VideoPlaybackController?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if model.mediaType == .video, let videoPlaybackController {
                VideoWidgetView(controller: videoPlaybackController)
            } else if model.mediaType == .video {
                Text("Unable to play video")
                    .foregroundStyle(.white)
            } else if model.mediaType == .gif {
                AnimatedGIFView(url: model.imageURL)
            } else if let image = NSImage(contentsOf: model.imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct VideoWidgetView: View {
    @ObservedObject var controller: VideoPlaybackController

    var body: some View {
        if let errorMessage = controller.playbackErrorMessage {
            Text(errorMessage)
                .foregroundStyle(.white)
        } else {
            VideoPlayerView(controller: controller)
        }
    }
}

private struct VideoPlayerView: NSViewRepresentable {
    let controller: VideoPlaybackController

    func makeNSView(context: Context) -> VideoPlayerContainerView {
        VideoPlayerContainerView(player: controller.player)
    }

    func updateNSView(_ nsView: VideoPlayerContainerView, context: Context) {
        nsView.player = controller.player
    }

    static func dismantleNSView(_ nsView: VideoPlayerContainerView, coordinator: ()) {
        nsView.player = nil
    }
}

private final class VideoPlayerContainerView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
        }
    }

    init(player: AVPlayer) {
        self.player = player
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    deinit {
        playerLayer.player = nil
    }
}

enum WidgetResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var isLeft: Bool {
        self == .topLeft || self == .bottomLeft
    }

    var isTop: Bool {
        self == .topLeft || self == .topRight
    }
}

private struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> GIFPlayerView {
        GIFPlayerView(url: url)
    }

    func updateNSView(_ nsView: GIFPlayerView, context: Context) {
        nsView.update(url: url)
    }

    static func dismantleNSView(_ nsView: GIFPlayerView, coordinator: ()) {
        nsView.stop()
    }
}

private final class GIFPlayerView: NSView {
    private var source: CGImageSource?
    private var frameIndex = 0
    private var timer: Timer?
    private(set) var url: URL

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
        loadGIF()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(url: URL) {
        guard self.url != url else { return }
        self.url = url
        loadGIF()
    }

    deinit {
        timer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stop()
        } else {
            // A representable can load its first frame before joining a window.
            // Start the animation only after it is attached.
            loadGIF()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source = nil
        layer?.contents = nil
    }

    private func loadGIF() {
        // A failed replacement must not leave the previous file's frame visible.
        stop()
        frameIndex = 0
        source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        displayCurrentFrame()
    }

    private func displayCurrentFrame() {
        guard let source else { return }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0, let image = CGImageSourceCreateImageAtIndex(source, frameIndex, [kCGImageSourceShouldCache: false] as CFDictionary) else { return }

        layer?.contents = image
        guard frameCount > 1, window != nil else { return }
        let delay = frameDelay(in: source, at: frameIndex)
        frameIndex = (frameIndex + 1) % frameCount

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.displayCurrentFrame()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func frameDelay(in source: CGImageSource, at index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let delay = unclampedDelay ?? (gifProperties[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return max(delay, 0.02)
    }
}
