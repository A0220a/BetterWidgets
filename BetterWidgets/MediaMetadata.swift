//
//  MediaMetadata.swift
//  BetterWidgets
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

enum MediaMetadata {
    static func dimensions(for url: URL, mediaType: WidgetMediaType) async -> CGSize? {
        switch mediaType {
        case .image, .gif:
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: imageDimensions(for: url))
                }
            }
        case .video:
            return await videoDimensions(for: url)
        }
    }

    static func initialWidgetSize(for dimensions: CGSize) -> CGSize {
        let maximumSize = CGSize(width: 360, height: 300)
        guard dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            return CGSize(width: 300, height: 200)
        }

        let scale = min(maximumSize.width / dimensions.width, maximumSize.height / dimensions.height)
        return CGSize(width: dimensions.width * scale, height: dimensions.height * scale)
    }

    nonisolated private static func imageDimensions(for url: URL) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.doubleValue > 0, height.doubleValue > 0
        else {
            return nil
        }

        let size = CGSize(width: width.doubleValue, height: height.doubleValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: size.height, height: size.width)
            : size
    }

    private static func videoDimensions(for url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)

        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(transform)
            return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        } catch {
            print("BetterWidgets: unable to read video dimensions: \(error.localizedDescription)")
            return nil
        }
    }
}
