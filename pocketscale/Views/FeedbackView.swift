//
//  FeedbackView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/11/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FeedbackView: View {
    @Binding var isPresented: Bool
    @State private var feedbackMessage: String = ""
    @State private var isSending = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var submissionSuccessful = false

    // To handle the "Your Feedback" placeholder text
    private let placeholderText = "Tell us what you think or what features you'd like to see..."

    var body: some View {
        NavigationView {
            ZStack {
                // Consistent gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.15),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Custom TextEditor with placeholder
                    ZStack(alignment: .topLeading) {
                        if feedbackMessage.isEmpty {
                            Text(placeholderText)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }
                        
                        TextEditor(text: $feedbackMessage)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .padding(12)
                            .background(Color(.white))
                            .cornerRadius(16)
                            .frame(height: 250)
                    }

                    // Send Button
                    Button(action: sendFeedback) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Send Feedback")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .shadow(color: .accentColor.opacity(0.4), radius: 10, y: 5)
                    }
                    .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Send Us Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if submissionSuccessful {
                            isPresented = false // Dismiss sheet on success
                        }
                    }
                )
            }
        }
    }

    private func sendFeedback() {
        guard let user = Auth.auth().currentUser else {
            alertTitle = "Error"
            alertMessage = "You must be signed in to send feedback."
            submissionSuccessful = false
            showAlert = true
            return
        }

        isSending = true
        let db = Firestore.firestore()
        db.collection("feedback").addDocument(data: [
            "userId": user.uid,
            "email": user.email ?? "N/A",
            "name": user.displayName ?? "N/A",
            "message": feedbackMessage,
            "timestamp": Timestamp(date: Date())
        ]) { error in
            isSending = false
            if let error = error {
                alertTitle = "Error"
                alertMessage = "There was an issue sending your feedback. Please try again.\n\(error.localizedDescription)"
                submissionSuccessful = false
            } else {
                alertTitle = "Success"
                alertMessage = "Thank you for your feedback!"
                submissionSuccessful = true
                feedbackMessage = ""
            }
            showAlert = true
        }
    }
}
