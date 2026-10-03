//
//  WidgetModel.swift
//  BetterWidgets
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum WidgetMediaType: String, Codable, Hashable, Sendable {
    case image
    case gif
    case video

    nonisolated static func mediaType(for url: URL) -> WidgetMediaType {
        if let contentType = UTType(filenameExtension: url.pathExtension) {
            if contentType.conforms(to: .gif) {
                return .gif
            }
            if contentType.conforms(to: .movie) {
                return .video
            }
        }

        switch url.pathExtension.lowercased() {
        case "gif": return .gif
        case "mp4", "mov": return .video
        default: return .image
        }
    }
}

struct WidgetModel: Codable, Identifiable {
    let id: UUID
    var mediaType: WidgetMediaType
    var imageURL: URL
    var position: CGPoint
    var size: CGSize
    var isMuted: Bool
    var isEnabled: Bool
    var mediaBookmarkData: Data?
    var mediaItemKey: String?

    init(
        id: UUID = UUID(),
        mediaType: WidgetMediaType? = nil,
        imageURL: URL,
        position: CGPoint = .zero,
        size: CGSize = CGSize(width: 300, height: 200),
        isMuted: Bool = true,
        isEnabled: Bool = true,
        mediaBookmarkData: Data? = nil,
        mediaItemKey: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType ?? WidgetMediaType.mediaType(for: imageURL)
        self.imageURL = imageURL
        self.position = position
        self.size = size
        self.isMuted = isMuted
        self.isEnabled = isEnabled
        self.mediaBookmarkData = mediaBookmarkData
        self.mediaItemKey = mediaItemKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, mediaType, imageURL, position, size, isMuted, isEnabled, mediaBookmarkData, mediaItemKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageURL = try container.decode(URL.self, forKey: .imageURL)
        mediaType = try container.decodeIfPresent(WidgetMediaType.self, forKey: .mediaType) ?? WidgetMediaType.mediaType(for: imageURL)
        position = try container.decode(CGPoint.self, forKey: .position)
        size = try container.decode(CGSize.self, forKey: .size)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mediaBookmarkData = try container.decodeIfPresent(Data.self, forKey: .mediaBookmarkData)
        mediaItemKey = try container.decodeIfPresent(String.self, forKey: .mediaItemKey)
    }
}
