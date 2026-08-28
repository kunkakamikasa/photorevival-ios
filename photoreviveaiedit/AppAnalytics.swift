import FirebaseAnalytics
import Foundation
import StoreKit

/// The single entry point for product analytics.
///
/// Keep parameters low-cardinality and never pass prompts, email addresses,
/// media URLs, server task IDs, or localized error messages to this type.
enum AppAnalytics {
    struct PromotionContext: Hashable {
        let promotionID: String
        let promotionName: String
        let creativeName: String
        let creativeSlot: String
        let offerVariant: String
        let billingPeriod: String?

        init(
            promotionID: String,
            promotionName: String,
            creativeName: String,
            creativeSlot: String,
            offerVariant: String,
            billingPeriod: String? = nil
        ) {
            self.promotionID = promotionID
            self.promotionName = promotionName
            self.creativeName = creativeName
            self.creativeSlot = creativeSlot
            self.offerVariant = offerVariant
            self.billingPeriod = billingPeriod
        }

        var parameters: [String: Any] {
            var parameters: [String: Any] = [
                "promotion_id": promotionID,
                "promotion_name": promotionName,
                "creative_name": creativeName,
                "creative_slot": creativeSlot,
                "offer_variant": offerVariant
            ]
            parameters["billing_period"] = billingPeriod
            return parameters
        }
    }

    static func configure(userID: String?, isSignedIn: Bool, isSubscribed: Bool) {
        // This app intentionally uses Firebase Analytics for the product funnel.
        // If a dedicated analytics-consent setting is added later, pass that
        // choice here instead of enabling collection unconditionally.
        Analytics.setAnalyticsCollectionEnabled(true)
        updateUser(userID: userID, isSignedIn: isSignedIn)
        updateSubscription(isSubscribed: isSubscribed)
    }

    static func updateUser(userID: String?, isSignedIn: Bool) {
        Analytics.setUserID(isSignedIn ? normalized(userID) : nil)
        Analytics.setUserProperty(
            isSignedIn ? "signed_in" : "signed_out",
            forName: "auth_state"
        )
    }

    static func updateSubscription(isSubscribed: Bool) {
        Analytics.setUserProperty(
            isSubscribed ? "active" : "inactive",
            forName: "subscription_status"
        )
    }

    static func screen(_ name: String, className: String) {
        log("screen_view", [
            "screen_name": name,
            "screen_class": className
        ])
    }

    static func onboardingStepViewed(name: String, index: Int) {
        if index == 0 {
            log("tutorial_begin")
        }
        log("onboarding_step_view", [
            "step_name": name,
            "step_index": index
        ])
    }

    static func onboardingCompleted() {
        log("tutorial_complete")
    }

    static func authGateShown(source: String) {
        log("auth_gate_view", ["source": source])
    }

    static func authAttempt(method: String) {
        log("auth_attempt", ["method": method])
    }

    static func authResult(method: String, result: String, failureType: String? = nil) {
        var parameters: [String: Any] = [
            "method": method,
            "result": result
        ]
        parameters["failure_type"] = normalized(failureType)
        log("auth_result", parameters)

        if result == "success" {
            log("login", ["method": method])
        }
    }

    static func signedOut() {
        log("logout")
        updateUser(userID: nil, isSignedIn: false)
    }

    static func templateSelected(_ template: TemplateItem, source: String) {
        log("select_content", [
            "content_type": "template_\(template.generationKind.rawValue)",
            "item_id": template.id,
            "source": source
        ])
    }

    static func templateDetailViewed(_ template: TemplateItem) {
        log("template_detail_view", templateParameters(template))
    }

    static func templateTryNow(_ template: TemplateItem) {
        log("template_try_now", templateParameters(template))
    }

