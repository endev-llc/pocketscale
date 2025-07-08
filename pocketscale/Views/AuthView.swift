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
    
    // State for entry animation
    @State private var isAnimating = false

    var body: some View {
        ZStack {
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
                                Image(systemName: "scale.3d")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.accentColor)
                                    .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)

                                Text("Welcome to PocketScale!")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)

                                Text("The camera-based food scale in your pocket.")
                                    .font(.system(size: 17, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 30)
                            .padding(.bottom, 36)
                            .padding(.horizontal, 24)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : -30)

                            // MARK: - Features Section
                            VStack(alignment: .leading, spacing: 20) {
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
                                Text("By continuing, you agree to our **Terms of Service** and **Privacy Policy**.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    // Note: For actual links, you would wrap this in a view that can handle URLs.
                                    // For simplicity, we are using Markdown-style text here.
                                
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
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    AuthView()
}
