import Foundation
import Observation
import os

/// One meeting on disk. A directory per meeting keeps writes append-only and
/// crash-safe: transcript segments land in a JSONL file the moment they are
/// confirmed, so a crash loses at most the current unconfirmed window.
struct MeetingRecord: Identifiable, Equatable {
    var id: String
    var title: String
    var startedAt: Date
    var durationSeconds: Double
    /// "recording" while live, "done" after End.
    var state: String
    /// Cross-stream-deduplicated segments for display.
    var segments: [MeetingSegment]
    var notes: String
    /// Sage's task summary, empty until the user summarizes.
    var summary: String

    var isLive: Bool { state == "recording" }
}

/// Meeting persistence under Application Support/Murmur/Meetings/<uuid>/:
/// meta.json, transcript.jsonl (one MeetingSegment per line), notes.txt,
/// me.pcm16 + them.pcm16 audio spill (deleted on finish in phase 1).
@MainActor
@Observable
final class MeetingStore {
    static let shared = MeetingStore()

    private let log = Logger(subsystem: "com.elliot.Murmur", category: "meeting-store")
    private(set) var meetings: [MeetingRecord] = []

    private let root: URL
    private var transcriptHandles: [String: FileHandle] = [:]
    /// Raw (pre-dedup) segments per meeting. transcript.jsonl on disk is the
    /// append-only source of truth; the record's `segments` are the deduped
    /// view. Kept in memory so live appends re-dedup without re-reading disk.
    private var rawSegments: [String: [MeetingSegment]] = [:]

