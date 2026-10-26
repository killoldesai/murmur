import Foundation

/// The three ways to unlock Murmur Pro. Product IDs are placeholders: they must match the
/// products created in App Store Connect.
public enum Plan: String, CaseIterable, Identifiable, Sendable {
    case yearly, lifetime, monthly

    public var id: String { rawValue }
    public var productID: String { "app.murmur.pro.\(rawValue)" }

    public var title: String {
        switch self {
        case .yearly: "Yearly"
        case .lifetime: "Lifetime"
        case .monthly: "Monthly"
        }
    }

    public var isSubscription: Bool { self != .lifetime }

    /// Shown until the App Store returns the real price.
    public var placeholderPrice: String {
        switch self {
        case .yearly: "$19.99"
        case .lifetime: "$39.99"
        case .monthly: "$3.99"
        }
    }

    /// Order of value, for picking the best plan someone owns.
    var rank: Int {
        switch self {
        case .lifetime: 3
        case .yearly: 2
        case .monthly: 1
        }
    }
}

public struct PlanOffer: Equatable, Identifiable, Sendable {
    public let plan: Plan
    public let displayPrice: String
    /// "$1.67" for the yearly plan.
    public let monthlyEquivalent: String?
    public let trialDays: Int?
    /// `false` for the placeholder shown while the App Store has not answered.
    public let isAvailable: Bool

    public var id: String { plan.id }

    public init(plan: Plan, displayPrice: String, monthlyEquivalent: String? = nil, trialDays: Int? = nil, isAvailable: Bool = true) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.monthlyEquivalent = monthlyEquivalent
        self.trialDays = trialDays
        self.isAvailable = isAvailable
    }

    public static func placeholder(_ plan: Plan) -> PlanOffer {
        PlanOffer(plan: plan, displayPrice: plan.placeholderPrice,
                  monthlyEquivalent: plan == .yearly ? "$1.67" : nil,
                  trialDays: plan == .yearly ? 7 : nil, isAvailable: false)
    }

    /// Second line on the plan card.
    public var detail: String {
        switch plan {
        case .yearly:
            var parts: [String] = []
            if let monthlyEquivalent { parts.append("\(monthlyEquivalent) a month") }
            if let trialDays { parts.append("\(trialDays)-day free trial") }
            return parts.isEmpty ? "Billed yearly" : parts.joined(separator: " · ")
        case .lifetime: return "Pay once, yours forever"
        case .monthly: return "Cancel anytime"
        }
    }

    public var badge: String? {
        switch plan {
        case .yearly: "BEST VALUE"
        case .lifetime: "ONE-TIME"
        case .monthly: nil
        }
    }

    /// Text on the main button.
    public var callToAction: String {
        switch plan {
        case .yearly:
            if let trialDays { return "Start \(trialDays)-day free trial" }
            return "Subscribe · \(displayPrice)/year"
        case .lifetime: return "Unlock forever · \(displayPrice)"
        case .monthly: return "Continue · \(displayPrice)/month"
        }
    }
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased, cancelled, pending
}

/// The App Store, behind a protocol so tests and CI screenshots can use a fake.
public protocol PurchaseStore: Sendable {
    func offers() async throws -> [PlanOffer]
    func purchase(_ plan: Plan) async throws -> PurchaseOutcome
    /// Syncs purchases with the App Store (may ask the person to sign in).
    func restore() async throws
    /// Plans the person owns right now.
    func activePlans() async -> Set<Plan>
    /// Emits whenever a purchase, renewal, refund or restore changes what is owned.
    func updates() -> AsyncStream<Void>
}

/// What the free version allows: the first two minutes of each note.
public enum FreeTier {
    public static let freeSeconds: TimeInterval = 120

    /// The part of a transcript a free user can read (everything for Pro).
    public static func visible(_ segments: [TranscriptSegment], isPro: Bool) -> [TranscriptSegment] {
        isPro ? segments : Array(segments.prefix { $0.start < freeSeconds })
    }

    public static func lockedCount(_ segments: [TranscriptSegment], isPro: Bool) -> Int {
        segments.count - visible(segments, isPro: isPro).count
    }

    public static func lockedText(duration: TimeInterval) -> String {
        let minutes = max(1, Int(((duration - freeSeconds) / 60).rounded()))
        return "About \(minutes) more minute\(minutes == 1 ? "" : "s") of this note \(minutes == 1 ? "is" : "are") locked."
    }
}
