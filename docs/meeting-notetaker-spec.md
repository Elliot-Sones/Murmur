# Murmur Meetings: Granola-style notetaker

A meeting notetaker built into Murmur. It captures both sides of a call
without a meeting bot, transcribes locally, and turns the transcript plus
your rough jottings into polished notes. Summaries land in OpenMausBot.

## What Granola does, mapped to Murmur

| Granola behavior | Murmur equivalent |
|---|---|
| Captures mic + system audio, no bot joins the call | ScreenCaptureKit system-audio tap + existing `AudioRecorder` mic path |
| Pops up when a calendar meeting starts | EventKit watcher + pill popup with a Start button |
| You type sparse notes during the call | Small floating notes window, plain text |
| AI merges transcript + your notes into structured notes | Summary agent in OpenMausBot (their models, their thread history) |
| Templates (1:1, standup, sales call, interview) | Template picker; template text goes into the summary prompt |
| Past meetings list, search, share | Meetings tab in History window; copy/export Markdown |

## Core flows

### 1. Meeting starts (calendar trigger)
1. An EventKit watcher polls the next events every minute.
2. One minute before an event with attendees or a conferencing URL, the
   pill shows: calendar icon, event title, "Start notes" button.
3. One click starts capture. Ignoring it dismisses at event end. Manual
   start is always available from the menu bar (also for unscheduled calls).

### 2. During the meeting
- Pill switches to a compact meeting face: elapsed time, level meter,
  pause/resume, End button.
- Optional notes window (menu bar or pill click): free-form typing, saved
  continuously. These are the "sparse notes" the summary enhances.
- Live transcription runs the whole time. No 5-minute cap: this is a new
  capture controller, not `DictationController` (which pastes and caps at
  300 s by design).

### 3. Meeting ends
1. User clicks End (or capture auto-stops when the system audio stream
   reports the meeting app went silent/closed for N minutes; confirm first).
2. The meeting (transcript + notes) is stored **locally only** and opens
   in the Meetings page of the Settings window.
3. Nothing leaves the machine automatically. Summarization is an explicit
   action: the **Send to summary** button on the meeting posts title,
   date, attendees, typed notes, template, and transcript to the
   dedicated **Meetings** bot in OpenMausBot, and the reply is saved back
   onto the meeting as its summary.

## Architecture

### Audio capture (the hard part Granola solved)
Two simultaneous streams:
- **Mic** (you): existing `AudioRecorder` path, 16 kHz mono Float32.
- **System audio** (everyone else): ScreenCaptureKit `SCStream` audio-only
  capture (macOS 13+). Captures all output audio; a per-app filter can
  target Zoom/Meet/Teams/browser when identifiable. Requires the Screen
  Recording permission (one-time TCC prompt; audio capture rides on it).

Streams are resampled to 16 kHz mono and kept separate. The mic stream is
"Me" by construction; the system stream is everyone else.

### Speaker attribution
Two tiers:
- **Me / Them (free, exact):** which stream a segment came from.
- **Them, split by voice (diarization):** FluidAudio's diarizer
  (pyannote-based, ~17.7% DER) runs over the system stream and clusters
  segments into Speaker 1..N. Runs after the meeting ends (one pass, off
  the live path) so it cannot slow live transcription; it shares the
  single-inference slot. The summary prompt includes the calendar
  attendee names so the model can map Speaker 1..N to real names when
  the conversation makes it obvious, and leaves numbered labels when not.

### Transcription
Reuse the Parakeet sliding-window engine. Two constraints shape this:
- **One inference at a time.** FluidAudio's global MLMultiArray cache
  cannot survive concurrent inference (the crash we fixed). Both streams'
  windows are processed through the existing inference slot in
  `FluidAudioTranscriber`, interleaved: mic window, system window, mic
  window. At ~130 ms per 11 s window this is ~2.4% duty cycle for a
  two-stream meeting. Dictation stays usable mid-meeting; its passes just
  share the same slot.
- **Memory.** The sliding-window session consumes samples as it
  confirms windows; capture buffers hold only the current ~15 s window
  per stream (~2 MB total). Raw audio needed later (diarization, gap
  repair) spills to a temp file on disk (16-bit PCM, ~115 MB/hour) and
  is deleted after post-processing. RAM stays flat for arbitrarily long
  meetings. Confirmed text (with stream tag + timestamps) appends to
  disk as it arrives, so a crash mid-meeting loses at most the current
  window, and the spill file lets a relaunch re-transcribe that tail
  and recover the meeting fully.
- **Latency: two-tier live text.** Confirmed text lands ~10-15 s behind
  speech (11 s chunk + 2 s look-ahead). On top of it, a provisional
  pass re-transcribes the last few seconds of the active stream every
  ~1.5 s (through the shared inference slot, same as the dictation
  preview), so words appear near-instantly in a lighter style and get
  replaced by confirmed text as chunks commit. Granola feels instant
  because it streams audio to cloud ASR (Deepgram/AssemblyAI); this
  achieves the same perceived immediacy fully locally.
- **Failed windows.** A window that errors is skipped with a gap
  marker; gaps are re-transcribed from the spill file at meeting end.

Transcript model: ordered segments `{ start, end, source: me|them, text }`,
merged by timestamp for display and for the summary prompt.

### Calendar
- EventKit with full-access calendar permission.
- Watcher lists events in the next 24 h across selected calendars
  (Settings: calendar picker, same as Granola).
- Trigger rule: event starts within 60 s, has ≥1 other attendee OR a
  video-conference URL. All-day events never trigger.

### Summary via OpenMausBot (on demand only)
- Triggered only by the **Send to summary** button; transcripts live
  locally in the Meetings page and are never posted on their own.
