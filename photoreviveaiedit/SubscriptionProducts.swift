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

enum SubscriptionPlanLevel: Int, Comparable {
    case proWeekly = 0
    case proAnnual = 1
    case proPlusWeekly = 2
    case proPlusAnnual = 3

    static func < (lhs: SubscriptionPlanLevel, rhs: SubscriptionPlanLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init?(productID: String?) {
        guard let productID else { return nil }
        let normalized = productID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "loged_", with: "")

        switch normalized {
        case "pro_weekly", "special_gift_weekly", "family_exclusive_weekly", "super_prize_weekly":
            self = .proWeekly
        case "pro_yearly", "limited_time_offer_yearly", "special_gift_yearly", "3dayfreetrial_yearly":
            self = .proAnnual
        case "proplus_weekly":
            self = .proPlusWeekly
        case "proplus_yearly":
            self = .proPlusAnnual
        default:
            return nil
        }
    }

    var isHighest: Bool { self == .proPlusAnnual }
}

enum SubscriptionPurchaseOutcome {
    case purchased
    case cancelled
    case pending
    case unavailable
    case failed(String)
}

enum SubscriptionPurchaseService {
    static func purchase(
        _ productID: SubscriptionProductID,
        promotion: AppAnalytics.PromotionContext? = nil
    ) async -> SubscriptionPurchaseOutcome {
        await purchase(productID.rawValue, promotion: promotion)
    }

    static func purchase(
        _ productID: String,
        promotion: AppAnalytics.PromotionContext? = nil
    ) async -> SubscriptionPurchaseOutcome {
        if let promotion {
            AppAnalytics.promotionSelected(promotion, productID: productID)
        }
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                AppAnalytics.subscriptionResult(
                    productID: productID,
                    result: "unavailable",
                    failureStage: "product_lookup",
                    promotion: promotion
                )
                return .unavailable
            }

            let value = NSDecimalNumber(decimal: product.price).doubleValue
            let currency = product.priceFormatStyle.currencyCode
            AppAnalytics.checkoutStarted(
                productID: product.id,
                value: value,
                currency: currency,
                productName: product.displayName,
                promotion: promotion
            )

            let purchaseResult: Product.PurchaseResult
            if let userID = PhotoReviveAuthClient.shared.currentUserID,
               let appAccountToken = UUID(uuidString: userID) {
                purchaseResult = try await product.purchase(
                    options: [.appAccountToken(appAccountToken)]
                )
            } else {
                purchaseResult = try await product.purchase()
            }

            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // StoreKit 2 purchases are handed to Firebase explicitly so
                    // its IAP report receives the verified App Store transaction.
                    AppAnalytics.storeTransaction(transaction)
                    let transactionValue = transaction.price.map {
                        NSDecimalNumber(decimal: $0).doubleValue
                    } ?? value
                    let transactionCurrency = transaction.currency?.identifier ?? currency
                    let serverVerification = try await PhotoReviveAPIClient.shared.verifySubscription(
                        transactionID: String(transaction.id),
                        signedTransactionInfo: verification.jwsRepresentation
                    )
                    guard serverVerification.success,
                          serverVerification.subscriptionStatus == "active" else {
                        AppAnalytics.subscriptionResult(
                            productID: product.id,
                            result: "failed",
                            failureStage: "server_activation",
                            value: transactionValue,
                            currency: transactionCurrency,
                            promotion: promotion
                        )
                        return .failed(serverVerification.message ?? "Apple confirmed the purchase, but membership activation is still pending. Please try again.")
                    }
                    await AppAccountStore.shared.applySubscriptionVerification(serverVerification)
                    Task { @MainActor in
                        await AppAccountStore.shared.refreshCredits()
                        await AppAccountStore.shared.refreshCreditTransactions()
                    }
                    let isStartTrial: Bool
                    if #available(iOS 17.2, *) {
                        isStartTrial = transaction.offer?.paymentMode == .freeTrial
                    } else {
                        isStartTrial = false
                    }
                    MetaSubscriptionAnalytics.reportVerifiedPurchase(
                        productID: product.id,
                        value: transactionValue,
                        currency: transactionCurrency,
                        transactionID: String(transaction.id),
                        originalTransactionID: String(transaction.originalID),
                        isStartTrial: isStartTrial
                    )
                    AdjustService.shared.trackSubscribe(
                        productID: product.id,
                        revenue: NSDecimalNumber(decimal: product.price).doubleValue,
                        currency: product.priceFormatStyle.currencyCode,
                        transactionID: String(transaction.id),
                        orderID: String(transaction.id)
                    )
                    await transaction.finish()
                    AppAnalytics.subscriptionResult(
                        productID: product.id,
                        result: "purchased",
                        value: transactionValue,
                        currency: transactionCurrency,
                        promotion: promotion
                    )
                    return .purchased
                case .unverified(_, let error):
                    AppAnalytics.subscriptionResult(
                        productID: product.id,
                        result: "failed",
                        failureStage: "store_verification",
                        value: value,
                        currency: currency,
                        promotion: promotion
                    )
                    return .failed(error.localizedDescription)
                }
            case .userCancelled:
                AppAnalytics.subscriptionResult(
                    productID: product.id,
                    result: "cancelled",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .cancelled
            case .pending:
                AppAnalytics.subscriptionResult(
                    productID: product.id,
                    result: "pending",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .pending
            @unknown default:
                AppAnalytics.subscriptionResult(
                    productID: product.id,
                    result: "failed",
                    failureStage: "unknown_store_result",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .failed("Apple returned an unknown purchase result. Please try again.")
            }
        } catch {
            AppAnalytics.subscriptionResult(
                productID: productID,
                result: "failed",
                failureStage: "store_purchase",
                promotion: promotion
            )
            return .failed(error.localizedDescription)
        }
    }

    static func restore() async -> SubscriptionPurchaseOutcome {
        AppAnalytics.restoreStarted()
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
                            await AppAccountStore.shared.applySubscriptionVerification(serverVerification)
                            Task { @MainActor in
                                await AppAccountStore.shared.refreshCredits()
                                await AppAccountStore.shared.refreshCreditTransactions()
                            }
                            AppAnalytics.restoreResult("purchased")
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
                AppAnalytics.restoreResult(
                    "failed",
                    failureStage: "entitlement_verification"
                )
                return .failed(lastVerificationError)
            }
            AppAnalytics.restoreResult("unavailable")
            return .unavailable
        } catch {
            AppAnalytics.restoreResult("failed", failureStage: "store_sync")
            return .failed(error.localizedDescription)
        }
    }

    static func hasActiveStoreEntitlement(now: Date = Date()) async -> Bool {
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil else {
                continue
            }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= now {
                continue
            }
            return true
        }
        return false
    }

    static func activeProductID(now: Date = Date()) async -> String? {
        var bestMatch: (id: String, level: SubscriptionPlanLevel)?
        var fallbackProductID: String?

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil else {
                continue
            }
            if let expirationDate = transaction.expirationDate,
               expirationDate <= now {
                continue
            }

            guard let level = SubscriptionPlanLevel(productID: transaction.productID) else {
                fallbackProductID = fallbackProductID ?? transaction.productID
                continue
            }
            if bestMatch.map({ level > $0.level }) ?? true {
                bestMatch = (transaction.productID, level)
            }
        }

        return bestMatch?.id ?? fallbackProductID
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
