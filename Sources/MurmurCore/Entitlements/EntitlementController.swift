import Foundation
import Observation

/// Whether the person has Murmur Pro, and the paywall's state.
@MainActor
@Observable
public final class EntitlementController {
    public enum State: Equatable {
        case idle
        case purchasing
        case restoring
        case message(String)
        case failed(String)
    }

    public private(set) var activePlan: Plan?
    public private(set) var offers: [PlanOffer] = Plan.allCases.map(PlanOffer.placeholder)
    public var selected: Plan = .yearly
    public private(set) var state: State = .idle

    @ObservationIgnored private let store: PurchaseStore
    @ObservationIgnored private var started = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    public init(store: PurchaseStore) {
        self.store = store
    }

    deinit { updatesTask?.cancel() }

    public var isPro: Bool { activePlan != nil }
    public var isBusy: Bool { state == .purchasing || state == .restoring }

    public var selectedOffer: PlanOffer {
        offers.first { $0.plan == selected } ?? .placeholder(selected)
    }

    public var callToAction: String { selectedOffer.callToAction }

    /// Run once at launch: reads what is owned (this also picks up purchases restored from the
    /// same Apple ID), loads prices, and keeps listening for changes.
    public func start() async {
        guard !started else { return }
        started = true
        await refreshEntitlements()
        await loadOffers()
        let updates = store.updates()
        updatesTask = Task { [weak self] in
            for await _ in updates {
                await self?.refreshEntitlements()
            }
        }
    }

    public func loadOffers() async {
        guard let loaded = try? await store.offers() else { return }
        offers = Plan.allCases.map { plan in loaded.first { $0.plan == plan } ?? .placeholder(plan) }
    }

    public func refreshEntitlements() async {
        let plans = await store.activePlans()
        activePlan = plans.max { $0.rank < $1.rank }
    }

    public func purchase() async {
        guard !isBusy else { return }
        let offer = selectedOffer
        guard offer.isAvailable else {
            state = .failed("Purchases aren’t available right now. Check your connection and try again.")
            return
        }
        state = .purchasing
        do {
            switch try await store.purchase(offer.plan) {
            case .purchased:
                await refreshEntitlements()
                state = .idle
            case .cancelled:
                state = .idle
            case .pending:
                state = .message("Waiting for approval. Murmur Pro unlocks as soon as it’s approved.")
            }
        } catch {
            state = .failed("The purchase couldn’t be completed. You haven’t been charged.")
        }
    }

    public func restore() async {
        guard !isBusy else { return }
        state = .restoring
        do {
            try await store.restore()
            await refreshEntitlements()
            state = .message(isPro ? "Purchases restored." : "No purchases found for this Apple ID.")
        } catch {
            state = .failed("Purchases couldn’t be restored. Try again.")
        }
    }

    public func dismissMessage() {
        switch state {
        case .message, .failed: state = .idle
        default: break
        }
    }
}

/// A fake store for tests and CI screenshots.
public final class DemoPurchaseStore: PurchaseStore, @unchecked Sendable {
    private let lock = NSLock()
    private var owned: Set<Plan>
    private var continuations: [AsyncStream<Void>.Continuation] = []
    public var offersToReturn: [PlanOffer]?
    public var purchaseOutcome: PurchaseOutcome = .purchased
    public var shouldFail = false
    public var ownedAfterRestore: Set<Plan> = []

    public init(owned: Set<Plan> = []) {
        self.owned = owned
    }

    public func offers() async throws -> [PlanOffer] {
        if shouldFail { throw DemoStoreError.failed }
        return offersToReturn ?? Plan.allCases.map {
            PlanOffer(plan: $0, displayPrice: $0.placeholderPrice,
                      monthlyEquivalent: $0 == .yearly ? "$1.67" : nil, trialDays: $0 == .yearly ? 7 : nil)
        }
    }

    public func purchase(_ plan: Plan) async throws -> PurchaseOutcome {
        if shouldFail { throw DemoStoreError.failed }
        if purchaseOutcome == .purchased { grant(plan) }
        return purchaseOutcome
    }

    public func restore() async throws {
        if shouldFail { throw DemoStoreError.failed }
        for plan in ownedAfterRestore { grant(plan) }
    }

    public func activePlans() async -> Set<Plan> {
        lock.lock(); defer { lock.unlock() }
        return owned
    }

    public func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
        }
    }

    /// Simulates a purchase made elsewhere, such as a renewal or a refund.
    public func grant(_ plan: Plan) {
        lock.lock()
        owned.insert(plan)
        let all = continuations
        lock.unlock()
        all.forEach { $0.yield() }
    }

    public func revokeAll() {
        lock.lock()
        owned.removeAll()
        let all = continuations
        lock.unlock()
        all.forEach { $0.yield() }
    }
}

public enum DemoStoreError: Error { case failed }
