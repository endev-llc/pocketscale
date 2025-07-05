//
//  MainView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import SwiftUI
import AVFoundation
import FirebaseAuth

struct MainView: View {
    @StateObject private var geminiService = GeminiService()
    @State private var isWeighing = false
    @State private var showWeight = false
    @State private var currentWeight = 0.0
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var analysisResult: WeightAnalysisResponse?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingActionSheet = false
    
    // New state to control the settings menu popover
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // Sophisticated gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Minimal header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PocketScale")
                            .font(.system(size: 28, weight: .light, design: .default))
                            .foregroundColor(.primary)
                        Text("Digital Food Scale")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Updated button to toggle the settings menu
                    Button(action: {
                        showingSettings.toggle()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .ultraLight))
                            .foregroundColor(.secondary)
                    }
                    // Popover menu for settings
                    .popover(isPresented: $showingSettings) {
                        settingsMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)

                // Instructional text (only when not weighing and not showing results)
                if !isWeighing && !showWeight {
                    Text(capturedImage == nil ? "Take a photo to weigh food" : "Image ready for analysis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.bottom, 24)
                }

                // Digital scale platform area
                ZStack {
                    // Scale platform background with subtle scale-like styling
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        .shadow(color: .black.opacity(0.05), radius: 40, x: 0, y: 20)
                        .frame(width: 320, height: 320)

                    // Image display area
                    Group {
                        if let image = capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 320, height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .scaleEffect(isWeighing ? 1.05 : 1.0)
                                .animation(.easeInOut(duration: 0.5), value: isWeighing)
                        } else {
                            // Placeholder when no image
                            VStack(spacing: 16) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.secondary)
                                Text("Tap to add photo")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 320, height: 320)
                        }
                    }
                    .onTapGesture {
                        if !isWeighing {
                            showingActionSheet = true
                        }
                    }

                    // Scale platform border with subtle gradient
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [Color(.quaternaryLabel), Color(.quaternaryLabel).opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .frame(width: 320, height: 320)

                    // Scale weighing surface pattern (more scale-like) - only show when there's an image
                    if capturedImage != nil {
                        ZStack {
                            // Concentric circles for scale-like appearance
                            ForEach([60, 120, 180, 240], id: \.self) { diameter in
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                    .frame(width: CGFloat(diameter), height: CGFloat(diameter))
                            }

                            // Radial measurement marks
                            ForEach(0..<8, id: \.self) { index in
                                Rectangle()
                                    .fill(Color.white.opacity(isWeighing ? 0.6 : 0.3))
                                    .frame(width: 1, height: 12)
                                    .offset(y: -100)
                                    .rotationEffect(.degrees(Double(index) * 45))
                                    .animation(.easeInOut(duration: 0.6).delay(Double(index) * 0.1), value: isWeighing)
                            }

                            // Center measurement grid (refined)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 5), spacing: 20) {
                                ForEach(0..<25, id: \.self) { index in
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: isWeighing ? 2.5 : 1.5, height: isWeighing ? 2.5 : 1.5)
                                        .opacity(isWeighing ? 0.8 : 0.4)
                                        .scaleEffect(isWeighing ? 1.0 : 0.8)
                                        .animation(
                                            .easeInOut(duration: 0.6)
                                            .delay(Double(index) * 0.03),
                                            value: isWeighing
                                        )
                                }
                            }
                            .frame(width: 140, height: 140)
                        }
                    }

                    // Status display during weighing
                    if isWeighing {
                        VStack(spacing: 8) {
                            Text("Analyzing...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                            // Progress indicator
                            HStack(spacing: 4) {
                                ForEach(0..<4) { index in
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(isWeighing ? 1.0 : 0.5)
                                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                                        .animation(
                                            .easeInOut(duration: 0.5)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                            value: isWeighing
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 32)

                // Accuracy indicator (only when not weighing and not showing results)
                if !isWeighing && !showWeight && capturedImage != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        Text("AI-Powered Analysis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 24)
                }

                // Weight results panel
                if showWeight, let result = analysisResult {
                    VStack(spacing: 24) {
                        // Status indicator
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Measurement Complete")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        // Primary weight display - improved readability
                        HStack(alignment: .bottom, spacing: 8) {
                            Text("\(String(format: "%.1f", Double(result.total_weight_grams) * 0.035274))")
                                .font(.system(size: 58, weight: .light, design: .rounded))
                                .foregroundColor(.primary)
                                .kerning(-1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("oz")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("(\(result.total_weight_grams)g)")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                            .offset(y: -10)

                            Spacer()
                        }

                        // Metadata
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ITEM")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .tracking(1)
                                    Text(result.overall_food_item)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("CONFIDENCE")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .tracking(1)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(confidenceColor(result.confidence_percentage))
                                            .frame(width: 6, height: 6)
                                        Text("\(result.confidence_percentage)%")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(confidenceColor(result.confidence_percentage))
                                    }
                                }
                            }

                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Save Weight")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.blue)
                                    .cornerRadius(14)
                                }

                                Button(action: resetView) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.blue)
                                        .frame(width: 50, height: 50)
                                        .background(Color(.tertiarySystemBackground))
                                        .cornerRadius(14)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }

                Spacer()

                // Elegant buttons (when not showing results)
                if !showWeight {
                    VStack(spacing: 12) {
                        // Take Photo / Analyze button
                        if capturedImage == nil {
                            Button(action: { showingActionSheet = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Take Photo")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [Color.green, Color.green.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                        } else {
                            Button(action: startMeasurement) {
                                HStack(spacing: 12) {
                                    if isWeighing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                        Text("Analyzing...")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "scale.3d")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("Analyze Weight")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                                .scaleEffect(isWeighing ? 0.98 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isWeighing)
                            }
                            .disabled(isWeighing)
                            
                            // Retake photo button
                            Button(action: { showingActionSheet = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.rotate")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Retake Photo")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                            .disabled(isWeighing)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $capturedImage, isPresented: $showingCamera)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $capturedImage, isPresented: $showingImagePicker, sourceType: .photoLibrary)
        }
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(
                title: Text("Select Photo"),
                buttons: [
                    .default(Text("Camera")) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showingCamera = true
                        }
                    },
                    .default(Text("Photo Library")) {
                        showingImagePicker = true
                    },
                    .cancel()
                ]
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    // Extracted settings menu view
    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                signOut()
                showingSettings = false // Dismiss the popover
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .foregroundColor(.red)
                .padding()
            }
        }
    }
    
    private func confidenceColor(_ confidence: Int) -> Color {
        if confidence >= 80 {
            return .green
        } else if confidence >= 60 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func resetView() {
        withAnimation(.spring()) {
            showWeight = false
            isWeighing = false
            capturedImage = nil
            analysisResult = nil
        }
    }

    private func startMeasurement() {
        guard let image = capturedImage else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isWeighing = true
        }

        Task {
            do {
                let result = try await geminiService.analyzeFood(image: image)
                
                await MainActor.run {
                    self.analysisResult = result
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isWeighing = false
                        self.showWeight = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.isWeighing = false
                    }
                }
            }
        }
    }
    
    // New function to handle signing out
    private func signOut() {
        do {
            try Auth.auth().signOut()
        } catch let signOutError as NSError {
            // Present an error to the user if sign-out fails.
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
            self.showingError = true
            print("Error signing out: %@", signOutError)
        }
    }
}

#Preview {
    MainView()
}
