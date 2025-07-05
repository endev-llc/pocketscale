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

    var body: some View {
        VStack {
            Spacer()
            
            Text("Welcome to PocketScale")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)
            
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
            .frame(height: 50)
            .padding()
            .cornerRadius(8)
            
            Spacer()
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
    }
}

#Preview {
    AuthView()
}