    /// One low-volume event per startup milestone. Media URLs and item ids are
    /// intentionally excluded so this remains suitable for aggregate startup
    /// and cache diagnostics.
    static func homeMediaMilestone(
        _ milestone: String,
        elapsedMilliseconds: Int,
        catalogSource: String?,
        imageMemoryHits: Int,
        imageDiskHits: Int,
        imageNetworkLoads: Int,
        videoDiskHits: Int,
        videoNetworkLoads: Int
    ) {
        let imageRequests = imageMemoryHits + imageDiskHits + imageNetworkLoads
        let imageCacheHitPermille = imageRequests > 0
            ? (imageMemoryHits + imageDiskHits) * 1_000 / imageRequests
            : 0
        let videoRequests = videoDiskHits + videoNetworkLoads
        let videoCacheHitPermille = videoRequests > 0
            ? videoDiskHits * 1_000 / videoRequests
            : 0
        log("home_media_perf", [
            "milestone": milestone,
            "elapsed_ms": elapsedMilliseconds,
            "catalog_source": normalized(catalogSource) as Any,
            "image_memory_hits": imageMemoryHits,
            "image_disk_hits": imageDiskHits,
            "image_network_loads": imageNetworkLoads,
            "image_cache_hit_permille": imageCacheHitPermille,
            "video_disk_hits": videoDiskHits,
            "video_network_loads": videoNetworkLoads,
            "video_cache_hit_permille": videoCacheHitPermille
        ])
    }

    static func fixedFeatureSelected(_ feature: FixedFeature, source: String) {
        log("select_content", [
            "content_type": "fixed_feature",
            "item_id": feature.rawValue,
            "source": source
        ])
    }

    static func paywallViewed(
        variant: String,
        source: String,
        productID: String? = nil,
        promotion: PromotionContext? = nil
    ) {
        let resolvedPromotion = promotion ?? PromotionContext(
            promotionID: variant,
            promotionName: variant,
            creativeName: variant,
            creativeSlot: source,
            offerVariant: variant
        )
        var commerceParameters: [String: Any] = [:]
        if let productID = normalized(productID) {
            commerceParameters["product_id"] = productID
            commerceParameters["items"] = [["item_id": productID]]
        }
        let promotionParameters = merging(
            resolvedPromotion.parameters,
            with: commerceParameters
        )
        log("paywall_view", merging([
            "paywall_variant": variant,
            "source": source
        ], with: promotionParameters))
        log("view_promotion", promotionParameters)
    }

    static func promotionSelected(
        _ promotion: PromotionContext,
        productID: String
    ) {
        log("select_promotion", merging(promotion.parameters, with: [
            "product_id": productID,
            "items": [["item_id": productID]]
        ]))
    }

    static func checkoutStarted(
        productID: String,
        value: Double,
        currency: String,
        productName: String,
        promotion: PromotionContext? = nil
    ) {
        var parameters: [String: Any] = [
            "currency": currency,
            "value": value,
            "product_id": productID,
            "items": [[
                "item_id": productID,
                "item_name": productName
            ]]
        ]
        if let promotion {
            parameters = merging(parameters, with: promotion.parameters)
        }
        log("begin_checkout", parameters)
    }

    static func subscriptionResult(
        productID: String,
        result: String,
        failureStage: String? = nil,
        value: Double? = nil,
        currency: String? = nil,
        promotion: PromotionContext? = nil
    ) {
        var parameters: [String: Any] = [
            "product_id": productID,
            "result": result
        ]
        parameters["failure_stage"] = normalized(failureStage)
        parameters["value"] = value
        parameters["currency"] = normalized(currency)
        if let promotion {
            parameters = merging(parameters, with: promotion.parameters)
        }
        log("subscription_result", parameters)

        if result == "purchased" {
            updateSubscription(isSubscribed: true)
        }
    }

    static func creditPurchaseResult(
        productID: String,
        result: String,
        failureStage: String? = nil,
        value: Double? = nil,
        currency: String? = nil,
        promotion: PromotionContext? = nil
    ) {
        var parameters: [String: Any] = [
            "product_id": productID,
            "result": result,
            "items": [["item_id": productID]]
        ]
        parameters["failure_stage"] = normalized(failureStage)
        parameters["value"] = value
        parameters["currency"] = normalized(currency)
        if let promotion {
            parameters = merging(parameters, with: promotion.parameters)
        }
        log("credit_purchase_result", parameters)
    }

    static func storeTransaction(_ transaction: StoreKit.Transaction) {
        Analytics.logTransaction(transaction)
    }

    static func restoreStarted() {
        log("restore_purchase", ["result": "started"])
    }

