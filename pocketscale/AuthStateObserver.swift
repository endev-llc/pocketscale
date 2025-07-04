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
    private var listenerHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Set up a listener that fires whenever the user signs in or out.
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Update the 'user' property, which will cause any listening views to re-render.
            self?.user = user
        }
    }

    deinit {
        // Clean up the listener when the observer is no longer needed.
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}