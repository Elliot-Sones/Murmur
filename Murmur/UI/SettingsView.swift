import ServiceManagement
import SwiftUI

struct SettingsView: View {
    // Reopen on the tab the user last used, surviving relaunches.
    @AppStorage("settingsSelectedTab") private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag("general")
            DictionarySettingsTab()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                .tag("dictionary")
            AppProfilesSettingsTab()
                .tabItem { Label("Apps", systemImage: "app.badge") }
                .tag("apps")
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag("history")
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettingsTab: View {
    private var settings: SettingsStore { .shared }
    private var controller: DictationController { .shared }
    @State private var ollamaModels: [String] = []

    var body: some View {
        Form {
            Section("Keys") {
                Picker("Dictation key", selection: Binding(
                    get: { settings.hotkey },
                    set: { settings.hotkey = $0 }
                )) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                Picker("Command key (rewrite selection)", selection: Binding(
                    get: { settings.commandHotkey },
                    set: { settings.commandHotkey = $0 }
                )) {
                    ForEach(CommandHotkeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
            }

            Section("Cleanup") {
                Toggle("AI cleanup", isOn: Binding(
                    get: { settings.cleanupEnabled },
                    set: { settings.cleanupEnabled = $0 }
                ))
                Picker("Engine", selection: Binding(
                    get: { settings.cleanupEngine },
                    set: { settings.cleanupEngine = $0 }
                )) {
                    ForEach(CleanupEngineChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .disabled(!settings.cleanupEnabled)

                if settings.cleanupEngine == .ollama {
                    Picker("Ollama model", selection: Binding(
                        get: { settings.ollamaModel },
                        set: { settings.ollamaModel = $0 }
                    )) {
                        Text("Choose…").tag("")
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(!settings.cleanupEnabled)
                    if ollamaModels.isEmpty {
                        Text("Ollama server not reachable at localhost:11434.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Read back") {
                Picker("Voice engine", selection: Binding(
                    get: { settings.ttsEngine },
                    set: { settings.ttsEngine = $0 }
                )) {
                    ForEach(TtsEngineChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if settings.ttsEngine == .kokoro {
                    TextField("Kokoro voice", text: Binding(
                        get: { settings.ttsKokoroVoice },
                        set: { settings.ttsKokoroVoice = $0 }
                    ))
                    Text("Try af_heart, af_bella, am_michael, bf_emma, or bm_george. First use downloads the model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.ttsEngine == .qwen {
                    TextField("Qwen voice", text: Binding(
                        get: { settings.ttsQwenVoice },
                        set: { settings.ttsQwenVoice = $0 }
                    ))
                }
                if settings.ttsEngine.serverModel != nil {
                    Text("Needs the local voice server: run `make tts-serve` in the Murmur folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Live preview in HUD while dictating", isOn: Binding(
                    get: { settings.streamingPreviewEnabled },
                    set: { settings.streamingPreviewEnabled = $0 }
                ))
                Toggle("Sound cues", isOn: Binding(
                    get: { settings.soundCuesEnabled },
                    set: { settings.soundCuesEnabled = $0 }
                ))
                Toggle("Voice processing (experimental, may record silence)", isOn: Binding(
                    get: { settings.voiceProcessingEnabled },
                    set: { settings.voiceProcessingEnabled = $0 }
                ))
                Stepper(
                    "Clipboard restore delay: \(settings.restoreDelayMs) ms",
                    value: Binding(
                        get: { settings.restoreDelayMs },
                        set: { settings.restoreDelayMs = $0 }
                    ),
                    in: 100...1000,
                    step: 50
                )
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                ))
            }

            Section("Status") {
                LabeledContent("Speech engine", value: controller.engineStatus)
                LabeledContent(
                    "AI cleanup engine",
                    value: FoundationModelsCleanup.isAvailable
                        ? "Apple on-device model available"
                        : "Apple Intelligence unavailable, using raw transcripts"
                )
            }
        }
        .formStyle(.grouped)
        .task {
            ollamaModels = await OllamaCleanup.availableModels()
        }
    }
}

private struct DictionarySettingsTab: View {
    private var dictionary: DictionaryStore { .shared }
    private var history: HistoryStore { .shared }
    @State private var newWord = ""

    private var suggestions: [String] {
        let _ = history.revision
        let texts = history.records(matching: "").prefix(200).map(\.cleanedText)
        return DictionaryLearner.suggestions(
            from: Array(texts),
            knownWords: dictionary.words + dictionary.dismissedSuggestions
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Add a word or name", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Names and jargon the cleanup model should spell exactly like this.")
            }

            let suggested = suggestions
            if !suggested.isEmpty {
                Section("Suggested from your dictations") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggested, id: \.self) { word in
                                HStack(spacing: 4) {
                                    Button(word) { dictionary.add(word) }
                                        .help("Add \"\(word)\" to the dictionary")
                                    Button {
                                        dictionary.dismissSuggestion(word)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Dismiss this suggestion")
                                    .accessibilityLabel("Dismiss suggestion \(word)")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            }

            Section("Words") {
                if dictionary.words.isEmpty {
                    ContentUnavailableView(
                        "Dictionary is empty",
                        systemImage: "character.book.closed",
                        description: Text("Add names or jargon above, or accept a suggestion after you dictate for a while.")
                    )
                } else {
                    ForEach(dictionary.words, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(role: .destructive) {
                                dictionary.remove(word)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from dictionary")
                            .accessibilityLabel("Remove \(word)")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addWord() {
        dictionary.add(newWord)
        newWord = ""
    }
}

private struct AppProfilesSettingsTab: View {
    private var profiles: ProfileStore { .shared }
    @State private var selectedApp: String = ""

    private var runningApps: [(bundleId: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleId = app.bundleIdentifier else { return nil }
                return (bundleId, app.localizedName ?? bundleId)
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker("App", selection: $selectedApp) {
                        Text("Choose…").tag("")
                        ForEach(runningApps, id: \.bundleId) { app in
                            Text(app.name).tag(app.bundleId)
                        }
                    }
                    Button("Add Profile") {
                        guard !selectedApp.isEmpty else { return }
                        let name = runningApps.first { $0.bundleId == selectedApp }?.name ?? selectedApp
                        profiles.upsert(AppProfile(bundleId: selectedApp, appName: name))
                        selectedApp = ""
                    }
                    .disabled(selectedApp.isEmpty)
                }
            } footer: {
                Text("Per-app dictation behavior: tone hint, raw mode, extra vocabulary.")
            }

            Section("Profiles") {
                if profiles.profiles.isEmpty {
                    ContentUnavailableView(
                        "No app profiles yet",
                        systemImage: "app.badge",
                        description: Text("Pick a running app above to give it its own tone, raw mode, or vocabulary. Apps without a profile just use your defaults.")
                    )
                } else {
                    ForEach(profiles.profiles) { profile in
                        ProfileRow(profile: profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileRow: View {
    let profile: AppProfile
    private var store: ProfileStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.appName.isEmpty ? profile.bundleId : profile.appName)
                    .font(.headline)
                Spacer()
                Toggle("Raw mode", isOn: Binding(
                    get: { store.resolve(bundleId: profile.bundleId)?.rawMode ?? false },
                    set: { value in
                        var updated = store.resolve(bundleId: profile.bundleId) ?? profile
                        updated.rawMode = value
                        store.upsert(updated)
                    }
                ))
                Button(role: .destructive) {
                    store.remove(bundleId: profile.bundleId)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this profile")
                .accessibilityLabel("Remove profile for \(profile.appName.isEmpty ? profile.bundleId : profile.appName)")
            }
            TextField("Tone hint (e.g. casual, lowercase ok)", text: Binding(
                get: { store.resolve(bundleId: profile.bundleId)?.toneHint ?? "" },
                set: { value in
                    var updated = store.resolve(bundleId: profile.bundleId) ?? profile
                    updated.toneHint = value.isEmpty ? nil : value
                    store.upsert(updated)
                }
            ))
            TextField("Extra vocabulary, comma separated", text: Binding(
                get: { store.resolve(bundleId: profile.bundleId)?.vocab.joined(separator: ", ") ?? "" },
                set: { value in
                    var updated = store.resolve(bundleId: profile.bundleId) ?? profile
                    updated.vocab = value.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    store.upsert(updated)
                }
            ))
        }
        .padding(.vertical, 4)
    }
}
