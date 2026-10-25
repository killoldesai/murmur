import SwiftUI
import MurmurUI

@main
struct MurmurApp: App {
    var body: some Scene {
        WindowGroup {
            // Build step 0: the component gallery is the root screen until real screens exist.
            ComponentGallery()
                .preferredColorScheme(.dark)
        }
    }
}
