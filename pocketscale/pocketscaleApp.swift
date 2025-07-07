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
                } else if authStateObserver.user != nil {
                    if subscriptionManager.hasAccessToApp {
                        MainView()
                    } else {
                        SubscriptionView()
                    }
                } else {
                    AuthView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authStateObserver.user != nil)
            .animation(.easeInOut(duration: 0.3), value: subscriptionManager.hasAccessToApp)
            .onChange(of: authStateObserver.user) { oldUser, newUser in
                // Refresh subscription status when user signs in (background refresh)
                if oldUser == nil && newUser != nil {
                    Task {
                        await subscriptionManager.refreshSubscriptionStatus()
                    }
                }
            }
        }
    }
}
