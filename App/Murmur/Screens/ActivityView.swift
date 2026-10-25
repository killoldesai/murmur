import SwiftUI
import UIKit

/// The system share sheet for a file.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a file URL can drive `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
