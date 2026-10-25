import SwiftUI
import SwiftData
import MurmurCore
import MurmurUI

@main
struct MurmurApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try MurmurSchema.makeContainer()
        } catch {
            fatalError("Could not create the Murmur data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

/// Chooses the first screen. Launch arguments exist so CI can screenshot specific screens:
///   `-screen gallery -gallerySection N`   component gallery scrolled to section N
///   `-screen recording` / `recordingPaused`   record screen with a fake microphone
/// With no argument the app shows the normal home screen.
struct RootView: View {
    var body: some View {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "gallery":
            ComponentGallery(initialSection: UserDefaults.standard.integer(forKey: "gallerySection"))
        case "recording":
            DemoRecordingHost(startPaused: false)
        case "recordingPaused":
            DemoRecordingHost(startPaused: true)
        default:
            DevHomeView()
        }
    }
}
