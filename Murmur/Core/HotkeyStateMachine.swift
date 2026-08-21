import Foundation

/// Pure push-to-talk state machine. Hold = record, release = finish.
/// A quick tap followed by another quick tap locks hands-free mode; the next press finishes.
/// Time comes in through events so the logic stays testable.
struct HotkeyStateMachine {
    enum Event: Equatable {
        case hotkeyDown(TimeInterval)
        case hotkeyUp(TimeInterval)
        case escapeDown
        case tick(TimeInterval)
    }

    enum Action: Equatable {
        case startRecording
        case finishRecording
        case cancelRecording
    }

    private enum Phase: Equatable {
        case idle
        case holding(downAt: TimeInterval)
        case pendingDecision(shortUpAt: TimeInterval)
        case handsFree
    }

    /// A press shorter than this is a tap, not a hold.
    var shortTapMax: TimeInterval = 0.30
    /// A second tap must start within this window after the first tap ended.
    var doubleTapWindow: TimeInterval = 0.40

    private var phase: Phase = .idle

    var isCapturing: Bool { phase != .idle }

    mutating func handle(_ event: Event) -> [Action] {
        switch (phase, event) {
        case (.idle, .hotkeyDown):
            phase = .holding(downAt: downTime(of: event))
            return [.startRecording]

        case (.holding(let downAt), .hotkeyUp(let time)):
            if time - downAt < shortTapMax {
                phase = .pendingDecision(shortUpAt: time)
                return []
            }
            phase = .idle
            return [.finishRecording]

        case (.pendingDecision(let shortUpAt), .hotkeyDown(let time)):
            if time - shortUpAt <= doubleTapWindow {
                phase = .handsFree
                return []
            }
            phase = .holding(downAt: time)
            return [.cancelRecording, .startRecording]

        case (.pendingDecision(let shortUpAt), .tick(let time)):
            guard time - shortUpAt > doubleTapWindow else { return [] }
            phase = .idle
            return [.cancelRecording]

        case (.handsFree, .hotkeyDown):
            phase = .idle
            return [.finishRecording]

        case (.holding, .escapeDown), (.pendingDecision, .escapeDown), (.handsFree, .escapeDown):
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
