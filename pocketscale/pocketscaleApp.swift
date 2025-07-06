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
                if authStateObserver.user != nil {
                    if subscriptionManager.isLoadingStatus || subscriptionManager.hasAccessToApp {
                        MainView()
                    } else {
                        SubscriptionView()
                    }
                } else {
                    AuthView()
                }
            }
            .onChange(of: authStateObserver.user) { oldUser, newUser in
                // Immediately update subscription status when user signs in
                if oldUser == nil && newUser != nil {
                    Task {
                        await subscriptionManager.updateSubscriptionStatus()
                    }
                }
            }
        }
    }
}
