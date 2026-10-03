//
//  VideoPlaybackController.swift
//  BetterWidgets
//

import AVFoundation
import Combine

final class VideoPlaybackController: ObservableObject {
    let player: AVQueuePlayer
    @Published private(set) var playbackErrorMessage: String?

    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var looperObservation: NSKeyValueObservation?
    private var isStopped = false

    init(url: URL, isMuted: Bool) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = isMuted
        looper = AVPlayerLooper(player: player, templateItem: item)

        looperObservation = looper?.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            let message = looper.error?.localizedDescription ?? "Unknown error"
            DispatchQueue.main.async { [weak self] in self?.reportFailure(message) }
        }
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            let currentItem = player.currentItem
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isStopped else { return }
                self.statusObservation?.invalidate()
                // The looper plays replicas; its template item never plays.
                self.statusObservation = currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Unknown error"
                    DispatchQueue.main.async { [weak self] in self?.reportFailure(message) }
                }
            }
        }

        player.play()
    }

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        looperObservation?.invalidate()
        looperObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    private func reportFailure(_ message: String) {
        guard !isStopped, playbackErrorMessage == nil else { return }
        playbackErrorMessage = "Unable to play video"
        print("BetterWidgets: unable to play video: \(message)")
    }

    deinit {
        stop()
    }
}
