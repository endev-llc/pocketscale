//
//  SubscriptionView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/5/25.
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var selectedPlan: SubscriptionPlan = .annual
    
    // State for entry animation
    @State private var isAnimating = false
    
    enum SubscriptionPlan {
        case monthly
        case annual
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Elegant gradient background that matches AuthView
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
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Header Section
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 40, weight: .light)) // Adjusted weight for consistency
                                .foregroundColor(.accentColor)
                                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)
                            
                            Text("Try PocketScale!")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("The camera-based food scale in your pocket.")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60) // Increased top padding to make space for the close button
                        .padding(.bottom, 30)
                        .padding(.horizontal, 24)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : -30)
                        
                        // MARK: - Core Features Section
                        VStack(spacing: 16) {
                            FeatureRow(
                                icon: "🍅",
                                title: "Always With You",
                                description: "Your portable food scale that fits in your pocket."
                            )
                            FeatureRow(
                                icon: "📷",
                                title: "Camera-Based Weighing",
                                description: "No physical scale needed—just point and weigh."
                            )
                            FeatureRow(
                                icon: "🧠",
                                title: "AI-Powered Accuracy",
                                description: "Advanced computer vision for precise measurements."
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 25)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : -30)
                        .animation(.easeInOut(duration: 0.8).delay(0.2), value: isAnimating)

                        // MARK: - Plans Section
                        VStack(spacing: 8) {
                            CompactPlanCard(
                                isSelected: selectedPlan == .annual,
                                title: "Annual Plan",
                                price: formatPrice(for: subscriptionManager.annualProduct),
                                period: "year",
                                badge: "⭐ " + calculateSavings(),
                                isPopular: true,
                                action: { selectedPlan = .annual }
                            )
                            
                            CompactPlanCard(
                                isSelected: selectedPlan == .monthly,
                                title: "Monthly Plan",
                                price: formatPrice(for: subscriptionManager.monthlyProduct),
                                period: "month",
                                badge: nil,
                                isPopular: false,
                                action: { selectedPlan = .monthly }
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 30)
                        .animation(.easeInOut(duration: 0.8).delay(0.4), value: isAnimating)

                        // MARK: - Action Section
                        VStack(spacing: 20) {
                            Text("🎉 3-Day Free Trial • Cancel Anytime")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Button(action: startSubscription) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.9)
                                    } else {
                                        Text("Start Free Trial!")
                                            .font(.system(size: 20, weight: .bold))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56) // Consistent height
                                .background(Color.accentColor) // Using accent color for consistency
                                .clipShape(Capsule()) // Consistent shape
                                .shadow(color: .accentColor.opacity(0.4), radius: 10, y: 5)
                            }
                            .disabled(isLoading)
                            
                            Button(action: {
                                Task { await subscriptionManager.restorePurchases() }
                            }) {
                                Text("Restore Purchases")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 30)
                        .animation(.easeInOut(duration: 0.8).delay(0.6), value: isAnimating)
                    }
                }
            }
            
            // Close button
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color(.systemGray5).opacity(0.7))
                    .clipShape(Circle())
            }
            .padding()
            .padding(.top, 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                isAnimating = true
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: subscriptionManager.hasAccessToApp) { oldValue, newValue in
            if newValue {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    // MARK: - Functions (Unchanged)
    private func startSubscription() {
        isLoading = true
        
        Task {
            do {
                if selectedPlan == .monthly {
                    try await subscriptionManager.purchaseMonthlySubscription()
                } else {
                    try await subscriptionManager.purchaseAnnualSubscription()
                }
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
    
    private func formatPrice(for product: Product?) -> String {
        guard let product = product else { return "$--" }
        return product.displayPrice
    }
    
    private func calculateSavings() -> String {
        guard let monthlyProduct = subscriptionManager.monthlyProduct,
              let annualProduct = subscriptionManager.annualProduct else {
            return "Save 33%"
        }
        
        let monthlyPricePerYear = monthlyProduct.price * 12
        let annualPrice = annualProduct.price
        let savings = monthlyPricePerYear - annualPrice
        let savingsPercentage = (savings / monthlyPricePerYear) * 100
        
        let percentageValue = NSDecimalNumber(decimal: savingsPercentage).doubleValue
        return "Save \(Int(percentageValue))%"
    }
}

// MARK: - Helper Views (Unchanged)
struct CompactPlanCard: View {
    let isSelected: Bool
    let title: String
    let price: String
    let period: String
    let badge: String?
    let isPopular: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 2) {
                        Text(price)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Text("/\(period)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12) // Slightly more rounded corners
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(icon)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 3) {
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

// MARK: - Preview
#Preview {
    SubscriptionView()
}