- A dedicated **Meetings** bot (auto-created like the Murmur bot, with a
  system description tuned for note-taking: structure, action items,
  decisions; keep the user's own notes verbatim as anchors).
- Payload is one message: metadata header + user notes + transcript.
  Long transcripts chunk into sequential messages if they exceed the
  message size the harness accepts (measure; chunk at ~30k chars).
- The reply is parsed as the summary, saved on the meeting, and shown in
  the Summary tab. `MausClient` already covers bots, messages, and
  reply-await; only chunking is new.
- Sent meetings keep a link to the bot thread, so follow-up Q&A happens
  in OpenMausBot ("what did we decide about pricing last week?").

## Meetings page UI (Settings window)

A new **Meetings** tab in the existing Settings `TabView`
(`Label("Meetings", systemImage: "waveform.and.mic")`), following the
native macOS idiom of the other tabs. Design rules applied: system
controls and SF Symbols only, one primary action per screen, tabular
numerals for times, every state designed (empty, loading, error), AA
contrast in both appearances, 150-300ms transitions, reduced-motion
respected.

### Layout: two panes
- **Left: meeting list** (`List`, inset style, ~260 pt wide).
  - Search field on top (`.searchable`, ⌘F) matching titles, attendees,
    and transcript text.
  - Row: title (semibold), date + duration line in secondary color with
    monospaced digits, and a trailing status glyph: small progress ring
    while summarizing, a checkmark.seal for summarized, nothing for
    local-only. A live recording pins to the top with a red recording
    dot and elapsed time.
  - Sorted newest first. Selection preserved across tab switches.
  - Empty state: "No meetings yet", one-line explainer, and a Start
    meeting notes button.
- **Right: detail** for the selected meeting.
  - Header: editable title, date · duration · attendee names (plain
    text, secondary). No chrome, no cards.
  - Segmented picker: **Transcript · Notes · Summary**.
  - **Transcript tab:** virtualized `List` of segments. Each row:
    timestamp (caption, monospaced digits), speaker label, text.
    Speaker labels are text in fixed tint: Me in the accent color,
    Speaker 1..N in muted distinguishable tints, never color-only
    (label text always present). During a live meeting the list streams,
    pinned to bottom, with a "Jump to latest" capsule when scrolled up.
    Row hover reveals a copy button.
  - **Notes tab:** plain `TextEditor`, autosaved, placeholder "Type
    rough notes during the meeting; the summary uses them as anchors."
  - **Summary tab:** the page's single primary CTA lives here.
    - Not summarized: empty state with template picker (menu) and one
      prominent **Send to summary** button (accent). Caption under it:
      "Sends this meeting to OpenMausBot." Disabled while recording.
    - Sending: inline progress ("Summarizing with Meetings bot…"),
      cancellable; button disabled during flight.
    - Summarized: the summary as selectable rich text, with secondary
      actions: Open in OpenMausBot, Copy, Re-summarize.
    - Failure: inline error with the cause and a Retry button; nothing
      modal.
- **Footer toolbar** (detail pane): Copy transcript, Export Markdown,
  and Delete (destructive tint, right-aligned, confirmation dialog,
  undo toast after).

### Keyboard and accessibility
- ⌘F focuses search; ⌘⌫ deletes the selected meeting (with confirm);
  Return renames; arrows move list selection.
- Every control labeled for VoiceOver; transcript rows read as
  "speaker, time, text". Focus order matches visual order.
- Dynamic Type respected; timestamps never truncate (fixed column).

### Storage
`MeetingStore` (Core Data, like `HistoryStore`): title, date, calendar
event id, duration, template, typed notes, transcript segments, summary,
bot thread id. Raw audio is discarded by default after transcription
(privacy; Granola does the same). Optional keep-audio setting later.

## The normal tools
- Pause / resume capture.
- Meetings list in the History window: search (title + transcript),
  open, rename, delete.
- Detail view: summary, user notes, full transcript with Me/Them labels,
  "Open in OpenMausBot" for follow-up questions.
- Copy summary / copy transcript / export Markdown.
- Templates: General, 1:1, Standup, Interview, Sales, Custom (free text).
- Settings: calendars to watch, auto-popup on/off, default template,
  summary bot selection.

## Permissions (new)
| Permission | Why | When asked |
|---|---|---|
| Screen Recording (TCC) | ScreenCaptureKit system-audio capture | First manual meeting start |
| Calendar full access | Event watcher + popup | When enabling calendar connection in Settings |

Mic permission already exists.

## Phases
1. **Capture + transcribe (1-2 days).** Manual start/stop from menu bar.
   System audio + mic, interleaved sliding-window transcription, meeting
   stored, transcript viewable. This proves the audio pipeline.
2. **Summary to OpenMausBot (0.5 day).** Meetings bot auto-created,
   post + await + store, reply bubble. Mostly existing `MausClient`.
3. **Calendar popup (1 day).** EventKit watcher, pill meeting face,
   one-click start.
4. **Tools polish (1-2 days).** Notes window, templates, history UI,
   export, settings.

## Decided
- Transcripts stay local, shown in the Meetings page of Settings.
  OpenMausBot receives a meeting only when the user clicks Send to
  summary (the transcript goes along in that message so the bot can
  summarize it; nothing is sent automatically).
- Summaries go to a dedicated Meetings bot.
- Diarization is in scope: Me/Them from the streams, Them split by
  voice, names mapped from calendar attendees when context allows.

## Open questions
1. Auto-stop behavior: end capture automatically when the meeting app
   goes quiet, or always require an explicit End click?
2. Multi-display/multi-app calls: capture all system audio (simple,
   catches music too) or only the meeting app's audio (cleaner, needs
   app detection)? v1 proposal: all system audio.
