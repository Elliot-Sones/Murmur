import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            DictionarySettingsTab()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            AppProfilesSettingsTab()
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .frame(width: 540, height: 420)
    }
}

private struct GeneralSettingsTab: View {
    private var settings: SettingsStore { .shared }
    private var controller: DictationController { .shared }

    var body: some View {
        Form {
            Picker("Dictation key", selection: Binding(
                get: { settings.hotkey },
                set: { settings.hotkey = $0 }
            )) {
                ForEach(HotkeyChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)

            Toggle("Voice processing (experimental, may record silence)", isOn: Binding(
                get: { settings.voiceProcessingEnabled },
                set: { settings.voiceProcessingEnabled = $0 }
            ))

            Toggle("AI cleanup (Apple on-device model)", isOn: Binding(
                get: { settings.cleanupEnabled },
                set: { settings.cleanupEnabled = $0 }
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

            LabeledContent("Speech engine", value: controller.engineStatus)
            LabeledContent(
                "AI cleanup engine",
                value: FoundationModelsCleanup.isAvailable
                    ? "Apple on-device model available"
                    : "Apple Intelligence unavailable, using raw transcripts"
            )
        }
        .padding(20)
    }
}

private struct DictionarySettingsTab: View {
    private var dictionary: DictionaryStore { .shared }
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Names and jargon the cleanup model should spell exactly like this.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Add a word or name", text: $newWord)
                    .onSubmit(addWord)
                Button("Add", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List(dictionary.words, id: \.self) { word in
                HStack {
                    Text(word)
                    Spacer()
                    Button(role: .destructive) {
                        dictionary.remove(word)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 200)
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-app dictation behavior: tone hint, raw mode, extra vocabulary.")
                .foregroundStyle(.secondary)
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
            List(profiles.profiles) { profile in
                ProfileRow(profile: profile)
            }
            .frame(minHeight: 200)
        }
        .padding(20)
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
