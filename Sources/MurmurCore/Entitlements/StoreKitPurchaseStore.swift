import Foundation
#if canImport(StoreKit)
import StoreKit

/// The real App Store, using StoreKit 2.
public actor StoreKitPurchaseStore: PurchaseStore {
    private var products: [Plan: Product] = [:]

    public init() {}

    public func offers() async throws -> [PlanOffer] {
        let loaded = try await Product.products(for: Plan.allCases.map(\.productID))
        var result: [PlanOffer] = []
        for plan in Plan.allCases {
            guard let product = loaded.first(where: { $0.id == plan.productID }) else { continue }
            products[plan] = product
            var monthly: String?
            var trial: Int?
            if plan == .yearly {
                monthly = product.priceFormatStyle.format(product.price / 12)
            }
            if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
                let days: Int
                switch offer.period.unit {
                case .day: days = offer.period.value
                case .week: days = offer.period.value * 7
                case .month: days = offer.period.value * 30
                case .year: days = offer.period.value * 365
                @unknown default: days = offer.period.value
                }
                trial = days
            }
            result.append(PlanOffer(plan: plan, displayPrice: product.displayPrice,
                                    monthlyEquivalent: monthly, trialDays: trial))
        }
        return result
    }

    public func purchase(_ plan: Plan) async throws -> PurchaseOutcome {
        if products[plan] == nil { _ = try await offers() }
        guard let product = products[plan] else { throw StoreKitPurchaseError.productUnavailable }
        switch try await product.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .purchased
            case .unverified:
                throw StoreKitPurchaseError.unverified
            }
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
    }

    public func activePlans() async -> Set<Plan> {
        var plans: Set<Plan> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  let plan = Plan.allCases.first(where: { $0.productID == transaction.productID }) else { continue }
            plans.insert(plan)
        }
        return plans
    }

    public nonisolated func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result { await transaction.finish() }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum StoreKitPurchaseError: Error {
    case productUnavailable
    case unverified
}
#endif
