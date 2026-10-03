//
//  WidgetThumbnailView.swift
//  BetterWidgets
//

import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing
import SwiftUI

/// A static, cached card preview. Quick Look composites animated-image frames
/// and videos use one generated video frame, so the main-window list never
/// starts media playback.
struct WidgetThumbnailView: NSViewRepresentable {
    private let identifier: String
    private let url: URL
    private let mediaType: WidgetMediaType

    init(model: WidgetModel) {
        identifier = model.id.uuidString
        url = model.imageURL
        mediaType = model.mediaType
    }

    init(item: MediaItem) {
        identifier = item.id
        url = item.url
        mediaType = item.mediaType
    }

    func makeNSView(context: Context) -> ThumbnailImageView {
        ThumbnailImageView(identifier: identifier, url: url, mediaType: mediaType)
    }

    func updateNSView(_ nsView: ThumbnailImageView, context: Context) {
        nsView.update(identifier: identifier, url: url, mediaType: mediaType)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThumbnailImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 132, height: proposal.height ?? 92)
    }
}

final class ThumbnailImageView: NSView {
    private let imageView = NSImageView()
    private let placeholder = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage())
    private var representedIdentifier: String?
    private var representedURL: URL?
    private var representedMediaType: WidgetMediaType?
    private var representedCacheKey: NSString?
    private var isLoading = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    init(identifier: String, url: URL, mediaType: WidgetMediaType) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        placeholder.imageScaling = .scaleProportionallyUpOrDown
        placeholder.contentTintColor = .secondaryLabelColor

        [imageView, placeholder].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
            NSLayoutConstraint.activate([
                $0.leadingAnchor.constraint(equalTo: leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: trailingAnchor),
                $0.topAnchor.constraint(equalTo: topAnchor),
                $0.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        update(identifier: identifier, url: url, mediaType: mediaType)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(identifier: String, url: URL, mediaType: WidgetMediaType) {
        let cacheKey = ThumbnailCache.cacheKey(for: url, mediaType: mediaType)
        guard representedIdentifier != identifier
                || representedURL != url
                || representedMediaType != mediaType
                || representedCacheKey != cacheKey
                || (imageView.image == nil && !isLoading) else { return }

        representedIdentifier = identifier
        representedURL = url
        representedMediaType = mediaType
        representedCacheKey = cacheKey
        isLoading = true
        imageView.image = nil
        placeholder.isHidden = false

        ThumbnailCache.shared.image(for: url, mediaType: mediaType) { [weak self] image in
            guard let self,
                  self.representedIdentifier == identifier,
                  self.representedURL == url,
                  self.representedMediaType == mediaType,
                  self.representedCacheKey == cacheKey else { return }
            self.isLoading = false
            self.imageView.image = image
            self.placeholder.isHidden = image != nil
        }
    }
}

nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    typealias Renderer = (URL, WidgetMediaType, @escaping (NSImage?) -> Void) -> Void

    private struct Request: Sendable {
        let key: String
        let url: URL
        let mediaType: WidgetMediaType
    }

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "BetterWidgets.thumbnail", qos: .userInitiated)
    private let lock = NSLock()
    private let renderer: Renderer?
    private var pending: [NSString: [(NSImage?) -> Void]] = [:]
    private var waiting: [Request] = []
    private var activeRequests = 0

    init(renderer: Renderer? = nil) {
        self.renderer = renderer
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for url: URL, mediaType: WidgetMediaType, completion: @escaping (NSImage?) -> Void) {
        let key = Self.cacheKey(for: url, mediaType: mediaType)
        lock.lock()
        if let cachedImage = cache.object(forKey: key) {
            lock.unlock()
            DispatchQueue.main.async { completion(cachedImage) }
            return
        }
        if pending[key] != nil {
            pending[key]?.append(completion)
        } else {
            pending[key] = [completion]
            waiting.append(Request(key: key as String, url: url, mediaType: mediaType))
        }
        let requests = takeRequests()
        lock.unlock()
        requests.forEach(generate)
    }

    // Called while holding the lock. Bound asynchronous Quick Look/video work,
    // not just the queue that starts it.
    private func takeRequests() -> [Request] {
        var requests: [Request] = []
        while activeRequests < 2, !waiting.isEmpty {
            requests.append(waiting.removeFirst())
            activeRequests += 1
        }
        return requests
    }

    private func generate(_ request: Request) {
        queue.async { [weak self] in
            guard let self else { return }
            let finish: (NSImage?) -> Void = { [weak self] image in
                self?.finish(request, image: image)
            }
            if let renderer = self.renderer {
                renderer(request.url, request.mediaType, finish)
            } else if request.mediaType == .video {
                self.makeVideoThumbnail(for: request.url, completion: finish)
            } else {
                // Quick Look renders the composed GIF canvas, whereas ImageIO
                // can return a delta frame. Delta frames were the source of
                // blank and cropped cards in the media library.
                self.makeQuickLookThumbnail(for: request.url) { image in
                    if let image {
                        finish(image)
                        return
                    }

                    self.queue.async {
                        autoreleasepool { finish(self.makeImageThumbnail(for: request.url)) }
                    }
                }
            }
        }
    }

    private func finish(_ request: Request, image: NSImage?) {
        lock.lock()
        if let image {
            let cost = image.representations.reduce(0) { $0 + max(1, $1.pixelsWide) * max(1, $1.pixelsHigh) * 4 }
            cache.setObject(image, forKey: request.key as NSString, cost: max(1, cost))
        }
        let completions = pending.removeValue(forKey: request.key as NSString) ?? []
        activeRequests -= 1
        let requests = takeRequests()
        lock.unlock()
        DispatchQueue.main.async { completions.forEach { $0(image) } }
        requests.forEach(generate)
    }

    static func cacheKey(for url: URL, mediaType: WidgetMediaType) -> NSString {
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationDate = resourceValues?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = resourceValues?.fileSize ?? 0
        return "\(url.absoluteString)#\(mediaType.rawValue)#\(modificationDate)#\(fileSize)" as NSString
    }

    private func makeQuickLookThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 240),
            scale: 2,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation?.nsImage)
        }
    }

    private func makeImageThumbnail(for url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary

        // Sticker-like GIFs commonly begin with a fully transparent frame.
        // Pick the first frame with visible pixels so their card does not look empty.
        let frameCount = CGImageSourceGetCount(source)
        var fallbackImage: CGImage?
        for index in thumbnailFrameIndices(frameCount: frameCount) {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { continue }
            fallbackImage = fallbackImage ?? image
            if containsVisiblePixels(in: image) {
                return NSImage(cgImage: image, size: .zero)
            }
        }

        guard let fallbackImage else { return nil }
        return NSImage(cgImage: fallbackImage, size: .zero)
    }

    private func thumbnailFrameIndices(frameCount: Int) -> [Int] {
        guard frameCount > 0 else { return [] }

        // Sampling prevents a long GIF from delaying the list, while still covering
        // the animation instead of only inspecting its initial frame.
        let sampleCount = min(frameCount, 48)
        guard frameCount > sampleCount else { return Array(0..<frameCount) }

        return (0..<sampleCount).map { sample in
            sample * (frameCount - 1) / (sampleCount - 1)
        }
    }

    private func containsVisiblePixels(in image: CGImage) -> Bool {
        let sampleSize = 48
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }

        context.interpolationQuality = .low
        context.clear(CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return true }
        for offset in stride(from: 3, to: sampleSize * bytesPerRow, by: bytesPerPixel) {
            if data[offset] > 8 { return true }
        }
        return false
    }

    private func makeVideoThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        Task.detached(priority: .userInitiated) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 240)
            do {
                let result = try await generator.image(at: .zero)
                completion(NSImage(cgImage: result.image, size: .zero))
            } catch {
                completion(nil)
            }
        }
    }
}
