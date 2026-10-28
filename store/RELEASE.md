# Releasing Murmur

Notes for the owner. The release workflow (`.github/workflows/release.yml`) has never run: it needs
your Apple Developer account first, and the first real run will probably need small fixes.

## Done so far (October 28, 2026)

The bundle ID `app.murmur.Murmur` was already taken, so the app uses `com.appyzone.murmur`.
- Developer portal: the three App IDs, App Group `group.com.appyzone.murmur` and iCloud container `iCloud.com.appyzone.murmur` exist and are linked. (An unused group `group.app.murmur.Murmur` was also created; delete it.)
- App Store Connect: app "Murmur: Private Transcription" (iOS and macOS, Apple ID 6827877311), subscription group "Murmur Pro" with Pro Yearly $19.99 and Pro Monthly $3.99, and the Pro Lifetime non-consumable $39.99, all available in all countries, product IDs `app.murmur.pro.yearly|monthly|lifetime`.
- Pro Yearly has a free introductory offer of 3 days in all countries (Apple's shortest free trial; 1 day is not offered). The Paid Apps agreement and tax details were completed by the owner.
- Release workflow works (October 28, 2026): the first iOS build (with the Watch app) was uploaded to App Store Connect from `Release (manual)`. It needed an **Admin** API key (App Manager gives a "Cloud signing permission error"); secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (raw `.p8` text or base64 both work). The run's log is published to the `release-results` branch. Fixed on the way: Watch background audio is `UIBackgroundModes`, iPad needs all four orientations, `LSSupportsOpeningDocumentsInPlace` is set.
- Store listing translations (October 28, 2026): Spanish (Mexico), German, French and Portuguese (Brazil) added in App Store Connect from `store/localized_listings.py` / `store/listing-localized.md` (limits and keyword overlap checked by the script). The app screens are English only and each description says so. Have a native speaker review them. Later: localize the app UI (strings) for the best languages, then add more listings.
- Old open items (API access and key are done): request App Store Connect API access (Users and Access > Integrations; needs the account holder to accept terms), create the API key and add the GitHub secrets, add a review screenshot to each product, upload screenshots (`tools/make_screenshots.py`), upload a build.

## One-time setup in your Apple Developer account

1. Register the App IDs (Certificates, Identifiers & Profiles):
   - `com.appyzone.murmur` (iOS and macOS share it): capabilities **iCloud (CloudKit)**, **Push Notifications**, **App Groups**, **In-App Purchase**.
   - `com.appyzone.murmur.watchkitapp` and `com.appyzone.murmur.watchkitapp.widget`: **App Groups**.
   - App Group `group.com.appyzone.murmur`, iCloud container `iCloud.com.appyzone.murmur`.
   If you choose a different bundle ID, change `PRODUCT_BUNDLE_IDENTIFIER` and `WKCompanionAppBundleIdentifier` in `project.yml`, the product IDs in `Plans.swift`, and `ICloudSync.containerIdentifier`.
2. Create the app in App Store Connect with that bundle ID.
3. Create the three in-app purchases (IDs in `store/listing.md`).
4. In the CloudKit Dashboard, open the container, run the app once from Xcode against the **Development** environment with iCloud sync turned on and a note created, then **Deploy Schema Changes to Production**. Sync does not work in TestFlight or App Store builds until this is done.
5. Create an App Store Connect API key (Users and Access > Integrations > App Store Connect API, role App Manager) and add the four secrets listed at the top of the workflow.

## Shipping

- Run the **Release (manual)** workflow, choose `ios` (includes the Watch app) and later `mac`. The build appears in TestFlight after processing.
- The Mac App Store build is signed and distributed by Apple, so it needs **no notarization**. Notarization (Developer ID, `xcrun notarytool`) is only needed if you ever hand out a Mac build outside the App Store.
- Fill the listing from `store/listing.md`, upload screenshots, add the build, submit for review.

## Every release

- Bump `MARKETING_VERSION` in `project.yml` (the workflow sets the build number).
- Test on real devices first: the lists at the end of `CLAUDE.md` say what only a device can check.
