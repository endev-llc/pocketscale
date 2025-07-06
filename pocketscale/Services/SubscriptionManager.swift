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

/*
 * Subscription Flow:
 * 1. App checks Apple's StoreKit for current subscription status (source of truth)
 * 2. App updates Firebase to match Apple's reality
 * 3. App determines user access based on final status
 *
 * Status Transitions:
 * - New User: "free" (no access to app)
 * - User Subscribes: "professional" (full access)
 * - User Cancels: "professional" until period ends, then "free"
 */

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var subscriptionStatus: SubscriptionStatus = .free
    @Published var hasAccessToApp: Bool = false
    @Published var isLoadingStatus: Bool = true
    
    private var products: [Product] = []
    private var purchaseState = Set<AnyCancellable>()
    private let monthlyProductID = "com.tech.endev.pocketscale.monthly.subscription"
    private let annualProductID = "com.tech.endev.pocketscale.annual.subscription"
    
    private init() {
        Task {
            await updateSubscriptionStatus()
            await loadProducts()
        }
        
        // Listen for transaction updates
        Task {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await handleTransaction(transaction)
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
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
    
    // MARK: - Subscription Status Management
    func updateSubscriptionStatus() async {
        guard let user = Auth.auth().currentUser else {
            self.isLoadingStatus = false
            return
        }
        
        // Step 1: Check Apple's subscription status (source of truth)
        let appleSubscriptionStatus = await checkAppleSubscriptionStatus()
        
        // Step 2: Determine final status based on Apple's status only
        let finalStatus = determineFinalStatus(appleStatus: appleSubscriptionStatus)
        
        // Step 3: Update Firebase to match Apple's reality
        await updateFirebaseSubscriptionStatus(finalStatus)
        
        // Step 4: Update local state
        self.subscriptionStatus = finalStatus
        self.hasAccessToApp = (finalStatus == .professional)
        self.isLoadingStatus = false
    }
    
    private func checkAppleSubscriptionStatus() async -> SubscriptionStatus {
        // Check for active subscription from Apple (either monthly or annual)
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == monthlyProductID || transaction.productID == annualProductID {
                    return .professional
                }
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }
        return .free
    }
    
    private func determineFinalStatus(appleStatus: SubscriptionStatus) -> SubscriptionStatus {
        // If Apple says user has active subscription, they're professional
        if appleStatus == .professional {
            return .professional
        }
        
        // Otherwise, user is free
        return .free
    }
    
    // MARK: - Free Trial
    func startFreeTrial() async throws {
        // Default to monthly subscription for free trial
        guard let product = products.first(where: { $0.id == monthlyProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        guard let user = Auth.auth().currentUser else {
            throw SubscriptionError.notAuthenticated
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await handleTransaction(transaction)
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.purchasePending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    // MARK: - Purchase Subscriptions
    func purchaseMonthlySubscription() async throws {
        guard let product = products.first(where: { $0.id == monthlyProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await handleTransaction(transaction)
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.purchasePending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    func purchaseAnnualSubscription() async throws {
        guard let product = products.first(where: { $0.id == annualProductID }) else {
            throw SubscriptionError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await handleTransaction(transaction)
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.purchasePending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    }
    
    // MARK: - Transaction Handling
    private func handleTransaction(_ transaction: StoreKit.Transaction) async {
        guard let user = Auth.auth().currentUser else { return }
        
        let db = Firestore.firestore()
        let userDoc = db.collection("users").document(user.uid)
        
        do {
            // User has a valid subscription - set to professional
            try await userDoc.updateData([
                "subscriptionStatus": "professional"
            ])
            
            self.subscriptionStatus = .professional
            self.hasAccessToApp = true
            
            await transaction.finish()
            
        } catch {
            print("Error handling transaction: \(error)")
        }
    }
    
    // MARK: - Restore Purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
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
    
    private func updateFirebaseSubscriptionStatus(_ status: SubscriptionStatus) async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            try await Firestore.firestore().collection("users").document(user.uid).updateData([
                "subscriptionStatus": status.rawValue
            ])
        } catch {
            print("Error updating subscription status: \(error)")
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
