//
//  TermsOfServiceView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/14/25.
//

import SwiftUI

struct TermsOfServiceView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Terms of Service for PocketScale")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        Text("Last Updated: July 12, 2025")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 10)

                    Text("Please read these Terms of Service (\"Terms\") carefully before using the PocketScale mobile application (the \"Service\") operated by Endev LLC (\"us\", \"we\", or \"our\").")
                    
                    Text("Your access to and use of the Service is conditioned upon your acceptance of and compliance with these Terms. These Terms apply to all visitors, users, and others who wish to access or use the Service. By accessing or using the Service, you agree to be bound by these Terms. If you disagree with any part of the terms, then you do not have permission to access the Service.")

                    // MARK: - Section 1: The Service
                    SectionView(title: "1. The Service") {
                        Text("PocketScale is a mobile application that uses artificial intelligence (AI) to provide an estimated weight of food items from photos you provide.")
                        
                        Text("IMPORTANT DISCLAIMER: The weight estimations provided by the Service are for informational purposes only. ACCURACY IS NOT GUARANTEED. The estimations may not be precise and should not be relied upon for medical, nutritional, commercial, scientific, or any other purpose where accuracy is critical. We are not responsible for any decisions made based on the information provided by the Service.")
                            .fontWeight(.medium)
                            .padding()
                            .background(Color.yellow.opacity(0.15))
                            .cornerRadius(8)
                    }
                    
                    // MARK: - Section 2: Subscriptions
                    SectionView(title: "2. Subscriptions") {
                        Text("The Service requires a paid subscription to access its features. Subscriptions may be available on a monthly or annual basis.")
                        
                        Text("Payment: All payments are processed through Apple's App Store, from which you originally downloaded the application. You agree to comply with the App Store's terms and conditions.")
                        
                        Text("Free Trial: We may offer a free trial for a limited period. If you do not cancel before the end of the free trial period, you will be automatically charged for the subscription.")
                        
                        Text("Auto-Renewal: Your subscription will automatically renew at the end of each billing cycle unless you cancel it through your App Store account settings at least 24 hours before the end of the current period.")
                        
                        Text("Cancellations: You may cancel your subscription at any time. Your cancellation will take effect at the end of the current billing cycle.")
                    }

                    // MARK: - Section 3: User Accounts
                    SectionView(title: "3. User Accounts") {
                        Text("To use the Service, you must register for an account using Sign in with Apple. You are responsible for safeguarding your account and for any activities or actions under your account. You agree to provide accurate and complete information when you create an account with us.")
                    }
                    
                    // MARK: - Section 4: User Content
                    SectionView(title: "4. User Content") {
                        Text("Our Service allows you to post, link, store, share, and otherwise make available certain information, text, graphics, videos, or other material (\"Content\"), specifically the photos you submit for analysis.")
                        
                        Text("By submitting Content to the Service, you grant us a worldwide, non-exclusive, royalty-free license to use, copy, reproduce, process, adapt, modify, publish, transmit, display, and distribute such Content solely for the purpose of operating, developing, providing, and improving the Service. This includes transmitting your photos to our third-party AI service provider for analysis.")
                        
                        Text("You are responsible for the Content that you post on or through the Service, including its legality, reliability, and appropriateness. You may not submit any Content that is illegal, obscene, defamatory, threatening, or otherwise objectionable.")
                    }
                    
                    // MARK: - Section 5: Intellectual Property
                    SectionView(title: "5. Intellectual Property") {
                        Text("The Service and its original content (excluding Content provided by users), features, and functionality are and will remain the exclusive property of Endev LLC and its licensors. The Service is protected by copyright, trademark, and other laws of both the United States and foreign countries.")
                    }
                    
                    // MARK: - Section 6: Prohibited Uses
                    SectionView(title: "6. Prohibited Uses") {
                        Text("You agree not to use the Service:")
                            .padding(.bottom, 5)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• In any way that violates any applicable national or international law or regulation.")
                            Text("• To reverse engineer, decompile, or otherwise attempt to discover the source code of the App.")
                            Text("• To transmit any worms, viruses, or any code of a destructive nature.")
                        }.padding(.leading)
                    }
                    
                    // MARK: - Section 7: Termination
                    SectionView(title: "7. Termination") {
                        Text("We may terminate or suspend your account and bar access to the Service immediately, without prior notice or liability, under our sole discretion, for any reason whatsoever and without limitation, including but not limited to a breach of the Terms.")
                        Text("If you wish to terminate your account, you may simply discontinue using the Service.")
                    }
                    
                    // MARK: - Section 8: Limitation of Liability
                    SectionView(title: "8. Limitation of Liability") {
                        Text("In no event shall Endev LLC, nor its directors, employees, partners, agents, suppliers, or affiliates, be liable for any indirect, incidental, special, consequential, or punitive damages, including without limitation, loss of profits, data, use, goodwill, or other intangible losses, resulting from (i) your access to or use of or inability to access or use the Service; (ii) any conduct or content of any third party on the Service; (iii) any content obtained from the Service; and (iv) unauthorized access, use, or alteration of your transmissions or content, whether based on warranty, contract, tort (including negligence) or any other legal theory, whether or not we have been informed of the possibility of such damage, and even if a remedy set forth herein is found to have failed of its essential purpose.")
                    }
                    
                    // MARK: - Section 9: Governing Law
                    SectionView(title: "9. Governing Law") {
                        Text("These Terms shall be governed and construed in accordance with the laws of the State of New Mexico, United States, without regard to its conflict of law provisions.")
                    }
                    
                    // MARK: - Section 10: Changes
                    SectionView(title: "10. Changes") {
                        Text("We reserve the right, at our sole discretion, to modify or replace these Terms at any time. We will provide notice of any changes by posting the new Terms of Service within the App and updating the \"Last Updated\" date.")
                        Text("By continuing to access or use our Service after any revisions become effective, you agree to be bound by the revised terms.")
                    }
                    
                    // MARK: - Section 11: Contact Us
                    SectionView(title: "11. Contact Us") {
                        Text("If you have any questions about these Terms, please contact us at:")
                        Text("jake@endev.tech")
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }

                }
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

// Helper view to reduce repetition for section styling
struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            content
        }
    }
}
