# Murmur: iPhone & iPad MVP Spec

Oct 25, 2026 · @KD

Paste this doc into Claude (Claude Code or chat) as the first message to build the iPhone app: a private, on-device speech-to-text recorder, sold with a free trial plus subscription or lifetime unlock. Build this first. The Mac and Watch specs reuse the `LoroCore` Swift package defined here.

## Goal and constraints

- Record or import audio, transcribe it fully on-device with Whisper, and let the user edit, summarize and export the text.
- Native SwiftUI, iOS 18.6+, iPhone 13 or later. US market, English UI first.
- No backend. No account. Audio and text never leave the phone (privacy is the pitch).
- Open-source engine: WhisperKit (CoreML) with the `large-v3-turbo` model, downloaded on first launch (not bundled) to keep the install small.

## Project structure

- `LoroCore` (Swift Package, no UI): `TranscriptionEngine` protocol and WhisperKit implementation, `AudioRecorder`, `NoteStore` (SwiftData models), `Exporter` (TXT, SRT), `SummaryService` (Apple Foundation Models), `Entitlements` (StoreKit 2).
- `LoroApp` (iOS target): SwiftUI views only. No business logic inside views.
- Keep platform code behind `#if os(iOS)`, so the same package builds for macOS and watchOS later.

## Data model (SwiftData)

- `Note`: id, title, createdAt, duration, audioFileURL (optional), transcript (text), segments (array of start, end, text), folderID, language.
- `Folder`: id, name.
- `DictionaryWord`: id, term (custom vocabulary, passed to Whisper as a prompt).

## Design

