import AppKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    private var history: HistoryStore { .shared }
    @State private var query = ""
    @State private var confirmingClear = false
    @State private var expandedId: PersistentIdentifier?

    var body: some View {
        // Reading revision ties this view to store mutations.
        let _ = history.revision
        let records = history.records(matching: query)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search dictations", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Clear All", role: .destructive) { confirmingClear = true }
                    .disabled(records.isEmpty && query.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if let summary = summary(records) {
                Text(summary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if records.isEmpty {
                Spacer()
                Text(query.isEmpty ? "No dictations yet." : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(records) { record in
                    HistoryRow(
                        record: record,
                        isExpanded: expandedId == record.persistentModelID
                    ) {
                        expandedId = expandedId == record.persistentModelID
                            ? nil
                            : record.persistentModelID
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Delete all dictation history?",
            isPresented: $confirmingClear
        ) {
            Button("Delete All", role: .destructive) { history.clear() }
        }
    }

    private func summary(_ records: [DictationRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        var parts = ["\(records.count) dictations"]
        if let median = Median.of(records.map(\.totalMs)) {
            parts.append("median \(median) ms")
        }
        let corrected = records.compactMap { record in
            record.correctedText.map { (record.cleanedText, $0) }
        }
        if !corrected.isEmpty {
            let average = corrected
                .map { AccuracyScore.percent(inserted: $0.0, corrected: $0.1) }
                .reduce(0, +) / Double(corrected.count)
            parts.append(String(format: "%.0f%% accuracy over %d corrected", average, corrected.count))
        }
        let flagged = records.filter { $0.vote == -1 }.count
        if flagged > 0 {
            parts.append("\(flagged) flagged")
        }
        return parts.joined(separator: " · ")
    }
}

private struct HistoryRow: View {
    let record: DictationRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    private var history: HistoryStore { .shared }
    @State private var correctionDraft = ""
    @State private var isEditingCorrection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
            if isExpanded {
                breakdown
            }
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let appName = record.appName {
                    Text(appName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                if record.mode == "command" {
                    Text("rewrite")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
                if let corrected = record.correctedText {
                    AccuracyChip(
                        percent: AccuracyScore.percent(
                            inserted: record.cleanedText, corrected: corrected
                        )
                    )
                }
                if record.vote == -1 {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .help("Flagged as wrong")
                        .accessibilityLabel("Flagged as wrong")
                }
                Text("\(record.totalMs) ms")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        record.correctedText ?? record.cleanedText, forType: .string
                    )
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy text")
                .accessibilityLabel("Copy dictation text")
                Button(role: .destructive) {
                    history.delete(record)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this dictation")
                .accessibilityLabel("Delete dictation")
            }
            Text(record.cleanedText)
                .lineLimit(isExpanded ? nil : 3)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var breakdown: some View {
        let stages = [record.transcribeMs, record.cleanupMs, record.pasteMs]
        VStack(alignment: .leading, spacing: 8) {
            if stages.allSatisfy({ $0 == 0 }) {
                Text("Recorded before stage tracking; no time breakdown available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                StageBar(shares: StageShare.shares(stages))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    stageRow(color: .blue, label: "Transcription", ms: record.transcribeMs)
                    stageRow(color: .purple, label: "Cleanup", ms: record.cleanupMs)
                    stageRow(color: .green, label: "Paste", ms: record.pasteMs)
                }
            }

            Text(audioLine)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("Engine: \(record.engine)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if record.rawTranscript != record.cleanedText {
                Text("Raw: \(record.rawTranscript)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            HStack {
                correctionSection
                Spacer()
                Button(record.vote == -1 ? "Unflag" : "Flag as wrong") {
                    history.setVote(record, vote: record.vote == -1 ? 0 : -1)
                }
                .controlSize(.small)
            }
        }
        .padding(.leading, 20)
        .padding(.top, 2)
    }

    private var audioLine: String {
        var line = String(format: "%.1f s audio", Double(record.audioMs) / 1000)
        if record.totalMs > 0, record.audioMs > 0 {
            line += String(format: " · %.1fx realtime", Double(record.audioMs) / Double(record.totalMs))
        }
        return line
    }

    private func stageRow(color: Color, label: String, ms: Int) -> some View {
        GridRow {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption)
            Text("\(ms) ms")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var correctionSection: some View {
        if isEditingCorrection {
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "What it should have said",
                    text: $correctionDraft,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Correction") {
                        history.setCorrected(record, text: correctionDraft)
                        isEditingCorrection = false
                    }
                    .disabled(correctionDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { isEditingCorrection = false }
                }
                .controlSize(.small)
            }
        } else if let corrected = record.correctedText {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Corrected to:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") {
                        correctionDraft = corrected
                        isEditingCorrection = true
                    }
                    Button("Remove") { history.setCorrected(record, text: nil) }
                }
                .controlSize(.small)
                .font(.caption)
                Text(corrected)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Button("Mark correction…") {
                correctionDraft = record.cleanedText
                isEditingCorrection = true
            }
            .controlSize(.small)
            .help("Type what Murmur should have inserted; accuracy is scored against it")
        }
    }
}

private struct AccuracyChip: View {
    let percent: Double

    private var color: Color {
        if percent >= 95 { return .green }
        if percent >= 85 { return .orange }
        return .red
    }

    var body: some View {
        Text(String(format: "%.0f%%", percent))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel(String(format: "Accuracy %.0f percent", percent))
    }
}

private struct StageBar: View {
    let shares: [Double]
    private let colors: [Color] = [.blue, .purple, .green]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(shares.indices, id: \.self) { index in
                    Rectangle()
                        .fill(colors[index % colors.count])
                        .frame(width: max(0, geometry.size.width * shares[index]))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
