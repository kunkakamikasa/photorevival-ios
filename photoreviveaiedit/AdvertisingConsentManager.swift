import AppTrackingTransparency
import Combine
import Foundation
import UserMessagingPlatform

enum AdvertisingConsentPresentationPolicy {
    static func canLoadGoogleForm(
        trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus
    ) -> Bool {
        trackingAuthorizationStatus != .notDetermined
    }
}

/// Keeps Google advertising consent in sync and provides the user-facing
/// privacy-options entry point required by some regional consent messages.
@MainActor
final class AdvertisingConsentManager: ObservableObject {
    static let shared = AdvertisingConsentManager()

    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var isGatheringConsent = false

    private var preparationTask: Task<Bool, Never>?
    private var hasCompletedPreparation = false

    private init() {}

    /// Refreshes consent once per process launch and returns whether Google
    /// permits ad requests for the current consent state.
    func prepareForAdRequests() async -> Bool {
        // Always let the native iOS ATT sheet make the first and only tracking
        // request. Loading UMP while ATT is undecided lets a remotely published
        // AdMob IDFA explainer appear in front of it.
        guard AdvertisingConsentPresentationPolicy.canLoadGoogleForm(
            trackingAuthorizationStatus: ATTrackingManager.trackingAuthorizationStatus
        ) else {
            return false
        }

        if hasCompletedPreparation {
            refreshPrivacyOptionsRequirement()
            return ConsentInformation.shared.canRequestAds
        }

        if let preparationTask {
            return await preparationTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.gatherConsent()
        }
        preparationTask = task

        let canRequestAds = await task.value
        hasCompletedPreparation = true
        preparationTask = nil
        return canRequestAds
    }

    /// Presents Google's current privacy-options form. Call this only when
    /// `isPrivacyOptionsRequired` is true.
    func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        refreshPrivacyOptionsRequirement()
    }

    private func gatherConsent() async -> Bool {
        isGatheringConsent = true
        defer {
            isGatheringConsent = false
            refreshPrivacyOptionsRequirement()
        }

        do {
            let parameters = RequestParameters()
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            refreshPrivacyOptionsRequirement()
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // UMP retains a valid choice from a previous session when possible.
            // If no usable choice exists, canRequestAds remains false and ads
            // are skipped instead of bypassing consent.
            print("[AdvertisingConsent] Consent update failed: \(error.localizedDescription)")
        }

        return ConsentInformation.shared.canRequestAds
    }

    private func refreshPrivacyOptionsRequirement() {
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }
}
