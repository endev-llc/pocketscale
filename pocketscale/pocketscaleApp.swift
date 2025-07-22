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
    @State private var showingSubscriptionView = false

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
                    // Always show MainView regardless of auth state
                    MainView()
                        .fullScreenCover(isPresented: $showingSubscriptionView) {
                            SubscriptionView()
                        }
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
            .animation(.easeInOut(duration: 0.3), value: authStateObserver.user != nil)
            .animation(.easeInOut(duration: 0.3), value: subscriptionManager.hasAccessToApp)
            .onAppear {
                // Show subscription view if user doesn't have access
                if !subscriptionManager.hasAccessToApp {
                    showingSubscriptionView = true
                }
            }
            .onChange(of: subscriptionManager.hasAccessToApp) { oldValue, newValue in
                // Hide subscription view if user gains access
                if newValue {
                    showingSubscriptionView = false
                } else {
                    // Show subscription view if user loses access
                    showingSubscriptionView = true
                }
            }
        }
    }
}
