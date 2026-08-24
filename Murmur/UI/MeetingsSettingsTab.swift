import SwiftUI

/// Phase-1 Meetings page: searchable list on the left, transcript + notes
/// detail on the right. Live meetings stream text in as windows confirm.
struct MeetingsSettingsTab: View {
    private var store: MeetingStore { .shared }
    private var meetingController: MeetingController { .shared }
    @State private var selectedId: String?
    @State private var search = ""
    @State private var detailTab: DetailTab = .transcript

    enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case notes = "Notes"
    }

    var body: some View {
        HSplitView {
            meetingList
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
            detail
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
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
                    row(meeting).tag(meeting.id)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                if meetingController.isRecording {
                    Button("End Meeting") { meetingController.endMeeting() }
                } else {
                    Button("Start Meeting Notes") { meetingController.startMeeting() }
                }
                Spacer()
            }
            .padding(8)
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search meetings")
    }

    private func row(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if meeting.id == meetingController.liveMeetingId {
                    Circle().fill(.red).frame(width: 7, height: 7)
                        .accessibilityLabel("Recording")
                }
                Text(meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            Text(subtitle(meeting))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ meeting: MeetingRecord) -> String {
        let date = meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
        if meeting.id == meetingController.liveMeetingId { return "\(date) · recording" }
        guard meeting.durationSeconds > 0 else { return date }
        let minutes = Int(meeting.durationSeconds / 60)
        return "\(date) · \(minutes) min"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let meeting = store.meetings.first(where: { $0.id == selectedId }) {
            VStack(alignment: .leading, spacing: 10) {
                header(meeting)
                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch detailTab {
                case .transcript: transcript(meeting)
                case .notes: notesEditor(meeting)
                }
            }
            .padding(12)
        } else {
            emptyState
        }
    }

    private func header(_ meeting: MeetingRecord) -> some View {
        HStack {
            TextField(
                "Title",
                text: Binding(
                    get: { meeting.title },
                    set: { store.rename(meeting.id, to: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            Spacer()
            Button {
                copyTranscript(meeting)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy transcript")
            .disabled(meeting.segments.isEmpty)
            Button(role: .destructive) {
                store.delete(meeting.id)
                selectedId = store.meetings.first?.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete meeting")
            .disabled(meeting.id == meetingController.liveMeetingId)
        }
    }

    private func transcript(_ meeting: MeetingRecord) -> some View {
        ScrollViewReader { proxy in
            List(Array(meeting.segments.enumerated()), id: \.offset) { index, segment in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(timestamp(segment.offset))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .trailing)
                    Text(segment.source == "me" ? "Me" : "Them")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(segment.source == "me" ? Color.accentColor : .secondary)
                        .frame(width: 40, alignment: .leading)
                    Text(segment.text)
                        .textSelection(.enabled)
                }
                .id(index)
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .overlay {
                if meeting.segments.isEmpty {
                    transcriptEmptyOverlay(meeting)
                }
            }
            .onChange(of: meeting.segments.count) {
                guard meeting.id == meetingController.liveMeetingId else { return }
                proxy.scrollTo(meeting.segments.count - 1, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func transcriptEmptyOverlay(_ meeting: MeetingRecord) -> some View {
        if meeting.id == meetingController.liveMeetingId {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Listening. Text appears as each ~11 s chunk is confirmed.")
                    .font(.callout)
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
        .overlay(alignment: .topLeading) {
            if meeting.notes.isEmpty {
                Text("Type rough notes during the meeting; the summary uses them as anchors.")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No meetings yet")
                .font(.title3.weight(.medium))
            Text("Start meeting notes from the menu bar during any call.\nMurmur transcribes both sides locally.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Meeting Notes") { meetingController.startMeeting() }
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
