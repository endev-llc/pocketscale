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
    @State private var showMainViewDirectly = false

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
                    if showMainViewDirectly {
                        MainView()
                    } else if authStateObserver.user == nil {
                        AuthView(onDismiss: { showMainViewDirectly = true })
                    } else if !subscriptionManager.hasAccessToApp {
                        SubscriptionView(onDismiss: { showMainViewDirectly = true })
                    } else {
                        MainView()
                    }
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
            .animation(.easeInOut(duration: 0.3), value: authStateObserver.user != nil)
            .animation(.easeInOut(duration: 0.3), value: subscriptionManager.hasAccessToApp)
            .animation(.easeInOut(duration: 0.3), value: showMainViewDirectly)
        }
    }
}
