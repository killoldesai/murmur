# Murmur

On-device speech-to-text app (Whisper) for iPhone, iPad, Mac and Apple Watch. US market, English UI first. Native SwiftUI. No backend, no accounts: audio and text never leave the device.

## Status

Design and specs are done. **No app code is written yet.** Do not start coding until the owner says to. When they do, follow the build order in the specs.

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

- Only a physical device can verify: real microphone, Whisper speed on the Neural Engine, background recording, battery, Watch-to-iPhone transfer. Say so explicitly and list what to test by hand; never claim these work.
- Simulators are too slow for large Whisper; use the Small model in CI.
- Secrets (signing certificates, App Store Connect keys) go in GitHub Secrets only. The repo is public: never commit credentials.

## Pricing (placeholders)

$19.99/year with 7-day trial, $39.99 lifetime, $3.99/month. Real prices are set in App Store Connect.
