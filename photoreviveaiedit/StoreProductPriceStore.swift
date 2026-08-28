import Combine
import StoreKit

@MainActor
final class StoreProductPriceStore: ObservableObject {
    static let shared = StoreProductPriceStore()

    @Published private(set) var products: [String: Product] = [:]
    private var requestedIDs = Set<String>()

    private init() {}

    func load(productIDs: [String]) async {
        let ids = Set(productIDs.filter { !$0.isEmpty })
        let missing = ids.subtracting(requestedIDs)
        guard !missing.isEmpty else { return }
        requestedIDs.formUnion(missing)
        do {
            let loaded = try await Product.products(for: missing)
            for product in loaded {
                products[product.id] = product
            }
        } catch {
            requestedIDs.subtract(missing)
        }
    }

    func displayPrice(for productID: String?, fallback: String = "—") -> String {
        guard let productID, let product = products[productID] else { return fallback }
        return product.displayPrice
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
