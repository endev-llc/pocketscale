//
//  AccessView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/19/25.
//

import SwiftUI

struct AccessView: View {
    // This view now directly controls the value persisted in UserDefaults.
    // When this value is set to true, the main app view will react and transition away.
    @AppStorage("hasEnteredEarlyAccessCode") private var hasEnteredEarlyAccessCode: Bool = false
    
    @State private var accessCode: String = ""
    @State private var showError: Bool = false
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
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer()

                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(.accentColor)
                                .shadow(color: .accentColor.opacity(0.3), radius: 10, y: 5)

                            Text("Early Access")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)

                            Text("Enter your code to unlock PocketScale.")
                                .font(.system(size: 17, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : -30)
                        .animation(.easeInOut(duration: 0.8), value: isAnimating)

                        // Access Code Input
                        VStack {
                            TextField("Access Code", text: $accessCode)
                                .font(.system(size: 18, weight: .regular, design: .rounded))
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(16)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(showError ? Color.red : Color.clear, lineWidth: 2)
                                )
                        }
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 30)
                        .animation(.easeInOut(duration: 0.8).delay(0.2), value: isAnimating)


                        // Submit Button
                        Button(action: verifyCode) {
                            Text("Unlock")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                                .shadow(color: .accentColor.opacity(0.4), radius: 10, y: 5)
                        }
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 30)
                        .animation(.easeInOut(duration: 0.8).delay(0.4), value: isAnimating)

                        if showError {
                            Text("Invalid access code. Please try again.")
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .transition(.opacity.animation(.easeInOut))
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .onAppear {
            if !isAnimating {
                withAnimation {
                    isAnimating = true
                }
            }
        }
    }

    private func verifyCode() {
        // The check is case-insensitive. "EARLY", "Early", "early", etc., will all work.
        if accessCode.uppercased() == "EARLY" {
            withAnimation {
                // Set the persisted value to true.
                // The main app view will react to this change.
                hasEnteredEarlyAccessCode = true
            }
        } else {
            withAnimation {
                showError = true
            }
        }
    }
}
