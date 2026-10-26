import Foundation
import Observation

public struct OnboardingPage: Equatable, Sendable {
    public let title: String
    public let body: String
    /// SF Symbol for the illustration.
    public let symbol: String

    /// The same page worded for one line and another device, e.g. "Your words stay on your iPad".
    public func worded(forDevice device: String) -> OnboardingPage {
        OnboardingPage(
            title: title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "iPhone", with: device),
            body: body.replacingOccurrences(of: "iPhone", with: device),
            symbol: symbol
        )
    }
}

/// Three feature pages, then the microphone explanation.
@MainActor
@Observable
public final class OnboardingController {
    public static let pages: [OnboardingPage] = [
        OnboardingPage(title: "Your words stay\non your iPhone",
                       body: "Every recording is transcribed on-device. No servers, no accounts, nothing uploaded.",
                       symbol: "lock.fill"),
        OnboardingPage(title: "Works with\nno internet",
                       body: "Record and transcribe anywhere, in 100+ languages. Wi‑Fi is only needed once, to download the speech model.",
                       symbol: "wifi.slash"),
        OnboardingPage(title: "Summaries and\naction items",
                       body: "Label who said what, then get a summary and action items. All generated on your device.",
                       symbol: "text.badge.checkmark")
    ]

    /// 0 to 2 are feature pages; `pages.count` is the microphone step.
    public private(set) var index: Int

    public init(startAt index: Int = 0) {
        self.index = min(max(index, 0), Self.pages.count)
    }

    public var isMicrophoneStep: Bool { index >= Self.pages.count }
    public var page: OnboardingPage? { isMicrophoneStep ? nil : Self.pages[index] }
    /// Number of dots under the feature pages.
    public var pageCount: Int { Self.pages.count }

    public func next() {
        if index < Self.pages.count { index += 1 }
    }

    /// Tapping a card on the iPad jumps to that page. Ignored outside the feature pages.
    public func select(_ page: Int) {
        guard Self.pages.indices.contains(page) else { return }
        index = page
    }

    /// Skip jumps straight to the microphone step, which still has to be shown.
    public func skip() {
        index = Self.pages.count
    }
}
