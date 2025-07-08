//
//  SubscriptionManager.swift
//  pocketscale
//
//  Created by Jake Adams on 7/4/25.
//

import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFirestore
import Combine

enum SubscriptionStatus: String, CaseIterable {
    case free = "free"
    case professional = "professional"
}

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var hasAccessToApp: Bool = false
    
    private var products: [Product] = []
    private let monthlyProductID = "com.tech.endev.pocketscale.monthly.subscription"
    private let annualProductID = "com.tech.endev.pocketscale.annual.subscription"
    
    // Cache key for UserDefaults
    private let subscriptionCacheKey = "hasActiveSubscription"
    
    private init() {
        // Load cached status immediately (no loading screen)
        loadCachedSubscriptionStatus()
        
        Task {
            await loadProducts()
            await refreshSubscriptionStatus()
        }
        
        // Listen for transaction updates
        Task {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await transaction.finish()
                    await refreshSubscriptionStatus()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Instant Status Loading (No Loading Screen)
    private func loadCachedSubscriptionStatus() {
        // Load from cache immediately - assume user has access if they had it before
        self.hasAccessToApp = UserDefaults.standard.bool(forKey: subscriptionCacheKey)
    }
    
    private func cacheSubscriptionStatus(_ hasAccess: Bool) {
        UserDefaults.standard.set(hasAccess, forKey: subscriptionCacheKey)
    }
    
    // MARK: - Background Subscription Refresh
    func refreshSubscriptionStatus() async {
        guard Auth.auth().currentUser != nil else {
            await MainActor.run {
                self.hasAccessToApp = false
                self.cacheSubscriptionStatus(false)
            }
            return
        }
        
        // Check Apple's subscription status in background
        var hasActiveSubscription = false
        
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == monthlyProductID || transaction.productID == annualProductID {
                    hasActiveSubscription = true
                    break
                }
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }
        
        await MainActor.run {
            self.hasAccessToApp = hasActiveSubscription
            self.cacheSubscriptionStatus(hasActiveSubscription)
        }
        
        // Update Firebase for analytics (non-blocking)
        await updateFirebaseSubscriptionStatus(hasActiveSubscription ? .professional : .free)
    }
    
    // MARK: - Product Loading
    private func loadProducts() async {
        do {
            products = try await Product.products(for: [monthlyProductID, annualProductID])
            print("Loaded products: \(products.map { $0.id })")
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    // MARK: - Purchase Methods
    func startFreeTrial() async throws {
        guard let product = products.first(where: { $0.id == monthlyProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        guard Auth.auth().currentUser != nil else {
            throw SubscriptionError.notAuthenticated
        }
        
        try await purchaseProduct(product)
    }
    
    func purchaseMonthlySubscription() async throws {
        guard let product = products.first(where: { $0.id == monthlyProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        try await purchaseProduct(product)
    }
    
    func purchaseAnnualSubscription() async throws {
        guard let product = products.first(where: { $0.id == annualProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        try await purchaseProduct(product)
    }
    
    private func purchaseProduct(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshSubscriptionStatus()
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.purchasePending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    // MARK: - Restore Purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }
    
    // MARK: - Product Access
    var monthlyProduct: Product? {
        return products.first(where: { $0.id == monthlyProductID })
    }
    
    var annualProduct: Product? {
        return products.first(where: { $0.id == annualProductID })
    }
    
    // MARK: - Helper Methods
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // Write subscription status to Firebase for analytics (never read from Firebase)
    private func updateFirebaseSubscriptionStatus(_ status: SubscriptionStatus) async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            // Use setData with merge to create document if it doesn't exist, or update if it does
            try await Firestore.firestore().collection("users").document(user.uid).setData([
                "uid": user.uid,
                "email": user.email ?? "",
                "name": user.displayName ?? "",
                "isAppleUser": true,
                "subscriptionStatus": status.rawValue,
                "lastSubscriptionUpdate": Timestamp(date: Date())
            ], merge: true)
            print("Updated Firebase subscription status to: \(status.rawValue)")
        } catch {
            print("Error updating subscription status in Firebase: \(error)")
            // Don't throw error - this is just for analytics, not critical
        }
    }
}

enum SubscriptionError: LocalizedError {
    case productNotFound
    case notAuthenticated
    case userCancelled
    case purchasePending
    case verificationFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found"
        case .notAuthenticated:
            return "User not authenticated"
        case .userCancelled:
            return "Purchase was cancelled"
        case .purchasePending:
            return "Purchase is pending approval"
        case .verificationFailed:
            return "Purchase verification failed"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
