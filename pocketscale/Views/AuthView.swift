//
//  AuthView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/3/25.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var viewModel = AuthenticationViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    // Add this parameter
    let onDismiss: () -> Void
    
    // State for entry animation
    @State private var isAnimating = false
    
    // State for sheet presentations
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Elegant gradient background that adapts to light/dark mode
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

            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 0) {
                            // MARK: - Header Section
                            VStack(spacing: 16) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 80, weight: .light))
                                    .foregroundColor(.accentColor)
                                    .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)

                                Text("Welcome to PocketScale!")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)

                                Text("An account is required to personalize your scanning experience and save your measurements.")
                                    .font(.system(size: 17, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 60) // Space for close button
                            .padding(.bottom, 36)
                            .padding(.horizontal, 24)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : -30)

                            // MARK: - Features Section
                            VStack(alignment: .leading, spacing: 20) {
                                FeatureRow(
                                    icon: "📱",
                                    title: "Scan History",
                                    description: "Save and track all your food measurements over time."
                                )
                                
                                FeatureRow(
                                    icon: "☁️",
                                    title: "Cloud Backup & Sync",
                                    description: "Your measurements are safely stored and synced across devices."
                                )
                                
                                FeatureRow(
                                    icon: "🎯",
                                    title: "Custom Preferences",
                                    description: "Set your preferred units, dietary goals, and measurement settings."
                                )
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : -30)
                            .animation(.easeInOut(duration: 0.8).delay(0.2), value: isAnimating)

                            // MARK: - Action Section
                            VStack(spacing: 20) {
                                // Sign in with Apple Button
                                SignInWithAppleButton(
                                    .signIn,
                                    onRequest: { request in
                                        viewModel.handleSignInWithAppleRequest(request)
                                    },
                                    onCompletion: { result in
                                        viewModel.handleSignInWithAppleCompletion(result)
                                    }
                                )
                                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                .frame(height: 56)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

                                // Terms and Privacy Policy
                                Text(makeAttributedString())
                                    .font(.footnote) // Sets the base font for the whole string
                                    .multilineTextAlignment(.center)
                                    .environment(\.openURL, OpenURLAction { url in
                                        // Handle the link taps to show your sheets
                                        if url.absoluteString == "show-terms" {
                                            showingTermsOfService = true
                                        } else if url.absoluteString == "show-privacy" {
                                            showingPrivacyPolicy = true
                                        }
                                        return .handled // Indicates we've handled the URL
                                    })
                                
                                // Error Message Display
                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                        .multilineTextAlignment(.center)
                                        .transition(.opacity)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 30)
                            .animation(.easeInOut(duration: 0.8).delay(0.6), value: isAnimating)
                        }
                        
                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea()
            
            // Close button
            Button(action: {
                onDismiss()
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
                    
                    // Set the completion handler for successful authentication
                    viewModel.onAuthSuccess = {
                        // Refresh subscription status after successful auth
                        Task {
                            await SubscriptionManager.shared.refreshSubscriptionStatus()
                            // Don't call onDismiss() - let the main app routing handle the flow
                            // The app will automatically show SubscriptionView if no subscription,
                            // or MainView if there is an active subscription
                        }
                    }
                }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView(isPresented: $showingPrivacyPolicy)
        }
        .sheet(isPresented: $showingTermsOfService) {
            TermsOfServiceView(isPresented: $showingTermsOfService)
        }
    }
    
    /// Creates the styled string with embedded links for legal text.
    private func makeAttributedString() -> AttributedString {
        var string = AttributedString("By continuing, you agree to our ")
        
        // Create the "Terms of Service" link
        var termsLink = AttributedString("Terms of Service")
        termsLink.link = URL(string: "show-terms")
        termsLink.font = .footnote.weight(.medium)
        // .link automatically uses the accent color
        
        // Create the "Privacy Policy" link
        var privacyLink = AttributedString("Privacy Policy")
        privacyLink.link = URL(string: "show-privacy")
        privacyLink.font = .footnote.weight(.medium)
        
        // Combine all the parts
        string.append(termsLink)
        string.append(AttributedString(" and "))
        string.append(privacyLink)
        string.append(AttributedString("."))
        
        // Apply the secondary color to the non-link parts
        if let range = string.range(of: "By continuing, you agree to our ") {
            string[range].foregroundColor = .secondary
        }
        if let range = string.range(of: " and ") {
            string[range].foregroundColor = .secondary
        }
        if let range = string.range(of: ".") {
            string[range].foregroundColor = .secondary
        }
        
        return string
    }
}

// MARK: - Preview
#Preview {
    AuthView(onDismiss: {})
}
