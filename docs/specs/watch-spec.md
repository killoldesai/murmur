# Murmur: Apple Watch MVP Spec

Oct 25, 2026 · @KD

Paste this doc into Claude after the iPhone app works. It adds a small watchOS companion that records voice memos from the wrist and hands them to the iPhone for transcription. The watch never runs Whisper; it only records and syncs. Keep it tiny and reliable.

## Goal and constraints

- watchOS 11.6+ app paired with the iPhone app (a companion target in the same Xcode project).
- The watch records and stores audio only. The iPhone transcribes when the file arrives.
- Reuse `LoroCore` for shared models and file naming; the watch target must stay small and import only what it needs.
- No standalone purchase: the Watch app works if the iPhone app is unlocked, and shows a locked state otherwise.

## Project changes

- Add a `LoroWatch` watchOS App target and a `LoroWatchWidget` target for complications.
- Add a shared `WatchTransfer` type in `LoroCore` describing a recording (id, createdAt, duration, filename).
- Add the Watch Connectivity session on both sides: `WCSession` on the iPhone and the watch.

## Design

Match the Apple Watch row of the design canvas: [Murmur app design](https://claude.ai/artifact/CfxNqHbNuKs3RusaMefkKn). Pure black background (#000000) for OLED, cards in #1C1C23, the same accent #5EE0C6 and record red #FF5A6E. Full-width capsule buttons at least 44 pt tall. Motion stays small: a pulsing record button, live bars while recording, a checkmark that draws itself on save. Respect Reduce Motion.

| # | Watch screen | What it must do |
| --- | --- | --- |
| 1 | Home | Big pulsing record button; Recent row showing how many recordings are waiting for the iPhone |
| 2 | Recording | Counting timer, live bars from the mic level, pause and stop |
| 3 | Saved & sending | Checkmark draws in, "Sending to iPhone" with progress, then "On iPhone · transcribing" |
| 4 | Recent | Last recordings with Delivered (check) or Waiting (spinner) status |
| 5 | Playback | Play and pause inside a progress ring, elapsed and total time |
| 6 | Locked | Shown when Pro isn’t unlocked: lock icon and "Open on iPhone" |
| 7 | Complications | Circular (waveform icon, or notes-today count), Rectangular (tap to record, last memo status), Smart Stack widget (record button and two recent memos) |

## MVP features

1. **Record**: one big Record and Stop button, a running timer and a simple level indicator. Recording continues with the wrist down (background audio session).
2. **Save locally**: write an m4a (AAC, 16 kHz mono is enough for speech) to the watch's storage; keep it until the iPhone confirms receipt.
3. **Sync to iPhone**: send the file with `WCSession.transferFile` plus metadata. This queues automatically and delivers when the phone is in range. Show a status on each recording: Waiting, Sending, Delivered.
4. **iPhone side**: on receipt, create a `Note` marked as "From Watch" and queue it for transcription. The iPhone shows a banner when new watch recordings are ready.
5. **Recent list**: the last 10 recordings with date, duration and status. Tap to play back on the watch.
6. **Complication and Smart Stack widget**: tap to start recording immediately (Accessory circular, rectangular and corner). Also support the Action button on Apple Watch Ultra.
7. **Locked state**: if the iPhone app is not unlocked, show "Unlock on iPhone" instead of recording.

## Out of scope for MVP

On-watch transcription, standalone cellular upload, speaker labels, editing text on the watch, a separate watch purchase.

## Build order

1. Add the watch target and a stub screen that builds and runs in the simulator pair.
2. Implement recording with `AVAudioRecorder` and save the m4a.
3. Implement `WCSession` on both sides; send a test file and confirm receipt on the iPhone.
4. Wire receipt to a new `Note` and the existing transcription queue.
5. Add delivery status and the recent list.
6. Build the complication, Smart Stack widget and Action button.
7. Test on a real watch for background recording and battery.

## Acceptance criteria

- Recording starts within 1 second of tapping the complication.
- A 30-minute recording on the watch survives a wrist-down screen sleep and finishes intact.
- A recording made with the phone out of range arrives on the iPhone within a minute of reconnecting, and is never lost or duplicated.
- The watch app uses under 5% battery per 10 minutes of recording.
- Deleting a delivered recording on the watch frees its storage.

## Notes for Claude

- Prefer `transferFile` over `sendMessage`: files need guaranteed, queued delivery.
- Use the recording id as an idempotency key so retries never create duplicate notes.
- The simulator cannot test background recording or real Bluetooth sync; say so and tell me exactly what to test on hardware.

* Naming: use `MurmurCore` and a `MurmurWatch` target wherever this spec says `LoroCore` or `LoroWatch`.
* The design adds a notes-today circular complication and a "waiting for iPhone" count on Home; both read from the shared `WatchTransfer` queue.
