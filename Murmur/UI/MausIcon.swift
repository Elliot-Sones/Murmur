import AppKit
import SwiftUI

/// The OpenMausBot app icon, used on every quick-chat surface (input bar and
/// reply bubble) so the feature reads as one thing. Falls back to a generic
/// chat glyph if the app is not installed.
struct MausIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let appIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: MausClient.bundleId
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()
}
