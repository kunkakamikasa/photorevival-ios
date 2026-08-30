//
//  photoreviveaieditApp.swift
//  photoreviveaiedit
//
//  Created by Mayingkun on 2026/8/15.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import FacebookCore
import AdSupport
import AppTrackingTransparency
import UIKit

final class PhotoReviveAppDelegate: NSObject, UIApplicationDelegate {
    private var appOpenAdPreparationTask: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Facebook's launch hook starts network discovery immediately. Preserve
        // the options now, then forward them after the launch video has rendered
        // so a first-network system sheet never lands on the black launch color.
        StartupServiceBootstrap.captureLaunchOptions(launchOptions)
        SubscriptionTransactionObserver.shared.start()

        let shouldPrepareAppOpenAd = AppOpenAdLaunchPolicy().shouldPrepareForLaunch(
            isAdvertisingEnabled: AppOpenAdConfiguration.isAdvertisingEnabled,
            isSubscribed: UserDefaults.standard.bool(forKey: "isSubscribed")
        )
        if shouldPrepareAppOpenAd {
            appOpenAdPreparationTask = Task { [weak self] in
                defer { self?.appOpenAdPreparationTask = nil }

                let isSubscribed = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
                guard !Task.isCancelled else { return }

                UserDefaults.standard.set(isSubscribed, forKey: "isSubscribed")
                guard !isSubscribed else { return }

                AppOpenAdManager.shared.prepareForCurrentLaunch()
            }
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Auto App Events are disabled so Meta cannot classify a free trial as
        // an implicit Purchase. Keep install/session attribution explicitly.
        StartupAppActivationGate.shared.applicationDidBecomeActive()
        AppOpenAdManager.shared.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        appOpenAdPreparationTask?.cancel()
        appOpenAdPreparationTask = nil
        AppOpenAdManager.shared.applicationDidEnterBackground()
    }
}

@MainActor
final class StartupAppActivationGate {
    static let shared = StartupAppActivationGate()

    private var isStartupVisualReady = false
    private var hasPendingActivation = false

    private init() {}

    func applicationDidBecomeActive() {
        hasPendingActivation = true
        activateMetaIfReady()
    }

    func startupVisualDidBecomeReady() {
        isStartupVisualReady = true
        activateMetaIfReady()
    }

    private func activateMetaIfReady() {
        guard isStartupVisualReady, hasPendingActivation else { return }
        hasPendingActivation = false
        AppEvents.shared.activateApp()
    }
}

@MainActor
enum StartupServiceBootstrap {
    private static var hasConfiguredServices = false
    private static var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    static func captureLaunchOptions(
        _ options: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        launchOptions = options
    }

    static func configureIfNeeded() {
        guard !hasConfiguredServices else { return }
        hasConfiguredServices = true

        _ = ApplicationDelegate.shared.application(
            UIApplication.shared,
            didFinishLaunchingWithOptions: launchOptions
        )
        launchOptions = nil

        FirebaseApp.configure()
        AppAnalytics.configure(
            userID: PhotoReviveAuthClient.shared.currentUserID,
            isSignedIn: UserDefaults.standard.bool(forKey: "isLoggedIn"),
            isSubscribed: UserDefaults.standard.bool(forKey: "isSubscribed")
        )
    }
}

@main
struct photoreviveaieditApp: App {
    @UIApplicationDelegateAdaptor(PhotoReviveAppDelegate.self) private var appDelegate

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-forceSignedOut") {
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
        }
        if arguments.contains("-forceUnsubscribed") {
            UserDefaults.standard.set(false, forKey: "isSubscribed")
        }
#endif

        // Diagnostic-only path used to inspect the IDFA on a test device.
        if ProcessInfo.processInfo.arguments.contains("-printIDFA") {
            let status = ATTrackingManager.trackingAuthorizationStatus
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            print("[IDFA] authorizationStatus=\(status.rawValue) advertisingIdentifier=\(idfa)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                    _ = ApplicationDelegate.shared.application(
                        UIApplication.shared,
                        open: url,
                        sourceApplication: nil,
                        annotation: nil
                    )
                }
        }
    }
}
