import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

@main
struct MurmurApp: App {
    private let container: ModelContainer
    private let services: AppServices

    init() {
        do {
            container = try MurmurSchema.makeContainer()
        } catch {
            fatalError("Could not create the Murmur data store: \(error)")
        }
        services = AppServices(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

/// Chooses the first screen. Launch arguments exist so CI can screenshot specific screens:
///   `-screen gallery -gallerySection N`   component gallery scrolled to section N
///   `-screen recording` / `recordingPaused`   record screen with a fake microphone
///   `-screen modelDownload` / `modelDownloading` / `modelDone`   model download screen (fake downloader)
///   `-screen transcribing` / `transcribingDone`   transcribing screen with sample text
///   `-screen library` / `libraryEmpty`   library with demo notes / first-run state
///   `-screen import` / `export`   import queue and export sheet (demo data)
///   `-screen note` / `noteEdit`   note with playback running / edit transcript (demo data)
/// With no argument the app shows the normal home screen.
struct RootView: View {
    let services: AppServices

    var body: some View {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "gallery":
            ComponentGallery(initialSection: UserDefaults.standard.integer(forKey: "gallerySection"))
        case "recording":
            DemoRecordingHost(startPaused: false)
        case "recordingPaused":
            DemoRecordingHost(startPaused: true)
        case "modelDownload":
            DemoModelDownloadHost(mode: .choosing)
        case "modelDownloading":
            DemoModelDownloadHost(mode: .downloading)
        case "modelDone":
            DemoModelDownloadHost(mode: .done)
        case "library":
            DemoLibraryHost(empty: false)
        case "libraryEmpty":
            DemoLibraryHost(empty: true)
        case "import":
            DemoImportHost()
        case "export":
            DemoExportHost()
        case "note":
            DemoNoteHost(edit: false)
        case "paywall":
            DemoPaywallHost()
        case "noteLocked":
            DemoNoteHost(edit: false, locked: true)
        case "search":
            DemoSearchHost()
        case "dictionary":
            DemoDictionaryHost()
        case "findReplace":
            DemoFindReplaceHost()
        case "summary":
            DemoNoteHost(edit: false, summaryTab: true)
        case "noteEdit":
            DemoNoteHost(edit: true)
        case "transcribing":
            DemoTranscribingScreen(done: false)
        case "transcribingDone":
            DemoTranscribingScreen(done: true)
        case "onboarding":
            OnboardingScreen(requestMicrophone: {}, onFinish: {})
        case "onboardingMic":
            OnboardingScreen(startAt: 3, requestMicrophone: {}, onFinish: {})
        case "settings":
            DemoSettingsHost()
        default:
            HomeGate(services: services)
        }
    }
}

/// The first launch shows onboarding; after that, the library.
struct HomeGate: View {
    let services: AppServices

    var body: some View {
        if services.settings.hasCompletedOnboarding {
            LibraryScreen(deps: services.libraryDependencies)
        } else {
            OnboardingScreen(
                requestMicrophone: { await services.requestMicrophone() },
                onFinish: { services.settings.completeOnboarding() }
            )
        }
    }
}
