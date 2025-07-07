//
//  AuthStateObserver.swift
//  pocketscale
//
//  Created by Jake Adams on 7/4/25.
//

import Foundation
import FirebaseAuth
import Combine

class AuthStateObserver: ObservableObject {
    @Published var user: User?
    @Published var isLoading: Bool = true
    private var listenerHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Set up a listener that fires whenever the user signs in or out.
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Update the 'user' property and stop loading
            self?.user = user
            self?.isLoading = false
        }
    }

    deinit {
        // Clean up the listener when the observer is no longer needed.
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}
