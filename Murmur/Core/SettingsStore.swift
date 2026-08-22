import Foundation
import Observation

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case fn
    case rightCommand
    case controlI
    case controlOption

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: "Hold Fn (Globe)"
        case .rightCommand: "Hold Right Command"
        case .controlI: "Hold Control+I"
        case .controlOption: "Hold Control+Option"
        }
    }

    var shortName: String {
        switch self {
        case .fn: "🌐"
        case .rightCommand: "Right ⌘"
        case .controlI: "⌃I"
        case .controlOption: "⌃⌥"
        }
    }
}

enum CommandHotkeyChoice: String, CaseIterable, Identifiable {
    case rightOption
    case controlO

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: "Hold Right Option"
        case .controlO: "Hold Control+O"
        }
    }

    var shortName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .controlO: "⌃O"
        }
    }
}

enum CleanupEngineChoice: String, CaseIterable, Identifiable {
    case apple
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple on-device"
        case .ollama: "Ollama (local server)"
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
        static let streamingPreview = "streamingPreviewEnabled"
        static let restoreDelay = "restoreDelayMs"
        static let cleanupEngine = "cleanupEngine"
        static let ollamaModel = "ollamaModel"
        static let soundCues = "soundCuesEnabled"
        static let commandHotkey = "commandHotkey"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var hotkey: HotkeyChoice {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Key.hotkey)
            // Right Option is one of the chord keys; vacate it for command mode.
            if hotkey == .controlOption, commandHotkey == .rightOption {
                commandHotkey = .controlO
            }
        }
    }
    var voiceProcessingEnabled: Bool {
        didSet { defaults.set(voiceProcessingEnabled, forKey: Key.voiceProcessing) }
    }
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Key.cleanup) }
    }
    var streamingPreviewEnabled: Bool {
        didSet { defaults.set(streamingPreviewEnabled, forKey: Key.streamingPreview) }
    }
    var cleanupEngine: CleanupEngineChoice {
        didSet { defaults.set(cleanupEngine.rawValue, forKey: Key.cleanupEngine) }
    }
    var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Key.ollamaModel) }
    }
    var soundCuesEnabled: Bool {
        didSet { defaults.set(soundCuesEnabled, forKey: Key.soundCues) }
    }
    var commandHotkey: CommandHotkeyChoice {
        didSet { defaults.set(commandHotkey.rawValue, forKey: Key.commandHotkey) }
    }
    var restoreDelayMs: Int {
        didSet { defaults.set(restoreDelayMs, forKey: Key.restoreDelay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: Key.hotkey) ?? "") ?? .fn
        // Off by default: without a full-duplex audio path, voice processing
        // records silence (all-zero buffers).
        voiceProcessingEnabled = defaults.object(forKey: Key.voiceProcessing) as? Bool ?? false
        cleanupEnabled = defaults.object(forKey: Key.cleanup) as? Bool ?? true
        streamingPreviewEnabled = defaults.object(forKey: Key.streamingPreview) as? Bool ?? true
        cleanupEngine = CleanupEngineChoice(
            rawValue: defaults.string(forKey: Key.cleanupEngine) ?? ""
        ) ?? .apple
        ollamaModel = defaults.string(forKey: Key.ollamaModel) ?? ""
        soundCuesEnabled = defaults.object(forKey: Key.soundCues) as? Bool ?? true
        commandHotkey = CommandHotkeyChoice(
            rawValue: defaults.string(forKey: Key.commandHotkey) ?? ""
        ) ?? .rightOption
        restoreDelayMs = defaults.object(forKey: Key.restoreDelay) as? Int ?? 250
    }
}