    init(root: URL? = nil) {
        self.root =
            root
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: root ?? self.root, withIntermediateDirectories: true)
        reload()
    }

    // MARK: - Lifecycle

    func create(title: String) -> MeetingRecord {
        let record = MeetingRecord(
            id: UUID().uuidString, title: title, startedAt: Date(),
            durationSeconds: 0, state: "recording", segments: [], notes: "", summary: ""
        )
        let dir = directory(for: record.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        writeMeta(record)
        FileManager.default.createFile(atPath: transcriptURL(record.id).path, contents: nil)
        transcriptHandles[record.id] = try? FileHandle(forWritingTo: transcriptURL(record.id))
        rawSegments[record.id] = []
        meetings.insert(record, at: 0)
        return record
    }

    /// Appends one confirmed segment: raw JSONL on disk first (append-only,
    /// crash-safe), then recompute the deduped view the UI observes.
    func append(_ segment: MeetingSegment, to id: String) {
        if let handle = transcriptHandles[id],
            var line = try? JSONEncoder().encode(segment) {
            line.append(0x0A)
            handle.write(line)
        }
        rawSegments[id, default: []].append(segment)
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].segments = Self.deduped(rawSegments[id] ?? [])
    }

    func finish(_ id: String, duration: Double) {
        try? transcriptHandles[id]?.close()
        transcriptHandles[id] = nil
        update(id) {
            $0.state = "done"
            $0.durationSeconds = duration
        }
        // Phase 1 keeps no audio: diarization lands in a later phase.
        for name in ["me.pcm16", "them.pcm16"] {
            try? FileManager.default.removeItem(at: directory(for: id).appendingPathComponent(name))
        }
    }

    func saveNotes(_ notes: String, for id: String) {
        update(id) { $0.notes = notes }
        try? notes.write(
            to: directory(for: id).appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8
        )
    }

    func saveSummary(_ summary: String, for id: String) {
        update(id) { $0.summary = summary }
        try? summary.write(
            to: directory(for: id).appendingPathComponent("summary.txt"),
            atomically: true, encoding: .utf8
        )
    }

    func rename(_ id: String, to title: String) {
        update(id) { $0.title = title }
    }

    /// The deduped transcript as plain "[mm:ss] Speaker: text" lines.
    func transcriptText(for id: String) -> String {
        guard let record = meetings.first(where: { $0.id == id }) else { return "" }
        return record.segments.map { segment in
            let total = Int(segment.offset)
            let stamp = String(format: "%d:%02d", total / 60, total % 60)
            return "[\(stamp)] \(segment.source == "me" ? "Me" : "Them"): \(segment.text)"
        }.joined(separator: "\n")
    }

    func delete(_ id: String) {
        try? transcriptHandles[id]?.close()
        transcriptHandles[id] = nil
        rawSegments[id] = nil
        try? FileManager.default.removeItem(at: directory(for: id))
        meetings.removeAll { $0.id == id }
    }

    func spillDirectory(for id: String) -> URL {
        directory(for: id)
    }

    // MARK: - Loading

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        var loaded: [MeetingRecord] = []
        for dir in contents where dir.hasDirectoryPath {
            guard var record = readMeta(dir) else { continue }
            let raw = readTranscript(record.id)
            rawSegments[record.id] = raw
            record.segments = Self.deduped(raw)
            record.notes =
                (try? String(contentsOf: dir.appendingPathComponent("notes.txt"), encoding: .utf8)) ?? ""
            record.summary =
                (try? String(contentsOf: dir.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? ""
            // A meeting still marked recording after a relaunch died with the
            // app; its confirmed transcript survived. Mark it done.
            if record.isLive { record.state = "done" }
            loaded.append(record)
        }
        meetings = loaded.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Plumbing

    private func update(_ id: String, _ mutate: (inout MeetingRecord) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&meetings[index])
        writeMeta(meetings[index])
    }

    private func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func transcriptURL(_ id: String) -> URL {
        directory(for: id).appendingPathComponent("transcript.jsonl")
    }

    private struct Meta: Codable {
        var id: String
        var title: String
        var startedAt: Date
        var durationSeconds: Double
        var state: String
    }

    private func writeMeta(_ record: MeetingRecord) {
        let meta = Meta(
            id: record.id, title: record.title, startedAt: record.startedAt,
            durationSeconds: record.durationSeconds, state: record.state
        )
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: directory(for: record.id).appendingPathComponent("meta.json"))
    }

    private func readMeta(_ dir: URL) -> MeetingRecord? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
            let meta = try? JSONDecoder().decode(Meta.self, from: data)
        else { return nil }
        return MeetingRecord(
            id: meta.id, title: meta.title, startedAt: meta.startedAt,
            durationSeconds: meta.durationSeconds, state: meta.state,
            segments: [], notes: "", summary: ""
        )
    }

    // MARK: - Cross-stream dedup
    //
    // Without headphones-perfect isolation both captures pick up both voices,
    // so the same utterance is transcribed twice, once per stream. Collapse
    // opposite-source near-duplicates that land close in time, keeping the
    // louder copy (the stream that actually captured the speaker).

    static func deduped(_ raw: [MeetingSegment]) -> [MeetingSegment] {
        let sorted = raw.sorted { $0.offset < $1.offset }
        var kept: [MeetingSegment] = []
        for seg in sorted {
            if let idx = kept.lastIndex(where: { k in
                k.source != seg.source
                    && abs(k.offset - seg.offset) <= 8
                    && similarity(k.text, seg.text) >= 0.5
            }) {
                // Same utterance heard on both streams: keep the better copy.
                if isBetter(seg, than: kept[idx]) { kept[idx] = seg }
            } else {
                kept.append(seg)
            }
        }
        return kept.sorted { $0.offset < $1.offset }
    }

    /// Louder wins when both have a clear energy reading; otherwise the
    /// longer (more complete) transcription wins.
    private static func isBetter(_ a: MeetingSegment, than b: MeetingSegment) -> Bool {
        if let ea = a.energy, let eb = b.energy, abs(ea - eb) > 0.0005 {
            return ea > eb
        }
        return a.text.count > b.text.count
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let intersection = ta.intersection(tb).count
        let union = ta.union(tb).count
        return Double(intersection) / Double(union)
    }

    private static func tokens(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 1 }
        )
    }

    private func readTranscript(_ id: String) -> [MeetingSegment] {
        guard let data = try? Data(contentsOf: transcriptURL(id)),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(MeetingSegment.self, from: Data(line.utf8))
        }.sorted { $0.offset < $1.offset }
    }
}
