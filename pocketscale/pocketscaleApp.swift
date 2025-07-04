//
//  pocketscaleApp.swift
//  pocketscale
//
//  Created by Jake Adams on 6/30/25.
//
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct pocketscaleApp: App {
    
    // Create an instance of the observer. SwiftUI will keep this object alive.
    @StateObject private var authStateObserver = AuthStateObserver()
    
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authStateObserver.user != nil {
                MainView()
            } else {
                AuthView()
            }
        }
    }
}
