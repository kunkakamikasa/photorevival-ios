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
        do {
            let products = try await Product.products(for: [productID.rawValue])
            guard let product = products.first else { return .unavailable }

            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
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
