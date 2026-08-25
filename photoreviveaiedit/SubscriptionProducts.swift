import Foundation
import StoreKit

enum SubscriptionProductID: String, CaseIterable, Identifiable {
    case proYearly = "pro_yearly"
    case proWeekly = "pro_weekly"
    case proPlusYearly = "proplus_yearly"
    case proPlusWeekly = "proplus_weekly"
    case loggedProYearly = "loged_pro_yearly"
    case loggedProWeekly = "loged_pro_weekly"
    case loggedProPlusYearly = "loged_proplus_yearly"
    case loggedProPlusWeekly = "loged_proplus_weekly"
    case limitedTimeOfferYearly = "limited_time_offer_yearly"
    case specialGiftYearly = "special_gift_yearly"
    case specialGiftWeekly = "special_gift_weekly"
    case familyExclusiveWeekly = "family_exclusive_weekly"
    case superPrizeWeekly = "super_prize_weekly"
    case threeDayFreeTrialYearly = "3dayfreetrial_yearly"

    var id: String { rawValue }
}

enum SubscriptionPurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case unavailable
    case failed(String)
}

enum SubscriptionPurchaseService {
    static func purchase(_ productID: SubscriptionProductID) async -> SubscriptionPurchaseOutcome {
        await purchase(productID.rawValue)
    }

    static func purchase(_ productID: String) async -> SubscriptionPurchaseOutcome {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else { return .unavailable }

            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let serverVerification = try await PhotoReviveAPIClient.shared.verifySubscription(
                        transactionID: String(transaction.id),
                        signedTransactionInfo: verification.jwsRepresentation
                    )
                    guard serverVerification.success,
                          serverVerification.subscriptionStatus == "active" else {
                        return .failed(serverVerification.message ?? "Apple confirmed the purchase, but membership activation is still pending. Please try again.")
                    }
                    AdjustService.shared.trackSubscribe(
                        productID: product.id,
                        revenue: NSDecimalNumber(decimal: product.price).doubleValue,
                        currency: product.priceFormatStyle.currencyCode,
                        transactionID: String(transaction.id),
                        orderID: String(transaction.id)
                    )
                    await transaction.finish()
                    return .purchased
                case .unverified(_, let error):
                    return .failed(error.localizedDescription)
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Apple returned an unknown purchase result. Please try again.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func restore() async -> SubscriptionPurchaseOutcome {
        do {
            try await AppStore.sync()
            var lastVerificationError: String?

            for await verification in Transaction.currentEntitlements {
                switch verification {
                case .verified(let transaction):
                    do {
                        let serverVerification = try await PhotoReviveAPIClient.shared.verifySubscription(
                            transactionID: String(transaction.id),
                            signedTransactionInfo: verification.jwsRepresentation
                        )
                        if serverVerification.success,
                           serverVerification.subscriptionStatus == "active" {
                            return .purchased
                        }
                        lastVerificationError = serverVerification.message
                    } catch {
                        lastVerificationError = error.localizedDescription
                    }
                case .unverified(_, let error):
                    lastVerificationError = error.localizedDescription
                }
            }

            if let lastVerificationError {
                return .failed(lastVerificationError)
            }
            return .unavailable
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

struct SubscriptionPurchaseAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum LimitedOfferEligibility {
    static func dayKey(for date: Date, calendar: Calendar = .current) -> Double {
        calendar.startOfDay(for: date).timeIntervalSince1970
    }

    static func canPresent(
        lastPresentedDay: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        lastPresentedDay != dayKey(for: now, calendar: calendar)
    }
}
