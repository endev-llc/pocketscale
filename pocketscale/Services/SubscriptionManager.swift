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
    case inTrial = "inTrial"
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
 * - Starts Trial: "inTrial" (3-day access)
 * - Trial Converts: "professional" (full access)
 * - Trial Expires: "free" (no access unless user subscribes)
 * - User Subscribes: "professional" (full access)
 * - User Cancels: "professional" until period ends, then "free"
 */

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var subscriptionStatus: SubscriptionStatus = .free
    @Published var hasAccessToApp: Bool = false
    
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
        guard let user = Auth.auth().currentUser else { return }
        
        // Step 1: Check Apple's subscription status (source of truth)
        let appleSubscriptionStatus = await checkAppleSubscriptionStatus()
        
        // Step 2: Get current Firebase data for trial information
        do {
            let document = try await Firestore.firestore().collection("users").document(user.uid).getDocument()
            let data = document.data()
            
            let finalStatus = await determineFinalStatus(
                appleStatus: appleSubscriptionStatus,
                firebaseData: data
            )
            
            // Step 3: Update Firebase to match Apple's reality
            await updateFirebaseSubscriptionStatus(finalStatus)
            
            // Step 4: Update local state
            self.subscriptionStatus = finalStatus
            self.hasAccessToApp = (finalStatus == .inTrial || finalStatus == .professional)
            
        } catch {
            print("Error fetching Firebase data: \(error)")
            // If Firebase fails, trust Apple's status
            self.subscriptionStatus = appleSubscriptionStatus == .professional ? .professional : .free
            self.hasAccessToApp = (appleSubscriptionStatus == .professional)
        }
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
    
    private func determineFinalStatus(appleStatus: SubscriptionStatus, firebaseData: [String: Any]?) async -> SubscriptionStatus {
        // If Apple says user has active subscription, they're professional
        if appleStatus == .professional {
            return .professional
        }
        
        // If Apple says no active subscription, check if user is still in trial period
        guard let data = firebaseData,
              let trialEndTimestamp = data["trialEnd"] as? Timestamp else {
            return .free
        }
        
        let trialEndDate = trialEndTimestamp.dateValue()
        let currentFirebaseStatus = data["subscriptionStatus"] as? String ?? "free"
        
        // If user was in trial and trial hasn't expired yet, keep them in trial
        if currentFirebaseStatus == "inTrial" && Date() < trialEndDate {
            return .inTrial
        }
        
        // Trial has expired or user was never in trial, and Apple says no active subscription
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
            let document = try await userDoc.getDocument()
            let currentData = document.data() ?? [:]
            
            // Check current subscription status in Firebase
            let currentStatus = currentData["subscriptionStatus"] as? String ?? "free"
            
            if currentStatus == "free" {
                // This is a new trial - user is starting their first subscription
                let now = Date()
                let trialEnd = Calendar.current.date(byAdding: .day, value: 3, to: now)!
                
                try await userDoc.updateData([
                    "subscriptionStatus": "inTrial",
                    "trialStart": Timestamp(date: now),
                    "trialEnd": Timestamp(date: trialEnd)
                ])
                
                self.subscriptionStatus = .inTrial
                self.hasAccessToApp = true
                
            } else if currentStatus == "inTrial" {
                // User's trial converted to paid subscription
                try await userDoc.updateData([
                    "subscriptionStatus": "professional"
                ])
                
                self.subscriptionStatus = .professional
                self.hasAccessToApp = true
                
            } else {
                // User already has professional status, just ensure they still have access
                self.subscriptionStatus = .professional
                self.hasAccessToApp = true
            }
            
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
