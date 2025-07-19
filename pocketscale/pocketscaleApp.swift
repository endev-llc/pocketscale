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
    
    // @AppStorage automatically reads from and writes to UserDefaults.
    // The app will now remember if the access code has been entered.
    @AppStorage("hasEnteredEarlyAccessCode") private var hasEnteredEarlyAccessCode: Bool = false

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // First, check if the user has already been granted early access.
                if !hasEnteredEarlyAccessCode {
                    // If not, show the AccessView. It will handle its own logic
                    // and update the "hasEnteredEarlyAccessCode" value in UserDefaults.
                    AccessView()
                } else if authStateObserver.isLoading {
                    // Show nothing while Firebase determines auth state (prevents flash)
                    Color(.systemBackground)
                        .ignoresSafeArea()
                } else if authStateObserver.user != nil {
                    // User is signed in
                    if subscriptionManager.hasAccessToApp {
                        MainView()
                    } else {
                        SubscriptionView()
                    }
                } else {
                    // User is not signed in, but has passed the access code screen
                    MainView()
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
            // Animate the transition from AccessView to the main app content.
            .animation(.easeInOut(duration: 0.4), value: hasEnteredEarlyAccessCode)
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
