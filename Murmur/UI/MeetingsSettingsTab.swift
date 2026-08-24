import SwiftUI

/// Meetings page in the Granola idiom: a clean centered document with a big
/// title and metadata chips, transcript set as readable speaker-labeled
/// paragraphs (no chat bubbles), a quiet action rail on the right, and a
/// floating pill toolbar to switch Transcript/Notes. The whole page sits on
/// a soft light-blue wash; the document itself is a white card.
struct MeetingsSettingsTab: View {
    private var store: MeetingStore { .shared }
    private var meetingController: MeetingController { .shared }
    @State private var selectedId: String?
    @State private var search = ""
    @State private var detailTab: DetailTab = .transcript
    @State private var confirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DetailTab: String, CaseIterable {
        case transcript
        case notes

        var icon: String {
            switch self {
            case .transcript: "text.alignleft"
            case .notes: "square.and.pencil"
            }
        }

        var label: String {
            switch self {
            case .transcript: "Transcript"
            case .notes: "My notes"
            }
        }
    }

    private enum Theme {
        static let tint = Color(red: 0.29, green: 0.56, blue: 0.89)
        static let pageTop = Color(red: 0.94, green: 0.965, blue: 1.0)
        static let pageBottom = Color(red: 0.88, green: 0.93, blue: 0.99)
        static let meLabel = tint
        static let themLabel = Color(red: 0.42, green: 0.49, blue: 0.56)
    }

