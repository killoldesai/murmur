# Releasing Murmur

Notes for the owner. The release workflow (`.github/workflows/release.yml`) has never run: it needs
your Apple Developer account first, and the first real run will probably need small fixes.

## One-time setup in your Apple Developer account

1. Register the App IDs (Certificates, Identifiers & Profiles):
   - `app.murmur.Murmur` (iOS and macOS share it): capabilities **iCloud (CloudKit)**, **Push Notifications**, **App Groups**, **In-App Purchase**.
   - `app.murmur.Murmur.watchkitapp` and `app.murmur.Murmur.watchkitapp.widget`: **App Groups**.
   - App Group `group.app.murmur.Murmur`, iCloud container `iCloud.app.murmur.Murmur`.
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
