//
//  AuthenticationViewModel.swift
//  pocketscale
//
//  Created by Jake Adams on 7/4/25.
//

import Foundation
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

class AuthenticationViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var currentNonce: String?
    
    // Completion handler for successful authentication
    var onAuthSuccess: (() -> Void)?

    func handleSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
    }

    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple Authorization failed."
                return
            }
            guard let nonce = currentNonce else {
                errorMessage = "Invalid state: A login callback was received, but no login request was sent."
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                errorMessage = "Unable to fetch identity token."
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to serialize token string from data: \(appleIDToken.debugDescription)"
                return
            }
            
            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                             rawNonce: nonce,
                                                             fullName: appleIDCredential.fullName)

            Auth.auth().signIn(with: credential) { (authResult, error) in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                guard let user = authResult?.user else { return }
                
                let db = Firestore.firestore()
                let userDoc = db.collection("users").document(user.uid)
                
                // Check if user already exists
                userDoc.getDocument { (document, error) in
                    if let error = error {
                        self.errorMessage = "Error checking user document: \(error)"
                        return
                    }
                    
                    if let document = document, document.exists {
                        // User already exists, no action needed
                        print("User already exists")
                        // Call success handler - sign in successful
                        DispatchQueue.main.async {
                            self.onAuthSuccess?()
                        }
                    } else {
                        // New user, create basic profile document (no subscription status)
                        userDoc.setData([
                            "uid": user.uid,
                            "email": user.email ?? "",
                            "name": user.displayName ?? "",
                            "isAppleUser": true,
                            "signUpTime": Timestamp(date: Date())
                        ]) { err in
                            if let err = err {
                                self.errorMessage = "Error writing document: \(err)"
                            } else {
                                // Call success handler - sign up successful
                                DispatchQueue.main.async {
                                    self.onAuthSuccess?()
                                }
                            }
                        }
                    }
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}