    static func restoreResult(_ result: String, failureStage: String? = nil) {
        var parameters: [String: Any] = ["result": result]
        parameters["failure_stage"] = normalized(failureStage)
        log("restore_purchase", parameters)

        if result == "purchased" {
            updateSubscription(isSubscribed: true)
        }
    }

    static func generationBlocked(
        contentType: String,
        itemID: String?,
        reason: String
    ) {
        log("generation_blocked", [
            "content_type": contentType,
            "item_id": normalized(itemID) as Any,
            "reason": reason
        ])
    }

    static func generationStarted(
        contentType: String,
        itemID: String?,
        creditsCost: Int,
        inputCount: Int,
        resolution: String,
        durationSeconds: Int? = nil,
        soundEnabled: Bool? = nil,
        multiShotEnabled: Bool? = nil
    ) {
        var parameters: [String: Any] = [
            "content_type": contentType,
            "credits_cost": creditsCost,
            "input_count": inputCount,
            "resolution": resolution
        ]
        parameters["item_id"] = normalized(itemID)
        parameters["duration_seconds"] = durationSeconds
        parameters["sound_enabled"] = soundEnabled.map(NSNumber.init(value:))
        parameters["multi_shot_enabled"] = multiShotEnabled.map(NSNumber.init(value:))
        log("generation_start", parameters)
    }

    static func generationSubmitted(contentType: String, itemID: String?) {
        log("generation_submitted", [
            "content_type": contentType,
            "item_id": normalized(itemID) as Any
        ])
    }

    static func generationCompleted(
        contentType: String,
        itemID: String?,
        elapsedMilliseconds: Int
    ) {
        log("generation_complete", [
            "content_type": contentType,
            "item_id": normalized(itemID) as Any,
            "elapsed_ms": elapsedMilliseconds
        ])
    }

    static func generationFailed(
        contentType: String,
        itemID: String?,
        stage: String,
        failureType: String,
        elapsedMilliseconds: Int? = nil
    ) {
        var parameters: [String: Any] = [
            "content_type": contentType,
            "stage": stage,
            "failure_type": failureType
        ]
        parameters["item_id"] = normalized(itemID)
        parameters["elapsed_ms"] = elapsedMilliseconds
        log("generation_failed", parameters)
    }

    static func contentSaved(contentType: String, itemID: String?) {
        log("content_saved", [
            "content_type": contentType,
            "item_id": normalized(itemID) as Any
        ])
    }

    static func apiFailureType(_ error: Error) -> String {
        if let error = error as? PhotoReviveAPIError {
            switch error {
            case .invalidResponse:
                return "invalid_response"
            case .requestFailed(let statusCode, _):
                switch statusCode {
                case 401, 403: return "authorization"
                case 400..<500: return "client_error"
                case 500..<600: return "server_error"
                default: return "http_error"
                }
            }
        }
        if error is URLError {
            return "network"
        }
        return "unknown"
    }

    private static func templateParameters(_ template: TemplateItem) -> [String: Any] {
        var parameters: [String: Any] = [
            "content_type": template.generationKind.rawValue,
            "item_id": template.id,
            "input_count": template.imageUploadCount
        ]
        parameters["model_type"] = normalized(template.modelType)
        return parameters
    }

    private static func merging(
        _ first: [String: Any],
        with second: [String: Any]
    ) -> [String: Any] {
        first.merging(second) { _, new in new }
    }

    private static func log(_ name: String, _ parameters: [String: Any] = [:]) {
        let compactParameters = parameters.reduce(into: [String: Any]()) { result, entry in
            if let optional = unwrap(entry.value) {
                result[entry.key] = optional
            }
        }
        Analytics.logEvent(name, parameters: compactParameters.isEmpty ? nil : compactParameters)
    }

    private static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return nil }
            return unwrap(wrapped)
        }
        if let string = value as? String {
            return normalized(string)
        }
        if let array = value as? [Any] {
            var compacted: [Any] = []
            for element in array {
                if let value = unwrap(element) {
                    compacted.append(value)
                }
            }
            return compacted
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = unwrap(entry.value)
            }
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(100))
    }
}
