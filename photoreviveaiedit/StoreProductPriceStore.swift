import Combine
import StoreKit

enum StoreProductPreloadCatalog {
    static var knownProductIDs: [String] {
        Array(Set(
            SubscriptionProductID.allCases.map(\.rawValue)
                + CreditProductCatalog.allProductIDs
        )).sorted()
    }
}

@MainActor
final class StoreProductPriceStore: ObservableObject {
    static let shared = StoreProductPriceStore()

    @Published private(set) var products: [String: Product] = [:]

    private init() {}

    func preloadKnownProducts() async {
        await load(productIDs: StoreProductPreloadCatalog.knownProductIDs)
    }

    func load(productIDs: [String]) async {
        await load(productIDs: productIDs, maximumAttempts: 1)
    }

    func loadWithRetry(
        productIDs: [String],
        maximumAttempts: Int = 3
    ) async {
        await load(
            productIDs: productIDs,
            maximumAttempts: max(1, maximumAttempts)
        )
    }

    private func load(
        productIDs: [String],
        maximumAttempts: Int
    ) async {
        let requestedProductIDs = Set(productIDs.filter { !$0.isEmpty })
        guard !requestedProductIDs.isEmpty else { return }

        for attempt in 0..<maximumAttempts {
            guard !Task.isCancelled else { return }

            let missingProductIDs = requestedProductIDs.subtracting(products.keys)
            guard !missingProductIDs.isEmpty else { return }

            if attempt > 0 {
                let retryDelay = UInt64(attempt) * 500_000_000
                try? await Task.sleep(nanoseconds: retryDelay)
                guard !Task.isCancelled else { return }
            }

            do {
                let loaded = try await Product.products(for: missingProductIDs)
                for product in loaded {
                    products[product.id] = product
                }
            } catch {
                // A failed StoreKit lookup must remain retryable. In particular,
                // startup preloading must not permanently block a paywall lookup.
            }
        }
    }

    func displayPrice(for productID: String?, fallback: String = "—") -> String {
        guard let productID, let product = products[productID] else { return fallback }
        return product.displayPrice
    }

    func loadedDisplayPrice(for productID: String) -> String? {
        products[productID]?.displayPrice
    }

    func periodicPrice(
        for productID: String?,
        divisor: Decimal,
        suffix: String,
        fallback: String = "—"
    ) -> String {
        guard let productID, let product = products[productID], divisor != 0 else {
            return fallback
        }
        return "\((product.price / divisor).formatted(product.priceFormatStyle))\(suffix)"
    }

    func introductoryDisplayPrice(for productID: String) -> String? {
        guard let product = products[productID],
              let offer = product.subscription?.introductoryOffer else { return nil }
        return offer.price.formatted(product.priceFormatStyle)
    }

    func hasIntroductoryOffer(productID: String) -> Bool {
        products[productID]?.subscription?.introductoryOffer != nil
    }

    func introductoryPeriodicPrice(
        for productID: String,
        divisor: Decimal,
        suffix: String
    ) -> String? {
        guard divisor != 0,
              let product = products[productID],
              let offer = product.subscription?.introductoryOffer else { return nil }
        return "\((offer.price / divisor).formatted(product.priceFormatStyle))\(suffix)"
    }

    func introductoryPeriodDescription(for productID: String) -> String? {
        guard let period = products[productID]?.subscription?.introductoryOffer?.period else {
            return nil
        }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return nil
        }
        return "\(period.value) \(unit)"
    }

    func isEligibleForIntroOffer(productID: String) async -> Bool {
        await load(productIDs: [productID])
        guard let subscription = products[productID]?.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }
}
