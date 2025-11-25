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
                    LaunchScreenView()
                } else {
                    MainView()
                }
            }
            .environmentObject(authStateObserver)
            .environmentObject(subscriptionManager)
        }
    }
}

// MARK: - Launch Screen
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.15),
                    Color(.systemBackground)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "scalemass")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.accentColor)
                
                Text("PocketScale")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Camera-based food scale")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
}