Build the screens to match the design canvas: [Murmur app design](https://claude.ai/artifact/CfxNqHbNuKs3RusaMefkKn). It holds 21 iPhone and 8 iPad screens, each a clickable prototype. The style is solid and flat: no gradients, glows, blur or glass. Dark appearance only for the MVP (`.preferredColorScheme(.dark)`).

Put every value below in one `MurmurTheme` file so screens never hard-code colors.

| Token | Hex | Use |
| --- | --- | --- |
| background | #111116 | Screen background |
| surface | #1C1C23 | Cards, fields, sheets |
| panel | #16161C | iPad sidebars and side panels |
| raised | #26262E | Secondary buttons, progress tracks |
| border | #2A2A33 | 1 pt card and field borders |
| accent | #5EE0C6 | Primary buttons, progress, selection, toggles |
| onAccent | #06231E | Text and icons on accent |
| selectedFill | #16302B | Selected row, plan or segment (with an accent border) |
| record | #FF5A6E | Record, stop, recording dot |
| textPrimary | #F4F3F8 | Titles and body |
| textSecondary | #B9B7C8 | Meta, snippets |
| textTertiary | #8F8D9C | Hints, footnotes |
| folder colors | #5EE0C6, #FFB86B, #A9B4FF, #FF8FA3, #8FD3FF | Folders, note tiles, speakers |

- **Type:** SF Pro (system font). Large title 34 pt heavy, title 28 heavy, headline 17 bold, body 15–16 regular, caption 12–13, section labels 12 bold uppercase with wide tracking. Timers use monospaced digits.
- **Shape:** cards 18–22 pt corner radius, main buttons 56 pt tall with 18 pt radius, chips fully rounded, every tap target at least 44 pt.
- **Components to build once:** `PrimaryButton`, `SecondaryButton`, `Chip`, `NoteCard`, `TranscriptRow` (normal, playing, editing), `PlaybackBar`, `Waveform`, `ProgressRing`, `PlanCard`, `SettingsRow` (value or toggle).

## Motion

Every screen animates on entry, and all motion turns off when Reduce Motion is on (`@Environment(\.accessibilityReduceMotion)`).

| Element | What it does | SwiftUI approach |
| --- | --- | --- |
| Screen entry | Content rises 16 pt and fades in, staggered 50–80 ms per item | `.transition(.move(edge: .bottom).combined(with: .opacity))` with a spring (response 0.5, damping 0.85) and per-index delay |
| Press feedback | Buttons and cards scale to 0.96 | Custom `ButtonStyle` with `scaleEffect` |
| Record button | Gentle pulse, scale 1 to 1.06 over 2.4 s | `repeatForever` animation |
| Live waveform | Bars follow the real mic level | `AVAudioRecorder` metering feeding a `TimelineView` + `Canvas` |
| Recording timer | Solid accent arc spins around the timer; red ring ripples from Stop | `rotationEffect` + `repeatForever`; pauses with the recording |
| Transcribing | Accent progress ring fills; lines of preview text appear one by one | `Circle().trim` bound to progress |
| Playback | The playing line gets the selected fill and accent border, 0.35 s ease; small equalizer bars | Scroll to the current segment with `ScrollViewReader` |
| Checkboxes | Tick pops 0.4 to 1.2 to 1 | Spring scale on a checkmark |
| Toasts | Slide up, hold 2 s, fade | Overlay with `.transition` |
| Sheets and toggles | System sheets and `Toggle` tinted with accent | Built-in |

## Screens

| # | iPhone screen | What it must do |
| --- | --- | --- |
| 1 | Library | Notes grouped by day, search entry, folder link, import and settings buttons, pulsing record button |
| 2 | Recording | Live waveform, counting timer, pause and resume, bookmark, stop leads to Transcribing |
| 3 | Transcribing | Progress ring with time left, live preview lines, "Transcribe later" |
| 4 | Note | Transcript with speaker rows, tap a line to seek, playback bar with speed, links to Edit, Find & replace, Export |
| 5 | Summary | Templates (Meeting, Lecture, Bullet points), summary text, tickable action items, share |
| 6 | Paywall | Yearly, Lifetime, Monthly plans with selection state, Restore purchases |
| 7 | Splash | Icon bars build in, tap to begin |
| 8–10 | Onboarding | Private, Offline, Smart pages with page dots and Skip |
| 11 | Microphone access | Explains privacy before the system prompt |
| 12 | Model download | Choose Large (≈1.6 GB) or Small (≈0.5 GB), Wi‑Fi only toggle, live progress |
| 13 | Folders | Color-coded grid, "New folder" sheet with color picker |
| 14 | Search | Highlighted matches, scope filter (All, Transcripts, Summaries) |
| 15 | Edit transcript | Edit segment text, assign speaker, undo, play, split, merge, delete |
| 16 | Find & replace | Step through matches, Replace or Replace all, option to add the word to the dictionary |
| 17 | Custom dictionary | Add and remove words, tagged as name or term |
| 18 | Export | TXT, SRT, audio or copy, with speaker, timestamp and summary options |
| 19 | Import | Files, Photos, Voice Memos, share-sheet hint, queue with progress |
| 20 | Settings | Pro status, language, model, dictionary, audio format, delete-audio and haptics toggles |
| 21 | Empty library | First-run state with record and import |

| # | iPad screen | What it must do |
| --- | --- | --- |
| 1 | Library | Three columns: sidebar (library, folders, record, import, settings), note list, note detail with playback |
| 2 | Note + summary | Transcript beside a summary panel with action items and speaker talk-time bars |
| 3 | Recording | Large timer and waveform, bookmarks panel that fills as you mark moments |
| 4 | Search | Results list beside a context preview of the selected match |
| 5 | Import | Drag-and-drop zone for Split View, queue panel |
| 6 | Settings | Section list beside a detail pane |
| 7 | Onboarding | Three feature cards with a stepper |
| 8 | Paywall | Perks column beside plan cards |

## MVP features

1. **Record**: big record button, pause and resume, live waveform, auto-save every 3 minutes, background audio so recording continues with the screen locked.
2. **Transcribe**: after stopping, run Whisper with a progress bar. Auto-detect language. Show a clear "keep the app open" notice, and resume if interrupted.
3. **Import**: audio and video (mp3, m4a, wav, mp4, mov) from Files and the share sheet.
4. **Note view**: transcript synced to playback with word-level highlighting, tap a segment to seek, inline editing.
5. **Library**: list of notes, folders, search across all transcripts, swipe to delete.
6. **Summary**: one tap, uses Apple Foundation Models (on-device). Templates: summary, action items, meeting minutes. Hide the button on devices without Apple Intelligence.
7. **Export**: TXT, SRT, share sheet.
8. **Custom dictionary** and **find and replace** in a transcript.
9. **Paywall** (StoreKit 2): first 2 minutes of each note free, then unlock. Products: monthly, yearly, lifetime. Restore Purchases must be visible on the paywall and run automatically on launch.

**Added by the design** (also MVP):

- Bookmarks while recording, listed on the note.
- Model choice at first launch: Large v3 Turbo (≈1.6 GB) or Small (≈0.5 GB), with a Wi‑Fi only toggle. Switchable in Settings.
- Colored folders (5 colors) and a "New folder" sheet.
- Search scopes: All, Transcripts, Summaries.
- Edit transcript: change text, assign speaker manually, split, merge, delete a segment.
- Find & replace offers to add the new word to the custom dictionary.
- Import queue that transcribes files one after another.
- Settings toggles: delete audio after transcribing, haptics.
- iPad: three-column layout and summary side panel (see Screens).
- Paywall prices on the designs ($19.99 yearly with a 7-day trial, $39.99 lifetime, $3.99 monthly) are placeholders. Set real prices in App Store Connect.

## Out of scope for MVP

Automatic speaker identification (the screens show speaker labels: ship manual speaker assignment first, as on the Edit screen, and add auto-detection after launch), widgets, Lock Screen controls, cloud features. The iPad layout is now in scope (8 screens below). iCloud sync arrives with the Mac spec.

## Build order (commit after each step)

1. Create the package and the app; set up SwiftData models.
2. `AudioRecorder` plus the record screen; save an m4a file.
3. WhisperKit integration with model download and a progress UI; transcribe a recorded file and show text.
4. Library, note view, playback sync, editing.
5. Import and export.
6. Summaries.
7. Dictionary and search/replace.
8. StoreKit 2 paywall and entitlement gating.
9. Polish: onboarding with the microphone permission explanation, empty states, dark mode, accessibility (Dynamic Type, VoiceOver).

## Acceptance criteria

- A 10-minute English recording transcribes in under 3 minutes on an iPhone 15.
- Airplane mode works for the whole flow after the first model download.
- Killing the app mid-recording loses at most 3 minutes of audio.
- Memory stays under the system limit with a 1-hour import (process in chunks).
- Purchases restore on a fresh install with the same Apple ID.
- No network calls other than the model download and StoreKit.

## Notes for Claude

- Ask before adding any dependency beyond WhisperKit.
- Prefer small, testable `LoroCore` types with unit tests for `Exporter` and `NoteStore`.
- Test on a physical device; the simulator is too slow for Whisper.

* Naming: the app is **Murmur**. Use `MurmurCore` for the package and `Murmur` for the app target wherever this spec says `LoroCore` or `LoroApp`.
* Build step 0, before anything else: `MurmurTheme` and the shared components from the Design section, with SwiftUI previews of each.
* Open each canvas screen and press Play to see the exact motion before coding that screen.
