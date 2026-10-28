# App Store listing: Murmur

Everything App Store Connect asks for, ready to paste. Character limits are Apple's; the counts
below were checked by `store/check_listing.py`. Prices are placeholders (set the real ones in
App Store Connect). One listing covers iPhone, iPad, Mac and Apple Watch (universal purchase,
same bundle ID for iOS and Mac).

## Names

| Field | Text | Limit |
|---|---|---|
| App name | `Murmur: Private Transcription` | 30 |
| Subtitle | `Voice to text, on your device` | 30 |
| Promotional text | `Record or import audio and get an accurate transcript in minutes. Whisper runs on your device, so nothing is uploaded. No account needed.` | 170 |
| Keywords | `transcribe,whisper,dictation,voice memo,meeting notes,lecture,audio to text,recorder,offline` | 100 |
| Category | Productivity (primary), Business (secondary) | |
| Copyright | `2026 <your name or company>` | |
| Support URL | https://killoldesai.github.io/murmur/ | |
| Marketing URL | (optional, leave empty) | |
| Privacy Policy URL | https://killoldesai.github.io/murmur/privacy/ | |
| Terms of Use (custom EULA) | https://killoldesai.github.io/murmur/terms/ | |

Do not repeat the app name or category words in the keywords field (Apple already indexes them).

## Description

```
Turn speech into text without sending it anywhere.

Murmur records meetings, lectures and ideas, or imports audio and video you already have, and turns them into an accurate transcript using Whisper running on your own device. There are no servers and no accounts. Your audio and text are never uploaded to us, and Murmur even works in airplane mode after the one-time speech model download.

RECORD OR IMPORT
• Record with one tap, with bookmarks to mark the moments that matter
• Import from Files, or videos from Photos, and queue a whole batch
• Send recordings from your Apple Watch and find them transcribed on your iPhone

READ, SEARCH AND FIX
• Tap any line to play from that moment, and follow along as it plays
• Search every note at once, then find and replace across a transcript
• Edit text, split and merge lines, and label who said what
• Add your own names and jargon to a custom dictionary so they are spelled your way

SUMMARIES THAT STAY PRIVATE
• Meeting, Lecture and Bullet point summaries with action items
• Made on your device with Apple Intelligence (on supported devices)

EXPORT YOUR WAY
• Text, Markdown, subtitles (SRT) or audio
• Share to any app, or copy straight to the clipboard

ON EVERY DEVICE
• iPhone, iPad, Mac and Apple Watch
• Optional iCloud sync keeps your notes, transcripts, folders and dictionary in step across your devices through your own private iCloud. It is off until you turn it on. Audio stays on the device that recorded it.
• On Mac: a menu bar recorder and a global shortcut to start recording from any app

PRIVATE BY DESIGN
No analytics. No ads. No tracking. Murmur downloads its speech model once, then works offline.

MURMUR PRO
Free: the first 2 minutes of every note. Pro unlocks full transcripts, editing, export, find and replace, and summaries for everything you record, including older notes.
• $19.99 per year, with a 3-day free trial
• $39.99 once, for life
• $3.99 per month
Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage them in Settings > Apple ID > Subscriptions.

Terms of Use: https://killoldesai.github.io/murmur/terms/
Privacy Policy: https://killoldesai.github.io/murmur/privacy/
```

## What's New (first release)

```
Welcome to Murmur. Record or import audio and get a private, on-device transcript with summaries, search and export, on iPhone, iPad, Mac and Apple Watch.
```

## In-app purchases (product IDs must match `Plans.swift`)

| Reference name | Product ID | Type | Price | Display name | Description |
|---|---|---|---|---|---|
| Pro Yearly | `app.murmur.pro.yearly` | Auto-renewable, group "Murmur Pro" | $19.99, 3-day free trial (introductory offer) | Murmur Pro Yearly | Full transcripts, editing, export and summaries. Renews every year. |
| Pro Lifetime | `app.murmur.pro.lifetime` | Non-consumable | $39.99 | Murmur Pro Lifetime | Pay once and keep Pro on all your devices. |
| Pro Monthly | `app.murmur.pro.monthly` | Auto-renewable, group "Murmur Pro" | $3.99 | Murmur Pro Monthly | Full transcripts, editing, export and summaries. Renews every month. |

