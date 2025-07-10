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
    @StateObject private var cameraManager = PersistentCameraManager.shared
    
    @State private var isWeighing = false
    @State private var showWeight = false
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var analysisResult: WeightAnalysisResponse?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSettings = false
    @State private var shouldAnalyzeAfterCapture = false
    
    // Focus animation states
    @State private var focusPoint: CGPoint = .zero
    @State private var showingFocusIndicator = false

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
                // Minimal header - FIXED: Ensure buttons are always interactive
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

                    // Flash button - Always enabled and interactive
                    Button(action: {
                        cameraManager.toggleFlash()
                    }) {
                        Image(systemName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(cameraManager.isFlashEnabled ? .yellow : .primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(false) // Explicitly ensure it's never disabled
                    .buttonStyle(PlainButtonStyle()) // Prevent any default button styling issues
                    .padding(.trailing, 8)

                    // Settings button - Always enabled and interactive
                    Button(action: {
                        showingSettings.toggle()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(false) // Explicitly ensure it's never disabled
                    .buttonStyle(PlainButtonStyle()) // Prevent any default button styling issues
                    .popover(isPresented: $showingSettings) {
                        settingsMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .zIndex(999) // Ensure header is always on top and interactive

                // Instructional text (only when not weighing and not showing results)
                if !isWeighing && !showWeight {
                    Text(capturedImage == nil ? "Tap to focus • Capture to weigh food" : "Image ready for analysis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.bottom, 24)
                }

                // Camera view with overlay for captured image
                ZStack {
                    // Continuous camera preview (never stops)
                    SmoothCameraPreview(
                        onImageCaptured: handleImageCaptured,
                        onTap: handleCameraTap
                    )
                    .frame(width: 320, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        // Focus indicator is now an overlay on the camera preview
                        // to ensure correct positioning.
                        Group {
                            if showingFocusIndicator {
                                FocusIndicator()
                                    .position(focusPoint)
                                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                            }
                        }
                    )
                    
                    // Captured image overlay (shows on top of camera when image exists)
                    // Uses identical positioning and scaling to completely cover camera
                    if let image = capturedImage, !isWeighing {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 320, height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .onTapGesture {
                                // Allow dismissing captured image to go back to live camera
                                if !isWeighing && !showWeight {
                                    capturedImage = nil
                                    shouldAnalyzeAfterCapture = false
                                }
                            }
                    }

                    // Scale platform border
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

                    // Scale weighing surface pattern (only show when there's an image and we're weighing)
                    if capturedImage != nil && isWeighing {
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
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: 1, height: 12)
                                    .offset(y: -100)
                                    .rotationEffect(.degrees(Double(index) * 45))
                                    .animation(.easeInOut(duration: 0.6).delay(Double(index) * 0.1), value: isWeighing)
                            }

                            // Center measurement grid
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 5), spacing: 20) {
                                ForEach(0..<25, id: \.self) { index in
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 2.5, height: 2.5)
                                        .opacity(0.8)
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

                        // Primary weight display
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

                // Action buttons
                if !showWeight {
                    VStack(spacing: 12) {
                        // Capture & Analyze button
                        Button(action: captureAndAnalyze) {
                            HStack(spacing: 12) {
                                if isWeighing && shouldAnalyzeAfterCapture {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                    Text("Analyzing...")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Capture & Analyze")
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
                        
                        // Upload & Analyze button
                        Button(action: uploadAndAnalyze) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Upload & Analyze")
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
                        .disabled(isWeighing)
                        
                        // Manual analyze button (only shown if image exists but not analyzing)
                        if capturedImage != nil && !isWeighing && !shouldAnalyzeAfterCapture {
                            Button(action: startMeasurement) {
                                HStack(spacing: 8) {
                                    Image(systemName: "scale.3d")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Analyze Current Image")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Clear image button (when image exists)
                        if capturedImage != nil && !isWeighing {
                            Button(action: clearImage) {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Clear Image")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $capturedImage, isPresented: $showingImagePicker, sourceType: .photoLibrary)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: capturedImage) { oldValue, newValue in
            // Automatically start analysis when a new image is captured and shouldAnalyzeAfterCapture is true
            if newValue != nil && shouldAnalyzeAfterCapture && oldValue != newValue {
                shouldAnalyzeAfterCapture = false
                startMeasurement()
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                signOut()
                showingSettings = false
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
    
    // MARK: - Action Methods
    
    private func handleImageCaptured(_ image: UIImage) {
        // Show image immediately when user tapped "Capture & Analyze"
        if shouldAnalyzeAfterCapture {
            capturedImage = image  // No animation for immediate display
        } else {
            // Keep animation for other cases (like manual capture)
            withAnimation(.easeInOut(duration: 0.3)) {
                capturedImage = image
            }
        }
    }
    
    private func handleCameraTap(_ point: CGPoint) {
        // Only allow focus when live camera is visible (no captured image)
        guard capturedImage == nil else { return }
        
        focusPoint = point
        
        // Show the focus indicator and then hide it after a delay
        withAnimation {
            showingFocusIndicator = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                showingFocusIndicator = false
            }
        }
    }
    
    private func captureAndAnalyze() {
        shouldAnalyzeAfterCapture = true
        cameraManager.capturePhoto()
    }
    
    private func uploadAndAnalyze() {
        shouldAnalyzeAfterCapture = true
        showingImagePicker = true
    }
    
    private func clearImage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            capturedImage = nil
            shouldAnalyzeAfterCapture = false
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
            analysisResult = nil
            shouldAnalyzeAfterCapture = false
            capturedImage = nil
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
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            Task {
                await SubscriptionManager.shared.refreshSubscriptionStatus()
            }
        } catch let signOutError as NSError {
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
            self.showingError = true
            print("Error signing out: %@", signOutError)
        }
    }
}

// MARK: - Focus Indicator View
struct FocusIndicator: View {
    var body: some View {
        Circle()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 60, height: 60)
            .opacity(0.8)
    }
}

#Preview {
    MainView()
}
