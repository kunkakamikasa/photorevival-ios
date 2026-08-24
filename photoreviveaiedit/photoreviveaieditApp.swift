//
//  photoreviveaieditApp.swift
//  photoreviveaiedit
//
//  Created by 马颖昆 on 2026/8/15.
//

import SwiftUI
import GoogleSignIn

@main
struct photoreviveaieditApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
