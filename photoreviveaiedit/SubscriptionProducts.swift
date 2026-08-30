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
            // The backend activates subscriptions against a concrete user ID.
            // Guest paywalls therefore need an anonymous Supabase user before
            // StoreKit can create a transaction that must later be verified.
            _ = try await PhotoReviveAuthClient.shared.ensureUserAccessToken()

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

            // A previous Apple transaction may still be unfinished when its
            // server activation failed. Verify that transaction first instead
            // of presenting a second purchase that could charge the user again.
            if let recovered = await recoverUnfinishedPurchase(
                productID: product.id,
                fallbackValue: value,
                fallbackCurrency: currency,
                promotion: promotion
            ) {
                return recovered
            }

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
                    return await completeVerifiedPurchase(
                        transaction,
                        signedTransactionInfo: verification.jwsRepresentation,
                        fallbackValue: value,
                        fallbackCurrency: currency,
                        promotion: promotion
                    )
                case .unverified(_, let error):
                    AppAnalytics.subscriptionResult(
                        productID: product.id,
                        result: "failed",
                        failureStage: "store_verification",
                        value: value,
                        currency: currency,
                        promotion: promotion
                    )
                    return .failed(error.userFacingEnglishMessage(
                        fallback: "The App Store could not verify this purchase. Please try again."
                    ))
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
            return .failed(error.userFacingEnglishMessage(
                fallback: "The purchase could not be completed. Please try again."
            ))
        }
    }

    private static func recoverUnfinishedPurchase(
        productID: String,
        fallbackValue: Double,
        fallbackCurrency: String,
        promotion: AppAnalytics.PromotionContext?
    ) async -> SubscriptionPurchaseOutcome? {
        for await verification in Transaction.unfinished {
            switch verification {
            case .verified(let transaction)
                where transaction.productType == .autoRenewable &&
                    transaction.productID == productID:
                return await completeVerifiedPurchase(
                    transaction,
                    signedTransactionInfo: verification.jwsRepresentation,
                    fallbackValue: fallbackValue,
                    fallbackCurrency: fallbackCurrency,
                    promotion: promotion
                )
            case .unverified(let transaction, let error)
                where transaction.productType == .autoRenewable &&
                    transaction.productID == productID:
                AppAnalytics.subscriptionResult(
                    productID: productID,
                    result: "failed",
                    failureStage: "store_verification",
                    value: fallbackValue,
                    currency: fallbackCurrency,
                    promotion: promotion
                )
                return .failed(error.userFacingEnglishMessage(
                    fallback: "The App Store could not verify this purchase. Please try again."
                ))
            default:
                continue
            }
        }
        return nil
    }

    private static func completeVerifiedPurchase(
        _ transaction: Transaction,
        signedTransactionInfo: String,
        fallbackValue: Double,
        fallbackCurrency: String,
        promotion: AppAnalytics.PromotionContext?,
        reportsClientAttribution: Bool = true
    ) async -> SubscriptionPurchaseOutcome {
        // StoreKit 2 purchases are handed to Firebase explicitly so its IAP
        // report receives the verified App Store transaction.
        AppAnalytics.storeTransaction(transaction)
        let transactionValue = transaction.price.map {
            NSDecimalNumber(decimal: $0).doubleValue
        } ?? fallbackValue
        let transactionCurrency = transaction.currency?.identifier ?? fallbackCurrency

        do {
            let serverVerification = try await PhotoReviveAPIClient.shared.verifySubscription(
                transactionID: String(transaction.id),
                signedTransactionInfo: signedTransactionInfo
            )
            guard serverVerification.success,
                  serverVerification.subscriptionStatus == "active" else {
                AppAnalytics.subscriptionResult(
                    productID: transaction.productID,
                    result: "failed",
                    failureStage: "server_activation",
                    value: transactionValue,
                    currency: transactionCurrency,
                    promotion: promotion
                )
                return .failed(EnglishDisplayText.userFacingMessage(
                    serverVerification.message,
                    fallback: "Apple confirmed the purchase, but membership activation is still pending. Please try again."
                ))
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
            if reportsClientAttribution {
                MetaSubscriptionAnalytics.reportVerifiedPurchase(
                    productID: transaction.productID,
                    value: transactionValue,
                    currency: transactionCurrency,
                    transactionID: String(transaction.id),
                    originalTransactionID: String(transaction.originalID),
                    isStartTrial: isStartTrial
                )
                AdjustService.shared.trackSubscribe(
                    productID: transaction.productID,
                    revenue: transactionValue,
                    currency: transactionCurrency,
                    transactionID: String(transaction.id),
                    orderID: String(transaction.id)
                )
            }
            await transaction.finish()
            AppAnalytics.subscriptionResult(
                productID: transaction.productID,
                result: "purchased",
                value: transactionValue,
                currency: transactionCurrency,
                promotion: promotion
            )
            return .purchased
        } catch {
            AppAnalytics.subscriptionResult(
                productID: transaction.productID,
                result: "failed",
                failureStage: "server_activation",
                value: transactionValue,
                currency: transactionCurrency,
                promotion: promotion
            )
            return .failed(error.userFacingEnglishMessage(
                fallback: "Apple confirmed the purchase, but membership activation is still pending. Please try again."
            ))
        }
    }

    static func processTransactionUpdate(
        _ verification: VerificationResult<Transaction>
    ) async {
        switch verification {
        case .verified(let transaction) where transaction.productType == .autoRenewable:
            let value = transaction.price.map {
                NSDecimalNumber(decimal: $0).doubleValue
            } ?? 0
            let currency = transaction.currency?.identifier ?? "USD"
            _ = await completeVerifiedPurchase(
                transaction,
                signedTransactionInfo: verification.jwsRepresentation,
                fallbackValue: value,
                fallbackCurrency: currency,
                promotion: nil,
                reportsClientAttribution: false
            )
        case .unverified(let transaction, _) where transaction.productType == .autoRenewable:
            AppAnalytics.subscriptionResult(
                productID: transaction.productID,
                result: "failed",
                failureStage: "store_verification"
            )
        default:
            break
        }
    }

    static func restore() async -> SubscriptionPurchaseOutcome {
        AppAnalytics.restoreStarted()
        do {
            _ = try await PhotoReviveAuthClient.shared.ensureUserAccessToken()
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
                        lastVerificationError = EnglishDisplayText.userFacingMessage(
                            serverVerification.message,
                            fallback: "Membership activation is still pending. Please try again."
                        )
                    } catch {
                        lastVerificationError = error.userFacingEnglishMessage(
                            fallback: "Membership could not be restored. Please try again."
                        )
                    }
                case .unverified(_, let error):
                    lastVerificationError = error.userFacingEnglishMessage(
                        fallback: "The App Store could not verify this subscription."
                    )
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
            return .failed(error.userFacingEnglishMessage(
                fallback: "Membership could not be restored. Please try again."
            ))
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

@MainActor
final class SubscriptionTransactionObserver {
    static let shared = SubscriptionTransactionObserver()

    private var updatesTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { return }
                await SubscriptionPurchaseService.processTransactionUpdate(verification)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
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
