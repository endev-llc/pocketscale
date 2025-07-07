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
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var selectedPlan: SubscriptionPlan = .annual
    
    enum SubscriptionPlan {
        case monthly
        case annual
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Friendly Header
                VStack(spacing: 16) {
                    Image(systemName: "scale.3d")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.top, 30)
                    
                    Text("PocketScale Pro")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("🎯 AI-powered mobile food scale")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 30)
                
                // Core Features - improved text wrapping
                VStack(spacing: 16) {
                    FeatureRow(
                        icon: "📱",
                        title: "Camera-Based Weighing",
                        description: "No physical scale needed—just point and weigh"
                    )
                    
                    FeatureRow(
                        icon: "🧠",
                        title: "AI-Powered Accuracy",
                        description: "Advanced computer vision for precise measurements"
                    )
                    
                    FeatureRow(
                        icon: "✨",
                        title: "Always With You",
                        description: "Your portable scale that fits in your pocket"
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 25)
                
                // Compact Plans
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
                
                // Trial Info
                Text("🎉 3-Day Free Trial • Cancel Anytime")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
                
                // Prominent CTA Button
                Button(action: startSubscription) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Text("Start Free Trial")
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .disabled(isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Restore
                Button(action: {
                    Task { await subscriptionManager.restorePurchases() }
                }) {
                    Text("Restore Purchases")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
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
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
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
                    .foregroundColor(isSelected ? .blue : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.05) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
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
                .background(Color(.systemGray6))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
    }
}

#Preview {
    SubscriptionView()
}
