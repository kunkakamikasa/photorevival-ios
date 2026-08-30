//
//  AppOpenAdManager.swift
//  photoreviveaiedit
//

import Combine
import Foundation
import GoogleMobileAds
import UIKit

struct AppOpenAdLaunchPolicy {
    private static let hasLaunchedBeforeKey = "appOpenAd.hasLaunchedBefore.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records every process launch, but only allows ads after the first-ever launch.
    func shouldPrepareForLaunch(
        isAdvertisingEnabled: Bool,
        isSubscribed: Bool
    ) -> Bool {
        let hasLaunchedBefore = defaults.bool(forKey: Self.hasLaunchedBeforeKey)
        if !hasLaunchedBefore {
            defaults.set(true, forKey: Self.hasLaunchedBeforeKey)
            return false
        }

        return isAdvertisingEnabled && !isSubscribed
    }
}

enum AppOpenAdConfiguration {
    static let productionAdUnitID = "ca-app-pub-4065307599185281/1382540407"
    static let testAdUnitID = "ca-app-pub-3940256099942544/5575463023"

    static var adUnitID: String {
#if DEBUG
        testAdUnitID
#else
        productionAdUnitID
#endif
    }

    /// Debug builds use Google's test ad unit by default. Pass -disableAppOpenAd
    /// when a launch must remain free of full-screen ads.
    static var isAdvertisingEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
#if DEBUG
        let isDebugBuild = true
#else
        let isDebugBuild = false
#endif
        return shouldEnableAdvertising(
            arguments: processInfo.arguments,
            environment: processInfo.environment,
            isDebugBuild: isDebugBuild
        )
    }

    static func shouldEnableAdvertising(
        arguments: [String],
        environment: [String: String],
        isDebugBuild: Bool
    ) -> Bool {
        guard !arguments.contains("-disableAppOpenAd") else { return false }
        guard isDebugBuild else { return true }
        guard !arguments.contains("-skipOnboarding") else { return false }

        let automatedTestEnvironmentKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "XCInjectBundleInto"
        ]
        return automatedTestEnvironmentKeys.allSatisfy { environment[$0] == nil }
    }

    static var hasValidApplicationID: Bool {
        guard let appID = Bundle.main.object(
            forInfoDictionaryKey: "GADApplicationIdentifier"
        ) as? String else {
            return false
        }

        return appID.hasPrefix("ca-app-pub-")
            && appID.contains("~")
            && !appID.contains("$(")
    }
}

@MainActor
final class AppOpenAdManager: NSObject, ObservableObject {
    enum LaunchState {
        case inactive
        case loading
        case showing
        case complete
    }

    static let shared = AppOpenAdManager()

    private let consentResolutionWindow: TimeInterval = 20
    private let presentationWindow: TimeInterval = 12
    private let expirationInterval: TimeInterval = 4 * 60 * 60

    @Published private(set) var launchState: LaunchState = .inactive
    @Published private(set) var didPresentAdForCurrentLaunch = false

    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var presentationDeadline: Date?
    private var timeoutTask: Task<Void, Never>?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var shouldPresentForCurrentLaunch = false

    private override init() {
        super.init()
    }

    var isBlockingLaunchContent: Bool {
        launchState == .loading || launchState == .showing
    }

    func prepareForCurrentLaunch() {
        guard !shouldPresentForCurrentLaunch, !isShowingAd else { return }
        guard !isCurrentUserSubscribed else {
            print("[AppOpenAd] Active subscription found; skipping this launch.")
            return
        }
        guard AppOpenAdConfiguration.hasValidApplicationID else {
            print("[AppOpenAd] Missing a valid GADApplicationIdentifier; skipping this launch.")
            return
        }

        shouldPresentForCurrentLaunch = true
        launchState = .loading
        beginConsentResolutionWindow()

        Task {
            let canRequestAds = await AdvertisingConsentManager.shared.prepareForAdRequests()
            guard shouldPresentForCurrentLaunch else { return }
            guard !isCurrentUserSubscribed else {
                cancelPendingPresentation()
                return
            }
            guard canRequestAds else {
                print("[AppOpenAd] Consent state does not allow ad requests; skipping this launch.")
                cancelPendingPresentation()
                return
            }

            beginLoadingWindow()
            await loadAdIfNeeded()
        }
    }

    func applicationDidBecomeActive() {
        presentIfReady()
    }

    func applicationDidEnterBackground() {
        guard !isShowingAd else { return }
        cancelPendingPresentation()
    }

    private func beginConsentResolutionWindow() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.consentResolutionWindow))
            guard !Task.isCancelled else { return }
            print("[AppOpenAd] Consent flow exceeded the launch window; skipping this launch.")
            self.cancelPendingPresentation()
        }
    }

    private func beginLoadingWindow() {
        timeoutTask?.cancel()
        presentationDeadline = Date().addingTimeInterval(presentationWindow)
        MobileAds.shared.start()

        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.presentationWindow))
            guard !Task.isCancelled else { return }
            self.cancelPendingPresentation()
        }
    }

    private func loadAdIfNeeded() async {
        guard shouldPresentForCurrentLaunch, !isLoadingAd, !isAdAvailable else { return }

        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let loadedAd = try await AppOpenAd.load(
                with: AppOpenAdConfiguration.adUnitID,
                request: Request()
            )
            guard shouldPresentForCurrentLaunch else { return }
            guard !isCurrentUserSubscribed else {
                cancelPendingPresentation()
                return
            }
            loadedAd.fullScreenContentDelegate = self
            appOpenAd = loadedAd
            loadTime = Date()
            presentIfReady()
        } catch {
            print("[AppOpenAd] Failed to load: \(error.localizedDescription)")
            cancelPendingPresentation()
        }
    }

    private var isAdAvailable: Bool {
        guard appOpenAd != nil, let loadTime else { return false }
        return Date().timeIntervalSince(loadTime) < expirationInterval
    }

    private var isCurrentUserSubscribed: Bool {
        UserDefaults.standard.bool(forKey: "isSubscribed")
    }

    private func presentIfReady() {
        guard shouldPresentForCurrentLaunch, !isShowingAd else { return }
        guard !isCurrentUserSubscribed else {
            cancelPendingPresentation()
            return
        }

        // Consent may still be resolving when the app first becomes active.
        // The loading deadline begins only after UMP permits ad requests.
        guard let presentationDeadline else { return }
        guard Date() < presentationDeadline else {
            cancelPendingPresentation()
            return
        }

        guard UIApplication.shared.applicationState == .active,
              isAdAvailable,
              let appOpenAd else {
            return
        }

        shouldPresentForCurrentLaunch = false
        isShowingAd = true
        didPresentAdForCurrentLaunch = true
        launchState = .showing
        appOpenAd.present(from: nil)
    }

    private func cancelPendingPresentation() {
        timeoutTask?.cancel()
        timeoutTask = nil
        shouldPresentForCurrentLaunch = false
        presentationDeadline = nil
        appOpenAd = nil
        loadTime = nil
        launchState = .complete
    }

    private func finishPresentation() {
        isShowingAd = false
        cancelPendingPresentation()
    }
}

extension AppOpenAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishPresentation()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("[AppOpenAd] Failed to present: \(error.localizedDescription)")
        finishPresentation()
    }
}
