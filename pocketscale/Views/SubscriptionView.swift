//
//  SubscriptionView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/5/25.
//


//
//  SubscriptionView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/4/25.
//

import SwiftUI

struct SubscriptionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // App Icon/Logo area
                VStack(spacing: 16) {
                    Image(systemName: "scale.3d")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.blue)
                    
                    Text("PocketScale Pro")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.primary)
                    
                    Text("Unlock precise AI-powered food weighing")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 60)
                
                // Features list
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "camera.fill", title: "AI Photo Analysis", description: "Get accurate weights from photos")
                    FeatureRow(icon: "chart.bar.fill", title: "Weight Tracking", description: "Save and track your measurements")
                    FeatureRow(icon: "brain.head.profile", title: "Smart Recognition", description: "Identify food items automatically")
                    FeatureRow(icon: "icloud.fill", title: "Cloud Sync", description: "Access your data anywhere")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                
                // Pricing info
                VStack(spacing: 8) {
                    Text("3-Day Free Trial")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Then $4.99/month")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Cancel anytime during trial")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 32)
                
                Spacer()
                
                // CTA Button
                Button(action: {
                    startFreeTrial()
                }) {
                    HStack(spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .medium))
                        }
                        
                        Text(isLoading ? "Starting Trial..." : "Start 3-Day Free Trial!")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isLoading)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // Terms and restore
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }) {
                        Text("Restore Purchases")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 50)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startFreeTrial() {
        isLoading = true
        
        Task {
            do {
                try await subscriptionManager.startFreeTrial()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    SubscriptionView()
}