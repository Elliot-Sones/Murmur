import SwiftUI

/// Meetings page: searchable list on the left, transcript + notes detail on
/// the right. Live meetings stream text in as windows confirm.
///
/// Visual language: light-blue accent over system backgrounds. Transcript
/// reads as a conversation: Them on the left in neutral bubbles, Me on the
/// right in tinted bubbles. All colors are washes over semantic system
/// colors so both appearances keep AA contrast.
struct MeetingsSettingsTab: View {
    private var store: MeetingStore { .shared }
    private var meetingController: MeetingController { .shared }
    @State private var selectedId: String?
    @State private var search = ""
    @State private var detailTab: DetailTab = .transcript
    @State private var confirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case notes = "Notes"
    }

    private enum Theme {
        static let tint = Color(red: 0.29, green: 0.56, blue: 0.89)
        static let wash = tint.opacity(0.07)
        static let bubbleMe = tint.opacity(0.16)
        static let bubbleThem = Color.primary.opacity(0.055)
    }

    var body: some View {
        HSplitView {
            meetingList
                .frame(minWidth: 225, idealWidth: 250, maxWidth: 300)
            detail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.wash)
        }
        .onAppear {
            if selectedId == nil { selectedId = store.meetings.first?.id }
        }
    }

    // MARK: - List

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
                    row(meeting)
                        .tag(meeting.id)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            startStopButton
                .padding(10)
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

    private func row(_ meeting: MeetingRecord) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(meeting.id == meetingController.liveMeetingId ? Color.red.opacity(0.14) : Theme.tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(
                    systemName: meeting.id == meetingController.liveMeetingId
                        ? "record.circle" : "waveform.and.mic"
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(meeting.id == meetingController.liveMeetingId ? Color.red : Theme.tint)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle(meeting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ meeting: MeetingRecord) -> String {
        let date = meeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if meeting.id == meetingController.liveMeetingId { return "Recording · \(date)" }
        guard meeting.durationSeconds > 0 else { return date }
        return "\(date) · \(max(1, Int(meeting.durationSeconds / 60))) min"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let meeting = store.meetings.first(where: { $0.id == selectedId }) {
            VStack(alignment: .leading, spacing: 12) {
                header(meeting)
                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Group {
                    switch detailTab {
                    case .transcript: transcript(meeting)
                    case .notes: notesEditor(meeting)
                    }
                }
                .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(14)
        } else {
            emptyState
        }
    }

    private func header(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField(
                    "Title",
                    text: Binding(
                        get: { meeting.title },
                        set: { store.rename(meeting.id, to: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    copyTranscript(meeting)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.tint)
                .help("Copy transcript")
                .accessibilityLabel("Copy transcript")
                .disabled(meeting.segments.isEmpty)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.8))
                .help("Delete meeting")
                .accessibilityLabel("Delete meeting")
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
            HStack(spacing: 6) {
                chip(
                    icon: "calendar",
                    text: meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
                )
                if meeting.id == meetingController.liveMeetingId {
                    chip(icon: "record.circle", text: "Recording", tint: .red)
                } else if meeting.durationSeconds > 0 {
                    chip(icon: "clock", text: "\(max(1, Int(meeting.durationSeconds / 60))) min")
                }
                if !meeting.segments.isEmpty {
                    chip(icon: "text.alignleft", text: "\(meeting.segments.count) segments")
                }
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color = Theme.tint) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.caption)
        }
        .foregroundStyle(tint == Theme.tint ? Color.secondary : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.1), in: Capsule())
        .monospacedDigit()
    }

    // MARK: - Transcript (conversation view)

    private func transcript(_ meeting: MeetingRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(meeting.segments.enumerated()), id: \.offset) { index, segment in
                        bubble(segment)
                            .id(index)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if meeting.segments.isEmpty {
                    transcriptEmptyOverlay(meeting)
                }
            }
            .onChange(of: meeting.segments.count) {
                guard meeting.id == meetingController.liveMeetingId else { return }
                if reduceMotion {
                    proxy.scrollTo(meeting.segments.count - 1, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(meeting.segments.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func bubble(_ segment: MeetingSegment) -> some View {
        let isMe = segment.source == "me"
        return VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(isMe ? "Me" : "Them")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isMe ? Theme.tint : .secondary)
                Text(timestamp(segment.offset))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(segment.text)
                .font(.callout)
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    isMe ? Theme.bubbleMe : Theme.bubbleThem,
                    in: RoundedRectangle(cornerRadius: 11)
                )
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
        .padding(isMe ? .leading : .trailing, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMe ? "Me" : "Them"), \(timestamp(segment.offset)): \(segment.text)")
    }

    @ViewBuilder
    private func transcriptEmptyOverlay(_ meeting: MeetingRecord) -> some View {
        if meeting.id == meetingController.liveMeetingId {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(Theme.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                Text("Listening…")
                    .font(.callout.weight(.medium))
                Text("Text appears as each chunk of speech is confirmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No speech was transcribed in this meeting.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func notesEditor(_ meeting: MeetingRecord) -> some View {
        TextEditor(
            text: Binding(
                get: { meeting.notes },
                set: { store.saveNotes($0, for: meeting.id) }
            )
        )
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(8)
        .overlay(alignment: .topLeading) {
            if meeting.notes.isEmpty {
                Text("Type rough notes during the meeting; the summary will use them as anchors.")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
                    .padding(.leading, 13)
                    .allowsHitTesting(false)
            }
        }
    }

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

    private func timestamp(_ offset: Double) -> String {
        let total = Int(offset)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func copyTranscript(_ meeting: MeetingRecord) {
        let text = meeting.segments.map { segment in
            "[\(timestamp(segment.offset))] \(segment.source == "me" ? "Me" : "Them"): \(segment.text)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
