//
//  PrivacyPolicyView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/14/25.
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Privacy Policy for PocketScale")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        
                        Text("Last Updated: July 12, 2025")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 10)

                    Text("Welcome to PocketScale (\"we,\" \"us,\" or \"our\"). We are committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application, PocketScale (the \"App\"). Please read this privacy policy carefully. If you do not agree with the terms of this privacy policy, please do not access the application.")

                    Text("We reserve the right to make changes to this Privacy Policy at any time and for any reason. We will alert you about any changes by updating the \"Last Updated\" date of this Privacy Policy.")

                    // MARK: - Collection of Information
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. COLLECTION OF YOUR INFORMATION")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        
                        Text("We may collect information about you in a variety of ways. The information we may collect via the App depends on the content and materials you use, and includes:")
                        
                        Text("Personal Data")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("When you register with the App using Apple Sign-In, we collect personal information, such as your name and email address, and a unique user ID assigned to you by our system. You are under no obligation to provide us with personal information of any kind; however, your refusal to do so will prevent you from using the App.")
                        
                        Text("User Content")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("To provide the core functionality of the App, we collect the photos or videos you capture within the App or select from your device's photo library. This content is transmitted to our third-party service provider to perform the weight analysis. We also collect the content of any messages you send to us through the in-app feedback or customer support forms.")
                        
                        Text("Purchase Information")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("We collect information related to your subscription status (e.g., \"free\" or \"professional\") to manage access to the App's features. All payment processing for subscriptions is handled by Apple's App Store, and we do not collect or store any direct payment information, such as credit card numbers.")
                    }
                    
                    // MARK: - Use of Information
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2. USE OF YOUR INFORMATION")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        
                        Text("Having accurate information about you permits us to provide you with a smooth, efficient, and customized experience. Specifically, we may use information collected about you via the App to:")
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• Create and manage your account.")
                            Text("• Enable the core functionality of the App, which includes analyzing your submitted photos to provide weight estimations.")
                            Text("• Process payments and manage your subscriptions.")
                            Text("• Respond to your feedback, questions, and provide customer support.")
                            Text("• Monitor and analyze usage and trends to improve your experience with the App.")
                        }.padding(.leading)
                    }
                    
                    // MARK: - Disclosure of Information
                    VStack(alignment: .leading, spacing: 10) {
                        Text("3. DISCLOSURE OF YOUR INFORMATION")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        
                        Text("We may share information we have collected about you in certain situations. Your information may be disclosed as follows:")
                        
                        Text("By Law or to Protect Rights")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("If we believe the release of information about you is necessary to respond to legal process, to investigate or remedy potential violations of our policies, or to protect the rights, property, and safety of others, we may share your information as permitted or required by any applicable law, rule, or regulation.")
                        
                        Text("Third-Party Service Providers")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("We may share your information with third parties that perform services for us or on our behalf. These services include:")
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("• **Google (Firebase & Gemini AI):** We use Google's Firebase services for user authentication, database storage (for your account information and feedback), and hosting. To provide weight estimations, the photos you submit are sent to Google's Gemini AI service for analysis. Google's use of this data is governed by their own privacy policies.")
                            Text("• **Apple (App Store & Sign-In):** We use Apple for user authentication via Sign-In with Apple and for processing subscription payments through the App Store.")
                        }.padding(.leading)
                        
                        Text("We do not sell your personal information to third parties.")
                    }
                    
                    // MARK: - Data Security
                    VStack(alignment: .leading, spacing: 10) {
                        Text("4. DATA SECURITY")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("We use administrative, technical, and physical security measures to help protect your personal information. While we have taken reasonable steps to secure the personal information you provide to us, please be aware that despite our efforts, no security measures are perfect or impenetrable, and no method of data transmission can be guaranteed against any interception or other type of misuse.")
                    }
                    
                    // MARK: - Data Retention
                    VStack(alignment: .leading, spacing: 10) {
                        Text("5. DATA RETENTION")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("We will retain your personal information and user content for as long as your account remains active. You may delete your account at any time, which will result in the deletion of your personal information from our primary production servers.")
                    }

                    // MARK: - Children's Privacy
                    VStack(alignment: .leading, spacing: 10) {
                        Text("6. CHILDREN'S PRIVACY")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("We do not knowingly solicit information from or market to children under the age of 13. If you become aware of any data we have collected from children under age 13, please contact us using the contact information provided below.")
                    }
                    
                    // MARK: - Contact Us
                    VStack(alignment: .leading, spacing: 10) {
                        Text("7. CONTACT US")
                             .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("If you have questions or comments about this Privacy Policy, please contact us at:")
                        Text("jake@endev.tech")
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }
                }
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .padding()
            }
            .navigationTitle("Privacy Policy")
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
