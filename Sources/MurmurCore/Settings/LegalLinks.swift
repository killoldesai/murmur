import Foundation

/// Public pages for the policies, hosted with GitHub Pages from this repo's `docs/` folder.
/// If the pages move (for example to your own domain), change them here and in App Store Connect.
public enum LegalLinks {
    public static let home = URL(string: "https://killoldesai.github.io/murmur/")!
    public static let privacy = URL(string: "https://killoldesai.github.io/murmur/privacy/")!
    public static let terms = URL(string: "https://killoldesai.github.io/murmur/terms/")!

    /// What the paywall must say about auto-renewing subscriptions (App Store guideline 3.1.2).
    public static let subscriptionNotice =
        "Yearly and monthly plans renew automatically until you cancel in Settings › Apple ID › Subscriptions. Payment is charged to your Apple ID. Lifetime is a one-time purchase."
}