Each product needs a review screenshot: use the paywall screenshot (`-screen paywall`).
Make the lifetime plan available through Family Sharing only if you want that (off by default).

## App Privacy ("nutrition label")

Answer **Data Not Collected**.

Why this is accurate: Murmur has no server, no analytics SDK and no accounts. Audio and text are
processed on the device. With iCloud sync on, notes are stored in the person's own private CloudKit
database, which the developer cannot read, so it is not "collected" under Apple's definition.
The only network traffic is the one-time speech model download (the host sees an IP address, no
user data) and StoreKit.

Check before you submit: Apple's definition is about data sent off the device that you or your
partners can access. If you ever add crash reporting or analytics, this answer changes.

## Age rating

All "None" answers (no user-generated content shared with others, no web access, no gambling,
no mature content). Expected rating: 4+.

## Export compliance

The app uses only encryption built into Apple's operating systems (HTTPS, StoreKit, CloudKit).
`ITSAppUsesNonExemptEncryption` is set to `NO` in the Info.plist of every app target, so TestFlight
and App Review do not ask each time.

## App Review notes

```
Murmur transcribes audio on the device. There is no sign-in and no demo account.

To test:
1. Open the app and finish onboarding. Allow the microphone.
2. The first recording needs the speech model. Choose "Small" (about 500 MB) on the model screen and wait for the download (Wi-Fi). Large v3 Turbo is the recommended option but is larger (about 632 MB).
3. Tap the record button, speak for 20 to 30 seconds, then stop. The note is transcribed on the device.
4. Free notes show the first 2 minutes. To test purchases, use the sandbox products on the paywall (Settings > Murmur Pro).
5. Summaries need a device with Apple Intelligence. On other devices the Summary tab is hidden by design.
6. iCloud sync is optional (Settings > Sync with iCloud) and uses the reviewer's own iCloud account. It is off by default.

Apple Watch: the watch app records and sends the audio to the iPhone, which transcribes it.
Permissions: Microphone only. Photos is used through the system picker when importing a video.
```

## Screenshots

Capture from the real app on devices or simulators of the sizes below (6.9" iPhone, 13" iPad,
Mac, Apple Watch). Dark appearance only. In order, with a suggested caption (large, one line,
no more than 6 words):

| # | Screen | Caption |
|---|---|---|
| 1 | Note with transcript and playback (`-screen note`) | Words you can read and replay |
| 2 | Recording (`-screen recording`) | Record with one tap |
| 3 | Summary with action items (`-screen summary`) | Summaries, made on device |
| 4 | Library with folders (`-screen library`) | Every note in one place |
| 5 | Search (`-screen search`) | Find any word, anywhere |
| 6 | Import queue (`-screen import`) | Import audio and video |
| 7 | Paywall (`-screen paywall`) | Pro, when you want it |

Sizes Apple asks for today: iPhone 6.9" (1320 x 2868), iPad 13" (2064 x 2752), Mac
(2880 x 1800), Apple Watch (as listed in App Store Connect for the newest watch).
Up to 10 per device; at least 1 per device family you support.

## Before you submit

- [ ] Bundle ID, team and signing set; products created with the IDs above.
- [ ] iCloud container `iCloud.com.appyzone.murmur` created; **CloudKit schema deployed to Production** in the CloudKit Dashboard (without this, sync works in development builds only).
- [ ] App Group `group.com.appyzone.murmur` on the iOS app, watch app and watch widget.
- [ ] Support, Privacy and Terms URLs open.
- [ ] Copyright line filled in.
- [ ] Screenshots uploaded for iPhone, iPad, Mac and Watch.
