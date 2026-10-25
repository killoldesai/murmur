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
            // `-gallerySection N` launch argument scrolls to section N (used by CI screenshots).
            ComponentGallery(initialSection: UserDefaults.standard.integer(forKey: "gallerySection"))
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
