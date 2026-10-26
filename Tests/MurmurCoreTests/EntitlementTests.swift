import XCTest
@testable import MurmurCore

private func seg(_ start: Double) -> TranscriptSegment {
    TranscriptSegment(start: start, end: start + 5, text: "line at \(Int(start))")
}

final class FreeTierTests: XCTestCase {
    private let segments = [seg(0), seg(60), seg(119), seg(120), seg(300)]

    func testFreeUsersSeeOnlyFirstTwoMinutes() {
        let visible = FreeTier.visible(segments, isPro: false)
        XCTAssertEqual(visible.map(\.start), [0, 60, 119])
        XCTAssertEqual(FreeTier.lockedCount(segments, isPro: false), 2)
    }

    func testProSeesEverything() {
        XCTAssertEqual(FreeTier.visible(segments, isPro: true).count, 5)
        XCTAssertEqual(FreeTier.lockedCount(segments, isPro: true), 0)
    }

    func testShortNoteIsNeverLimited() {
        XCTAssertEqual(FreeTier.lockedCount([seg(0), seg(90)], isPro: false), 0)
        XCTAssertEqual(FreeTier.lockedCount([], isPro: false), 0)
    }

    func testLockedText() {
        XCTAssertEqual(FreeTier.lockedText(duration: 42 * 60 + 10), "About 40 more minutes of this note are locked.")
        XCTAssertEqual(FreeTier.lockedText(duration: 181), "About 1 more minute of this note is locked.")
    }
}

final class PlanTests: XCTestCase {
    func testProductIDsAreUnique() {
        let ids = Plan.allCases.map(\.productID)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(Plan.yearly.productID, "app.murmur.pro.yearly")
    }

    func testPlaceholderOffers() {
        let yearly = PlanOffer.placeholder(.yearly)
        XCTAssertFalse(yearly.isAvailable)
        XCTAssertEqual(yearly.detail, "$1.67 a month · 7-day free trial")
        XCTAssertEqual(yearly.callToAction, "Start 7-day free trial")
        XCTAssertEqual(yearly.badge, "BEST VALUE")
        XCTAssertEqual(PlanOffer.placeholder(.lifetime).callToAction, "Unlock forever · $39.99")
        XCTAssertEqual(PlanOffer.placeholder(.monthly).callToAction, "Continue · $3.99/month")
        XCTAssertNil(PlanOffer.placeholder(.monthly).badge)
    }

    func testYearlyWithoutTrial() {
        let offer = PlanOffer(plan: .yearly, displayPrice: "$24.99")
        XCTAssertEqual(offer.callToAction, "Subscribe · $24.99/year")
        XCTAssertEqual(offer.detail, "Billed yearly")
    }
}

@MainActor
final class EntitlementControllerTests: XCTestCase {
    func testStartsFreeWithPlaceholderOffers() {
        let controller = EntitlementController(store: DemoPurchaseStore())
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(controller.offers.count, 3)
        XCTAssertFalse(controller.offers[0].isAvailable)
        XCTAssertEqual(controller.selected, .yearly)
    }

    func testStartLoadsOffersAndOwnedPlans() async {
        let controller = EntitlementController(store: DemoPurchaseStore(owned: [.monthly, .lifetime]))
        await controller.start()
        XCTAssertTrue(controller.isPro)
        XCTAssertEqual(controller.activePlan, .lifetime)
        XCTAssertTrue(controller.offers.allSatisfy(\.isAvailable))
    }

    func testPurchaseUnlocks() async {
        let store = DemoPurchaseStore()
        let controller = EntitlementController(store: store)
        await controller.start()
        controller.selected = .lifetime
        await controller.purchase()
        XCTAssertTrue(controller.isPro)
        XCTAssertEqual(controller.activePlan, .lifetime)
        XCTAssertEqual(controller.state, .idle)
    }

    func testCancelledAndPendingDoNotUnlock() async {
        let store = DemoPurchaseStore()
        let controller = EntitlementController(store: store)
        await controller.start()
        store.purchaseOutcome = .cancelled
        await controller.purchase()
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(controller.state, .idle)
        store.purchaseOutcome = .pending
        await controller.purchase()
        XCTAssertFalse(controller.isPro)
        if case .message = controller.state {} else { XCTFail("expected a message") }
    }

    func testPurchaseWithoutProductsFailsClearly() async {
        let store = DemoPurchaseStore()
        store.shouldFail = true
        let controller = EntitlementController(store: store)
        await controller.start()
        XCTAssertFalse(controller.selectedOffer.isAvailable)
        await controller.purchase()
        if case .failed = controller.state {} else { XCTFail("expected failure") }
        controller.dismissMessage()
        XCTAssertEqual(controller.state, .idle)
    }

    func testRestore() async {
        let store = DemoPurchaseStore()
        store.ownedAfterRestore = [.yearly]
        let controller = EntitlementController(store: store)
        await controller.start()
        await controller.restore()
        XCTAssertTrue(controller.isPro)
        XCTAssertEqual(controller.state, .message("Purchases restored."))
    }

    func testRestoreWithNothingToRestore() async {
        let controller = EntitlementController(store: DemoPurchaseStore())
        await controller.start()
        await controller.restore()
        XCTAssertFalse(controller.isPro)
        XCTAssertEqual(controller.state, .message("No purchases found for this Apple ID."))
    }

    func testRestoreFailureShowsError() async {
        let store = DemoPurchaseStore()
        let controller = EntitlementController(store: store)
        store.shouldFail = true
        await controller.restore()
        if case .failed = controller.state {} else { XCTFail("expected failure") }
    }

    func testUpdatesFromOutsideChangeStatus() async throws {
        let store = DemoPurchaseStore()
        let controller = EntitlementController(store: store)
        await controller.start()
        XCTAssertFalse(controller.isPro)
        store.grant(.monthly)
        for _ in 0..<50 where !controller.isPro { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(controller.isPro)
        store.revokeAll()
        for _ in 0..<50 where controller.isPro { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(controller.isPro)
    }

    func testCallToActionFollowsSelection() async {
        let controller = EntitlementController(store: DemoPurchaseStore())
        await controller.start()
        XCTAssertEqual(controller.callToAction, "Start 7-day free trial")
        controller.selected = .monthly
        XCTAssertEqual(controller.callToAction, "Continue · $3.99/month")
    }
}
