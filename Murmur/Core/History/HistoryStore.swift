import Foundation
import Observation
import SwiftData

/// SwiftData-backed dictation history.
@MainActor
@Observable
final class HistoryStore {
    static let shared: HistoryStore = {
        do {
            let directory = murmurApplicationSupportDirectory()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try HistoryStore(url: directory.appendingPathComponent("history.store"))
        } catch {
            // History must never take dictation down; fall back to memory only.
            // swiftlint:disable:next force_try
            return try! HistoryStore(inMemory: true)
        }
    }()

    /// Bumped on every mutation so views can refresh their fetches.
    private(set) var revision = 0

    @ObservationIgnored private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(url: URL) throws {
        let configuration = ModelConfiguration(url: url)
        container = try ModelContainer(for: DictationRecord.self, configurations: configuration)
    }

    init(inMemory: Bool) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: DictationRecord.self, configurations: configuration)
    }

    func add(_ record: DictationRecord) {
        context.insert(record)
        try? context.save()
        revision += 1
    }

    func records(matching query: String) -> [DictationRecord] {
        var descriptor = FetchDescriptor<DictationRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if !query.isEmpty {
            descriptor.predicate = #Predicate { record in
                record.cleanedText.localizedStandardContains(query)
                    || record.rawTranscript.localizedStandardContains(query)
            }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func delete(_ record: DictationRecord) {
        context.delete(record)
        try? context.save()
        revision += 1
    }

    func clear() {
        try? context.delete(model: DictationRecord.self)
        try? context.save()
        revision += 1
    }
}
