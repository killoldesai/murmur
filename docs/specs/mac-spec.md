# Murmur: Mac MVP Spec

Oct 25, 2026 · @KD

Paste this doc into Claude after the iPhone app exists. It adds a native macOS target to the same Xcode project, reusing the `LoroCore` package, so Mac users get fast, private transcription of long meetings and lectures. The Mac's edge: Apple Silicon runs Whisper large-v3-turbo much faster than a phone, with no battery or backgrounding limits.

## Goal and constraints

- Native macOS app (SwiftUI, macOS 15+, Apple Silicon only; skip Intel).
- Same Whisper engine, data model, exports, summaries and paywall as iPhone, via `LoroCore`. Do not copy logic into the Mac target.
- Sold as a universal purchase: one unlock covers iPhone, iPad and Mac.
- Notes sync with iPhone through SwiftData and CloudKit (private database, no server cost).

## Project changes

- Add a `LoroMac` target to the existing project; add a macOS platform to `Package.swift`.
- Move any iOS-only code in `LoroCore` (for example `AVAudioSession`) behind `#if os(iOS)` with a macOS equivalent.
- Turn on iCloud with CloudKit for the SwiftData container in all targets, and migrate the existing store safely.
- Share views that work on both platforms (transcript view, summary view, paywall) in a `SharedUI` folder.

## Design

Match the Mac row of the design canvas: [Murmur app design](https://claude.ai/artifact/CfxNqHbNuKs3RusaMefkKn). Use the same `MurmurTheme` tokens and motion rules as the iPhone & iPad spec (solid colors, accent #5EE0C6 on #111116, no gradients or glows), at Mac density: 13 pt body, 30 pt toolbar controls with 8 pt radius, 30 pt sidebar rows with 7 pt radius. Keep motion quieter than iOS: 0.3–0.4 s entries, no press scaling on list rows.

| # | Mac screen | What it must do |
| --- | --- | --- |
| 1 | Main window | Toolbar with Import, search (⌘F) and Record (⌃⌥R); sidebar with library, folders, queue status and Settings; note list; transcript with playback (Space to play) |
| 2 | Note + inspector | Transcript with the playing line highlighted; toggleable inspector with summary, action items, speaker talk time and file info |
| 3 | Recording window | Small floating window with timer, waveform, input picker, bookmark, pause and stop; timer also shown in the menu bar |
| 4 | Menu bar | Dropdown with Start recording, live mini recorder while recording, input, recent notes, Open, Import, Settings, Quit |
| 5 | Drop files | Full-window drop overlay showing how many files will be added |
| 6 | Batch queue | Table of files with length, progress, speed (× real time), Pause queue, totals for done and time left |
| 7 | Export dialog | Sheet with TXT, Subtitles, Audio, Markdown; include options; save location |
| 8 | Paywall | Window with three plan cards and perks; same universal purchase as iOS |
| 9 | Settings: General | Open at login, menu bar icon, record shortcut recorder, default folder, recording format, delete audio, hide Dock icon |
| 10 | Settings: Dictionary | Table of words with type and date, add, remove, import and export lists |
| 11 | Onboarding | Four steps: welcome, microphone, shortcut and menu bar, model download with progress |

## Mac-specific MVP features

1. **Layout**: three-column `NavigationSplitView`: folders sidebar, note list, note detail. Resizable window, remembers its size.
2. **Record**: microphone recording from a menu bar item (start and stop without opening the window) and a global shortcut (default Control+Option+R).
3. **Import by drag and drop**: drop audio or video files onto the window or the Dock icon. Batch queue with progress, several files in a row.
4. **Faster transcription**: use the larger batch settings on Apple Silicon and show real-time-factor in the progress UI.
5. **Keyboard shortcuts**: Command+N new recording, Command+F search, Command+E export, space to play and pause, arrow keys to move between segments.
6. **Export**: TXT, SRT, Markdown and the original audio, with speaker, timestamp and summary options, plus "Reveal in Finder" and drag a note out as a file.
7. **Menu bar app** and standard Mac menus (File, Edit, View, Window, Help). Settings in a Preferences window.
8. **Same paywall and entitlement** as iPhone; restore on launch.

## Out of scope for MVP

System audio or meeting capture (needs ScreenCaptureKit and extra permissions, plan as a V2 feature), speaker identification, Intel Macs, Mac App Store alternatives such as direct download.

## Build order

1. Make `LoroCore` compile for macOS; fix platform differences.
2. Create the `LoroMac` target with the split view reading the shared SwiftData store.
3. Port the note detail and playback.
4. Recording and the menu bar item.
5. Drag and drop import and the batch queue.
6. Keyboard shortcuts and menus.
7. Enable CloudKit sync; test iPhone to Mac and back.
8. App Sandbox entitlements (microphone, user-selected files, network for the model download), then notarization and Mac App Store submission.

## Acceptance criteria

- A 60-minute recording transcribes in under 10 minutes on an M1.
- A note recorded on iPhone appears on the Mac within a minute of both being online.
- Dropping 5 files queues all of them and finishes without freezing the UI.
- The app passes App Sandbox review with only the entitlements it needs.
- The same purchase unlocks both apps.

## Notes for Claude

- Reuse before rewriting: if you need new logic, add it to `LoroCore` with a test, then call it from both apps.
- Ask me before changing the SwiftData schema, because it is shared with the iPhone app and a bad migration loses user notes.

* Naming: use `MurmurCore` and a `MurmurMac` target wherever this spec says `LoroCore` or `LoroMac`.
* The Markdown export and the queue's "× real time" speed figure are new from the design; add both to `MurmurCore` so iOS can reuse them.
