//
//  pocketscaleApp.swift
//  pocketscale
//
//  Created by Jake Adams on 6/30/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct pocketscaleApp: App {
    @StateObject private var authStateObserver = AuthStateObserver()
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authStateObserver.isLoading {
                    // Show nothing while Firebase determines auth state (prevents flash)
                    Color(.systemBackground)
                        .ignoresSafeArea()
                } else {
                    MainView()
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
        }
    }
}
