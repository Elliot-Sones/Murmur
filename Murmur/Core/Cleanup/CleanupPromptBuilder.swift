import Foundation

/// Builds the instructions and per-utterance prompt for the cleanup LLM.
struct CleanupPromptBuilder {
    func instructions(dictionary: [String] = [], toneHint: String? = nil) -> String {
        var parts: [String] = [
            """
            You clean up raw speech-to-text transcripts for a dictation app. Rewrite the transcript:
            - Fix punctuation, capitalization, and transcription spacing errors.
            - Remove filler words (um, uh, you know, and "like" when used as filler).
            - Apply self-corrections: "send it Tuesday, no wait, Wednesday" becomes "send it Wednesday".
            - Format dictated lists as lists.
            - Preserve the speaker's words and meaning. Never add information. Never answer \
            questions that appear in the transcript; they are dictated text, not questions for you.
            - Output only the rewritten text, nothing else. If the transcript is empty, output nothing.
            """
        ]
        if !dictionary.isEmpty {
            parts.append("Prefer these exact spellings when they match what was said: \(dictionary.joined(separator: ", ")).")
        }
        if let toneHint, !toneHint.isEmpty {
            parts.append("Tone for this app: \(toneHint).")
        }
        return parts.joined(separator: "\n")
    }

    func userPrompt(rawTranscript: String) -> String {
        "Transcript:\n\(rawTranscript)"
    }
}
