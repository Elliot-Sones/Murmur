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
2. Murmur posts to the dedicated **Meetings** bot in OpenMausBot:
   meeting title, date, attendees (from the event), the user's typed
   notes, the template, and the full transcript.
3. The bot's reply is the polished summary. It appears in the reply
   bubble (click opens OpenMausBot) and is saved with the meeting.
4. The meeting (transcript + notes + summary) is stored locally.

## Architecture

### Audio capture (the hard part Granola solved)
Two simultaneous streams:
- **Mic** (you): existing `AudioRecorder` path, 16 kHz mono Float32.
- **System audio** (everyone else): ScreenCaptureKit `SCStream` audio-only
  capture (macOS 13+). Captures all output audio; a per-app filter can
  target Zoom/Meet/Teams/browser when identifiable. Requires the Screen
  Recording permission (one-time TCC prompt; audio capture rides on it).

Streams are resampled to 16 kHz mono and kept separate for "Me" / "Them"
attribution (Granola-level attribution, not full diarization).

### Transcription
Reuse the Parakeet sliding-window engine. Two constraints shape this:
- **One inference at a time.** FluidAudio's global MLMultiArray cache
  cannot survive concurrent inference (the crash we fixed). Both streams'
  windows are processed through the existing inference slot in
  `FluidAudioTranscriber`, interleaved: mic window, system window, mic
  window. At ~130 ms per 11 s window this is ~2.4% duty cycle for a
  two-stream meeting. Dictation stays usable mid-meeting; its passes just
  share the same slot.
- **Memory.** One hour of 16 kHz mono Float32 is ~230 MB per stream.
  The sliding-window session already consumes samples as it confirms
  windows; capture buffers drop audio once its window is confirmed.
  Confirmed text (with stream tag + timestamps) appends to disk as it
  arrives, so a crash mid-meeting loses at most the current window.

Transcript model: ordered segments `{ start, end, source: me|them, text }`,
merged by timestamp for display and for the summary prompt.

### Calendar
- EventKit with full-access calendar permission.
- Watcher lists events in the next 24 h across selected calendars
  (Settings: calendar picker, same as Granola).
- Trigger rule: event starts within 60 s, has ≥1 other attendee OR a
  video-conference URL. All-day events never trigger.

### Summary via OpenMausBot
- A dedicated **Meetings** bot (auto-created like the Murmur bot, with a
  system description tuned for note-taking: structure, action items,
  decisions; keep the user's own notes verbatim as anchors).
- Payload is one message: metadata header + user notes + transcript.
  Long transcripts chunk into sequential messages if they exceed the
  message size the harness accepts (measure; chunk at ~30k chars).
- The reply is parsed as the summary. `MausClient` already covers bots,
  messages, and reply-await; only chunking is new.
- Every meeting is one thread-visible exchange, so the OpenMausBot
  thread doubles as the meetings archive with follow-up Q&A for free
  ("what did we decide about pricing last week?").

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

## Open questions
1. Which OpenMausBot agent should summarize: a new dedicated Meetings
   bot (recommended, keeps a clean archive thread) or an existing one?
2. Should the transcript itself go into OpenMausBot (searchable there,
   but large), or only the summary, with the transcript staying local?
3. Auto-stop behavior: end capture automatically when the meeting app
   goes quiet, or always require an explicit End click?
4. Multi-display/multi-app calls: capture all system audio (simple,
   catches music too) or only the meeting app's audio (cleaner, needs
   app detection)? v1 proposal: all system audio.
