import Foundation
import StoreKit

enum CreditPurchaseOutcome: Equatable {
    case purchased(credits: Int)
    case cancelled
    case pending
    case unavailable
    case failed(String)
}

enum CreditPurchasePromotion {
    static func store(pack: CreditPack) -> AppAnalytics.PromotionContext {
        AppAnalytics.PromotionContext(
            promotionID: "credit_store_\(pack.id)",
            promotionName: "credit_store",
            creativeName: "credit_pack_\(pack.credits)",
            creativeSlot: "credit_detail",
            offerVariant: pack.id,
            billingPeriod: "one_time"
        )
    }

    static let callback377 = AppAnalytics.PromotionContext(
        promotionID: "callback_377",
        promotionName: "credit_callback",
        creativeName: "bonus_77",
        creativeSlot: "credit_store_exit",
        offerVariant: "callback_377",
        billingPeriod: "one_time"
    )

    static let surprise1600 = AppAnalytics.PromotionContext(
        promotionID: "subscriber_scratch_1600",
        promotionName: "subscriber_return_scratch",
        creativeName: "scratch_1600",
        creativeSlot: "subscriber_return",
        offerVariant: "subscriber_scratch_1600",
        billingPeriod: "one_time"
    )
}

@MainActor
enum CreditPurchaseService {
    static func purchase(
        _ pack: CreditPack,
        promotion: AppAnalytics.PromotionContext
    ) async -> CreditPurchaseOutcome {
        guard let productID = pack.productID, !productID.isEmpty else {
            return .unavailable
        }

        AppAnalytics.promotionSelected(promotion, productID: productID)

        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                AppAnalytics.creditPurchaseResult(
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

            if let recovered = await recoverUnfinishedPurchase(
                productID: product.id,
                fallbackCredits: pack.credits,
                value: value,
                currency: currency,
                promotion: promotion
            ) {
                return recovered
            }

            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    return await completeVerifiedPurchase(
                        transaction,
                        signedTransactionInfo: verification.jwsRepresentation,
                        fallbackCredits: pack.credits,
                        value: value,
                        currency: currency,
                        promotion: promotion
                    )

                case .unverified(_, let error):
                    AppAnalytics.creditPurchaseResult(
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
                AppAnalytics.creditPurchaseResult(
                    productID: product.id,
                    result: "cancelled",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .cancelled

            case .pending:
                AppAnalytics.creditPurchaseResult(
                    productID: product.id,
                    result: "pending",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .pending

            @unknown default:
                return .failed("Apple returned an unknown purchase result. Please try again.")
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            AppAnalytics.creditPurchaseResult(
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

    /// StoreKit keeps verified consumables unfinished until our server grants
    /// their credits. Retrying that transaction first prevents a second charge
    /// after a temporary network or backend failure.
    private static func recoverUnfinishedPurchase(
        productID: String,
        fallbackCredits: Int,
        value: Double,
        currency: String,
        promotion: AppAnalytics.PromotionContext
    ) async -> CreditPurchaseOutcome? {
        for await verification in Transaction.unfinished {
            switch verification {
            case .verified(let transaction) where transaction.productID == productID:
                return await completeVerifiedPurchase(
                    transaction,
                    signedTransactionInfo: verification.jwsRepresentation,
                    fallbackCredits: fallbackCredits,
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
            case .unverified(let transaction, let error) where transaction.productID == productID:
                AppAnalytics.creditPurchaseResult(
                    productID: productID,
                    result: "failed",
                    failureStage: "store_verification",
                    value: value,
                    currency: currency,
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
        fallbackCredits: Int,
        value: Double,
        currency: String,
        promotion: AppAnalytics.PromotionContext
    ) async -> CreditPurchaseOutcome {
        AppAnalytics.storeTransaction(transaction)
        do {
            let serverResult = try await verifyWithRetry(
                transactionID: String(transaction.id),
                signedTransactionInfo: signedTransactionInfo
            )
            guard serverResult.success, serverResult.type == "consumable" else {
                AppAnalytics.creditPurchaseResult(
                    productID: transaction.productID,
                    result: "failed",
                    failureStage: "server_credit_grant",
                    value: value,
                    currency: currency,
                    promotion: promotion
                )
                return .failed(EnglishDisplayText.userFacingMessage(
                    serverResult.message,
                    fallback: "Apple confirmed the payment, but the credits are still being verified."
                ))
            }

            await transaction.finish()
            let granted = serverResult.creditsGranted ?? fallbackCredits
            AppAnalytics.creditPurchaseResult(
                productID: transaction.productID,
                result: "purchased",
                value: value,
                currency: currency,
                promotion: promotion
            )
            return .purchased(credits: granted)
        } catch is CancellationError {
            return .cancelled
        } catch {
            AppAnalytics.creditPurchaseResult(
                productID: transaction.productID,
                result: "failed",
                failureStage: "server_credit_grant",
                value: value,
                currency: currency,
                promotion: promotion
            )
            return .failed("Your payment is being confirmed. Please reopen Credit Detail shortly; the same Apple transaction will not be charged twice.")
        }
    }

    private static func verifyWithRetry(
        transactionID: String,
        signedTransactionInfo: String
    ) async throws -> AppleIAPVerificationResult {
        var lastError: Error?
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                return try await AppAccountStore.shared.verifyCreditPurchase(
                    transactionID: transactionID,
                    signedTransactionInfo: signedTransactionInfo
                )
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < 2 else { throw error }
                let delay = [1, 2, 4][attempt]
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw lastError ?? PhotoReviveAPIError.invalidResponse
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case PhotoReviveAPIError.requestFailed(let statusCode, _) = error {
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        }
        return false
    }
}
