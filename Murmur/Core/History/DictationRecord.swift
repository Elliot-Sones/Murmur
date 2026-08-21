import Foundation
import SwiftData

/// One completed dictation. Text only; audio is never retained.
@Model
final class DictationRecord {
    var date: Date
    var appBundleId: String?
    var appName: String?
    var rawTranscript: String
    var cleanedText: String
    var audioMs: Int
    var totalMs: Int
    var engine: String
    var mode: String = "insert"
    var transcribeMs: Int = 0
    var cleanupMs: Int = 0
    var pasteMs: Int = 0
    /// Hand-corrected ground truth; accuracy is scored against it.
    var correctedText: String?
    /// -1 flagged wrong, 0 unrated.
    var vote: Int = 0

    init(
        date: Date,
        appBundleId: String?,
        appName: String?,
        rawTranscript: String,
        cleanedText: String,
        audioMs: Int,
        totalMs: Int,
        engine: String,
        mode: String = "insert",
        transcribeMs: Int = 0,
        cleanupMs: Int = 0,
        pasteMs: Int = 0
    ) {
        self.date = date
        self.appBundleId = appBundleId
        self.appName = appName
        self.rawTranscript = rawTranscript
        self.cleanedText = cleanedText
        self.audioMs = audioMs
        self.totalMs = totalMs
        self.engine = engine
        self.mode = mode
        self.transcribeMs = transcribeMs
        self.cleanupMs = cleanupMs
        self.pasteMs = pasteMs
    }
}
