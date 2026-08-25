//
//  photoreviveaieditApp.swift
//  photoreviveaiedit
//
//  Created by 马颖昆 on 2026/8/15.
//

import SwiftUI
import GoogleSignIn
import AdSupport
import AppTrackingTransparency

@main
struct photoreviveaieditApp: App {
    init() {
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
                }
        }
    }
}
