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
    @State private var showSubscriptionAfterLogin = false
    @State private var hasSeenUserBefore = false

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
                    MainView()
                        .fullScreenCover(isPresented: $showSubscriptionAfterLogin) {
                            SubscriptionView()
                        }
                } else {
                    MainView()
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
            .animation(.easeInOut(duration: 0.3), value: authStateObserver.user != nil)
            .animation(.easeInOut(duration: 0.3), value: subscriptionManager.hasAccessToApp)
            .onChange(of: authStateObserver.user) { oldUser, newUser in
                // Track if we've seen any user (including on app startup)
                if newUser != nil {
                    if hasSeenUserBefore {
                        // Only show subscription view for actual sign-ins (not first time seeing user)
                        if oldUser == nil {
                            Task {
                                await subscriptionManager.refreshSubscriptionStatus()
                                // Only show subscription view if the user does not have access
                                if !subscriptionManager.hasAccessToApp {
                                    showSubscriptionAfterLogin = true
                                }
                            }
                        }
                    } else {
                        // First time seeing a user - mark as seen but don't show subscription
                        hasSeenUserBefore = true
                    }
                }
            }
        }
    }
}
