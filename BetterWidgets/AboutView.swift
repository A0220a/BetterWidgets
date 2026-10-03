import AppKit
import SwiftUI

struct AboutView: View {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    private var version: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var author: String {
        bundle.object(forInfoDictionaryKey: "BetterWidgetsAuthor") as? String ?? "madi"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BetterWidgets").font(.title2.weight(.semibold))
                    Text("Version \(version) (\(build))").foregroundStyle(.secondary)
                    Text("Created by \(author)").font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Label("Add an image, GIF, or video with Add Widget, or browse a folder with Add Folder.", systemImage: "plus.circle")
                Label("Choose Edit Widgets to move widgets. Drag a corner to resize while keeping proportions.", systemImage: "arrow.up.left.and.arrow.down.right")
                Label("Click Done to finish editing. Use each card to show, hide, or replace its widget.", systemImage: "checkmark.circle")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Text("Images, GIFs & videos on your desktop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420)
    }
}
