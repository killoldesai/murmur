# Murmur

On-device speech-to-text app (Whisper) for iPhone, iPad, Mac and Apple Watch. US market, English UI first. Native SwiftUI. No backend, no accounts: audio and text never leave the device.

## Status

Design and specs are done. Coding started on the owner's go-ahead.

- **Done: build step 0.** `MurmurTheme` (tokens), `MurmurMotion` (entrance, press), shared components (PrimaryButton, SecondaryButton, Chip, NoteCard, TranscriptRow, PlaybackBar, Waveform, ProgressRing, PlanCard, SettingsRow) and `ComponentGallery`, in `Sources/MurmurUI`. `MurmurCore` has `Timecode`. Unit tests pass in CI and the screenshots match the design.
- **Next:** spec "Build order" step 1 (SwiftData models), then step 2 (AudioRecorder and the record screen).
- The root screen of the app is still the component gallery. Replace it as real screens land.

Project layout: `Package.swift` (MurmurCore, MurmurUI), `project.yml` (XcodeGen spec for the iOS app; the `.xcodeproj` is generated, never committed), `App/Murmur/` (app target sources).

## Where things are

- `docs/specs/iphone-ipad-spec.md` build this first; it defines the shared package.
- `docs/specs/mac-spec.md` and `docs/specs/watch-spec.md` come after the iPhone app works.
- `docs/design/` is the source of the clickable design canvas (47 screens + icons). `canvas.json` indexes it; each screen is a `.dc.html` file in `iphone/`, `ipad/`, `mac/`, `watch/`. Read the file for a screen before building it: it has exact sizes, colours, copy and animation timings.
- Published design: https://claude.ai/artifact/CfxNqHbNuKs3RusaMefkKn

## Naming

The specs were written under an earlier working name. Use:

- `MurmurCore` (Swift package, no UI), not `LoroCore`
- `Murmur` (iOS/iPadOS app target), `MurmurMac`, `MurmurWatch`, `MurmurWatchWidget`

## Design rules (non-negotiable)

- Solid, flat style. **No gradients, glows, blur or glass.**
- Dark appearance only for the MVP.
- All colours, type and spacing live in one `MurmurTheme` file. Screens never hard-code values. Build `MurmurTheme` and the shared components first (spec "Build step 0"), with SwiftUI previews.
- Motion: entry rise + stagger, press scale 0.96, pulsing record button, live waveform. All motion off under Reduce Motion.
- Tap targets at least 44 pt. Support Dynamic Type and VoiceOver.

## Engineering rules

- Business logic goes in `MurmurCore` with unit tests. Views contain no logic.
- Platform-specific code behind `#if os(...)`.
- Engine: WhisperKit (large-v3-turbo; Small model as the lighter option). Ask before adding any other dependency.
- Ask before changing the SwiftData schema (shared across iPhone, iPad, Mac; a bad migration loses user notes).
- No network calls except the model download and StoreKit.
- Commit after each build step.

## Environment constraints

Development happens in a Linux cloud session with no Xcode. Code cannot be compiled or run locally. Verification is done by GitHub Actions on a macOS runner (`.github/workflows/ci.yml`): read the run logs and simulator screenshots, fix, push again.

- **Reading CI results from the cloud session:** Actions logs and artifacts are NOT downloadable here (the sandbox blocks GitHub's blob storage). Instead the last CI step force-pushes logs, a `summary.txt` and simulator screenshots to the `ci-results` branch. To read them:
  `git fetch origin ci-results && mkdir -p /tmp/claude-0/ci && git --work-tree=/tmp/claude-0/ci checkout FETCH_HEAD -- . && git reset -q`
  then read `summary.txt`, `swift-test.log`, `xcodebuild.log` and view `gallery-N.png` with the Read tool. Poll run status with `gh api repos/killoldesai/murmur/actions/runs/<id> --jq '"\(.status) \(.conclusion)"'` (a run takes about 5 minutes).
- The app accepts a `-gallerySection N` launch argument (scrolls the component gallery); CI uses it to screenshot each section. Extend this pattern (launch arguments that jump to a screen) so CI can screenshot every new screen.
- Only a physical device can verify: real microphone, Whisper speed on the Neural Engine, background recording, battery, Watch-to-iPhone transfer. Say so explicitly and list what to test by hand; never claim these work.
- Simulators are too slow for large Whisper; use the Small model in CI.
- Secrets (signing certificates, App Store Connect keys) go in GitHub Secrets only. The repo is public: never commit credentials.

## Pricing (placeholders)

$19.99/year with 7-day trial, $39.99 lifetime, $3.99/month. Real prices are set in App Store Connect.
