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

    init(
        date: Date,
        appBundleId: String?,
        appName: String?,
        rawTranscript: String,
        cleanedText: String,
        audioMs: Int,
        totalMs: Int,
        engine: String
    ) {
        self.date = date
        self.appBundleId = appBundleId
        self.appName = appName
        self.rawTranscript = rawTranscript
        self.cleanedText = cleanedText
        self.audioMs = audioMs
        self.totalMs = totalMs
        self.engine = engine
    }
}
