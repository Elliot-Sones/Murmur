import Foundation

/// Pure dictation-key state machine. Tap = toggle: a quick press locks
/// listening on and the next press finishes. Hold = push-to-talk: keep the
/// key down while speaking, release to finish. Esc cancels either way.
/// Time comes in through events so the logic stays testable.
struct HotkeyStateMachine {
    enum Event: Equatable {
        case hotkeyDown(TimeInterval)
        case hotkeyUp(TimeInterval)
        case escapeDown
    }

    enum Action: Equatable {
        case startRecording
        case finishRecording
        case cancelRecording
    }

    private enum Phase: Equatable {
        case idle
        case holding(downAt: TimeInterval)
        case locked
        /// Finish was triggered by a key press; its release is ignored.
        case draining
    }

    /// A press shorter than this is a tap (locks listening), longer is a hold.
    var shortTapMax: TimeInterval = 0.30

    private var phase: Phase = .idle

    var isCapturing: Bool {
        switch phase {
        case .holding, .locked: true
        case .idle, .draining: false
        }
    }

    mutating func handle(_ event: Event) -> [Action] {
        switch (phase, event) {
        case (.idle, .hotkeyDown):
            phase = .holding(downAt: downTime(of: event))
            return [.startRecording]

        case (.holding(let downAt), .hotkeyUp(let time)):
            if time - downAt < shortTapMax {
                phase = .locked
                return []
            }
            phase = .idle
            return [.finishRecording]

        case (.locked, .hotkeyDown):
            phase = .draining
            return [.finishRecording]

        case (.draining, .hotkeyUp):
            phase = .idle
            return []

        case (.holding, .escapeDown), (.locked, .escapeDown):
            phase = .idle
            return [.cancelRecording]

        default:
            return []
        }
    }

    private func downTime(of event: Event) -> TimeInterval {
        if case .hotkeyDown(let time) = event { return time }
        return 0
    }
}
