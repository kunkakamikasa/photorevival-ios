//
//  photoreviveaieditApp.swift
//  photoreviveaiedit
//
//  Created by 马颖昆 on 2026/8/15.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import FacebookCore
import AdSupport
import AppTrackingTransparency
import UIKit

final class PhotoReviveAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }
}

@main
struct photoreviveaieditApp: App {
    @UIApplicationDelegateAdaptor(PhotoReviveAppDelegate.self) private var appDelegate

    init() {
        FirebaseApp.configure()
        AppAnalytics.configure(
            userID: PhotoReviveAuthClient.shared.currentUserID,
            isSignedIn: UserDefaults.standard.bool(forKey: "isLoggedIn"),
            isSubscribed: UserDefaults.standard.bool(forKey: "isSubscribed")
        )

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