    var body: some View {
        HSplitView {
            meetingList
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)
            detailSurface
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let live = meetingController.liveMeetingId {
                selectedId = live
            } else if selectedId == nil {
                selectedId = store.meetings.first?.id
            }
        }
        .onChange(of: meetingController.liveMeetingId) {
            // A meeting just started (or ended): jump to it live, stay on it after.
            if let live = meetingController.liveMeetingId {
                selectedId = live
                detailTab = .transcript
            }
        }
    }

    // MARK: - Sidebar

    private var filteredMeetings: [MeetingRecord] {
        guard !search.isEmpty else { return store.meetings }
        let query = search.lowercased()
        return store.meetings.filter { meeting in
            meeting.title.lowercased().contains(query)
                || meeting.segments.contains { $0.text.lowercased().contains(query) }
                || meeting.notes.lowercased().contains(query)
        }
    }

    private var meetingList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                ForEach(filteredMeetings) { meeting in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if meeting.id == meetingController.liveMeetingId {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                    .accessibilityLabel("Recording")
                            }
                            Text(meeting.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                        }
                        Text(subtitle(meeting))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(meeting.id)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.sidebar)
            Divider()
            startStopButton.padding(10)
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search meetings")
    }

    @ViewBuilder
    private var startStopButton: some View {
        if meetingController.isRecording {
            Button {
                meetingController.endMeeting()
            } label: {
                Label("End Meeting", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.85))
        } else {
            Button {
                meetingController.startMeeting()
            } label: {
                Label("Start Meeting Notes", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.tint)
        }
    }

    private func subtitle(_ meeting: MeetingRecord) -> String {
        let date = meeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if meeting.id == meetingController.liveMeetingId { return "Recording · \(date)" }
        guard meeting.durationSeconds > 0 else { return date }
        return "\(date) · \(max(1, Int(meeting.durationSeconds / 60))) min"
    }

    // MARK: - Detail surface (tinted page + document + rail)

    @ViewBuilder
    private var detailSurface: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.pageTop, Theme.pageBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            if let meeting = store.meetings.first(where: { $0.id == selectedId }) {
                HStack(spacing: 0) {
                    documentCard(meeting)
                        .padding([.top, .leading, .bottom], 14)
                    actionRail(meeting)
                        .frame(width: 168)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 10)
                }
            } else {
                emptyState
            }
        }
    }

    private func documentCard(_ meeting: MeetingRecord) -> some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        documentHeader(meeting)
                        switch detailTab {
                        case .transcript: transcriptDocument(meeting)
                        case .notes: EmptyView()
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 30)
                    .padding(.bottom, 70)
                    .frame(maxWidth: 660, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                if detailTab == .notes {
                    notesEditor(meeting)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 60)
                }
            }
            pillToolbar
                .padding(.bottom, 14)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }

    private func documentHeader(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Title",
                text: Binding(
                    get: { meeting.title },
                    set: { store.rename(meeting.id, to: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .bold))
            HStack(spacing: 6) {
                chip(icon: "calendar", text: dayLabel(meeting.startedAt))
                if meeting.id == meetingController.liveMeetingId {
                    chip(icon: "record.circle", text: "Recording", tint: .red)
                } else if meeting.durationSeconds > 0 {
                    chip(icon: "clock", text: "\(max(1, Int(meeting.durationSeconds / 60))) min")
                }
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.caption)
        }
        .foregroundStyle(tint ?? Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
        .monospacedDigit()
    }

    // MARK: - Transcript as a document

    @ViewBuilder
    private func transcriptDocument(_ meeting: MeetingRecord) -> some View {
        if meeting.segments.isEmpty {
            transcriptEmpty(meeting)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(meeting.segments.enumerated()), id: \.offset) { index, segment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(segment.source == "me" ? "Me" : "Them")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    segment.source == "me" ? Theme.meLabel : Theme.themLabel
                                )
                            Text(timestamp(segment.offset))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.quaternary)
                        }
                        Text(segment.text)
                            .font(.system(size: 13.5))
                            .lineSpacing(4)
                            .foregroundStyle(.primary.opacity(0.88))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(index)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func transcriptEmpty(_ meeting: MeetingRecord) -> some View {
        if meeting.id == meetingController.liveMeetingId {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Theme.tint)
                    .symbolEffect(
                        .variableColor.iterative, options: .repeating, isActive: !reduceMotion
                    )
                Text("Listening…").font(.callout.weight(.medium))
                Text("Text appears here as each chunk of speech is confirmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("No speech was transcribed in this meeting.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func notesEditor(_ meeting: MeetingRecord) -> some View {
        TextEditor(
            text: Binding(
                get: { meeting.notes },
                set: { store.saveNotes($0, for: meeting.id) }
            )
        )
        .font(.system(size: 13.5))
        .lineSpacing(4)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            if meeting.notes.isEmpty {
                Text("Type rough notes; the summary will use them as anchors.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Floating pill toolbar

    private var pillToolbar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    detailTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 34, height: 26)
                        .background(
                            detailTab == tab ? Theme.tint.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .foregroundStyle(detailTab == tab ? Theme.tint : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(tab.label)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(detailTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: detailTab)
    }

    // MARK: - Action rail

    private func actionRail(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            railSection("Share notes") {
                railButton("Copy transcript", icon: "doc.on.doc", disabled: meeting.segments.isEmpty) {
                    copyTranscript(meeting)
                }
                railButton("Export Markdown", icon: "arrow.down.doc", disabled: meeting.segments.isEmpty) {
                    exportMarkdown(meeting)
                }
            }
            railSection("Details") {
                railFact(icon: "calendar", meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                if meeting.durationSeconds > 0 {
                    railFact(icon: "clock", "\(max(1, Int(meeting.durationSeconds / 60))) min")
                }
                railFact(icon: "text.alignleft", "\(meeting.segments.count) segments")
            }
            Spacer()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete meeting", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.75))
            .disabled(meeting.id == meetingController.liveMeetingId)
            .confirmationDialog(
                "Delete this meeting and its transcript?", isPresented: $confirmingDelete
            ) {
                Button("Delete", role: .destructive) {
                    store.delete(meeting.id)
                    selectedId = store.meetings.first?.id
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func railButton(
        _ title: String, icon: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func railFact(icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.tint.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.tint)
            }
            .accessibilityHidden(true)
            Text("No meetings yet")
                .font(.title3.weight(.semibold))
            Text("Start meeting notes during any call.\nMurmur transcribes both sides, fully on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                meetingController.startMeeting()
            } label: {
                Label("Start Meeting Notes", systemImage: "mic.fill")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.tint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func timestamp(_ offset: Double) -> String {
        let total = Int(offset)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transcriptText(_ meeting: MeetingRecord) -> String {
        meeting.segments.map { segment in
            "[\(timestamp(segment.offset))] \(segment.source == "me" ? "Me" : "Them"): \(segment.text)"
        }.joined(separator: "\n")
    }

    private func copyTranscript(_ meeting: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText(meeting), forType: .string)
    }

    private func exportMarkdown(_ meeting: MeetingRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.title).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines = ["# \(meeting.title)", ""]
        lines.append("_\(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))_")
        if !meeting.notes.isEmpty {
            lines += ["", "## Notes", "", meeting.notes]
        }
        lines += ["", "## Transcript", "", transcriptText(meeting)]
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
