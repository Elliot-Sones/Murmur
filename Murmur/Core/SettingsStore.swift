import Foundation
import Observation

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case fn
    case rightCommand
    case optionP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: "Hold Fn (Globe)"
        case .rightCommand: "Hold Right Command"
        case .optionP: "Hold Option+P"
        }
    }

    var shortName: String {
        switch self {
        case .fn: "🌐"
        case .rightCommand: "Right ⌘"
        case .optionP: "⌥P"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private enum Key {
        static let hotkey = "hotkey"
        static let voiceProcessing = "voiceProcessingEnabled"
        static let cleanup = "cleanupEnabled"
        static let restoreDelay = "restoreDelayMs"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var hotkey: HotkeyChoice {
        didSet { defaults.set(hotkey.rawValue, forKey: Key.hotkey) }
    }
    var voiceProcessingEnabled: Bool {
        didSet { defaults.set(voiceProcessingEnabled, forKey: Key.voiceProcessing) }
    }
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Key.cleanup) }
    }
    var restoreDelayMs: Int {
        didSet { defaults.set(restoreDelayMs, forKey: Key.restoreDelay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: Key.hotkey) ?? "") ?? .fn
        voiceProcessingEnabled = defaults.object(forKey: Key.voiceProcessing) as? Bool ?? true
        cleanupEnabled = defaults.object(forKey: Key.cleanup) as? Bool ?? true
        restoreDelayMs = defaults.object(forKey: Key.restoreDelay) as? Int ?? 250
    }
}
