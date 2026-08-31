import SwiftUI

/// One agent in the activity dock: the bot's custom avatar if it uploaded
/// one, otherwise the OpenMausBot mascot in the bot's color — the same look
/// the bot has in the app. A slow-spinning ring shows while it works, and a
/// small badge marks finished or failed.
struct AgentDockIcon: View {
    let job: AgentJobBoard.Job
    let reduceMotion: Bool

    @State private var spinning = false

    private var ringColor: Color {
        Color(MausMascotView.color(named: job.color))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
                .frame(width: 20, height: 20)
                .overlay(workingRing)
            badge
        }
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
        .onAppear { spinning = true }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = job.avatarUrl {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
                    .clipShape(Circle())
            } placeholder: {
                MausMascotView(colorName: job.color)
            }
        } else {
            MausMascotView(colorName: job.color)
        }
    }

    @ViewBuilder
    private var workingRing: some View {
        if job.isWorking {
            if reduceMotion {
                Circle()
                    .strokeBorder(ringColor.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            } else {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 25, height: 25)
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
                .font(.system(size: 10))
                .foregroundStyle(.green)
                .background(Circle().fill(.background))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .background(Circle().fill(.background))
        }
    }
}
