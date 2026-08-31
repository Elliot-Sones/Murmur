import SwiftUI

/// One agent in the activity dock: the bot's custom avatar (or the
/// OpenMausBot icon as fallback), a slow-spinning ring while it works, and a
/// small badge when it finished or failed.
struct AgentDockIcon: View {
    let job: AgentJobBoard.Job
    let reduceMotion: Bool

    @State private var spinning = false

    private var botColor: Color { Self.color(named: job.color) ?? .accentColor }

    private var accent: Color {
        switch job.phase {
        case .working: botColor
        case .done: .green
        case .failed: .red
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .overlay(workingRing)
            badge
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .onAppear { spinning = true }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = job.avatarUrl {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialDisc
            }
        } else {
            // Most bots have no custom avatar; mirror the OpenMausBot app's
            // identity mark instead: the accent-colored disc with an initial.
            initialDisc
        }
    }

    private var initialDisc: some View {
        ZStack {
            Circle().fill(botColor.gradient)
            Text(job.agentName.prefix(1).uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var workingRing: some View {
        if job.isWorking {
            if reduceMotion {
                Circle().strokeBorder(accent.opacity(0.8), lineWidth: 2)
            } else {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false),
                        value: spinning
                    )
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch job.phase {
        case .working:
            EmptyView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .background(Circle().fill(.background))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .background(Circle().fill(.background))
        }
    }

    /// The OpenMausBot palette by name; unknown names fall back to the accent.
    private static func color(named name: String?) -> Color? {
        switch name {
        case "teal": .teal
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "coral": Color(red: 1.0, green: 0.45, blue: 0.4)
        default: nil
        }
    }
}
