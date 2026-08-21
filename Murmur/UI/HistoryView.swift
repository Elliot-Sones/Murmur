import AppKit
import SwiftUI

struct HistoryView: View {
    private var history: HistoryStore { .shared }
    @State private var query = ""
    @State private var confirmingClear = false

    var body: some View {
        // Reading revision ties this view to store mutations.
        let _ = history.revision
        let records = history.records(matching: query)

        VStack(spacing: 0) {
            HStack {
                TextField("Search dictations", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Clear All", role: .destructive) { confirmingClear = true }
                    .disabled(records.isEmpty && query.isEmpty)
            }
            .padding(12)

            if records.isEmpty {
                Spacer()
                Text(query.isEmpty ? "No dictations yet." : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(records) { record in
                    HistoryRow(record: record)
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
}

private struct HistoryRow: View {
    let record: DictationRecord
    private var history: HistoryStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
                Text("\(record.totalMs) ms")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.cleanedText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy text")
                Button(role: .destructive) {
                    history.delete(record)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Text(record.cleanedText)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
