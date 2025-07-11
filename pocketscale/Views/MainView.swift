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
    
    // UI State
    @State private var isWeighing = false
    @State private var showWeight = false
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var analysisResult: WeightAnalysisResponse?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSettings = false
    @State private var shouldAnalyzeAfterCapture = false
    @State private var isShowingShareSheet = false // State for the share sheet
    
    // Animation States
    @State private var focusPoint: CGPoint = .zero
    @State private var showingFocusIndicator = false
    @State private var isAnimatingIn = false

    var body: some View {
        ZStack {
            // Elegant gradient background
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

            VStack(spacing: 0) {
                // MARK: - Top Centered Zone
                VStack(spacing: 0) {
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                        .opacity(isAnimatingIn ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: isAnimatingIn)
                        .zIndex(1)

                    Spacer()

                    cameraView
                        .padding(.horizontal, 24)
                        .opacity(isAnimatingIn ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5).delay(0.2), value: isAnimatingIn)
                    
                    Spacer()
                }

                // MARK: - Bottom Card Zone
                if showWeight, let result = analysisResult {
                    weightResultsView(for: result)
                        // Added padding to create more space below the camera view.
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                        .padding(.bottom)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                } else {
                    footerActionsView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                        .opacity(isAnimatingIn ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5).delay(0.4), value: isAnimatingIn)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $capturedImage, isPresented: $showingImagePicker, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            // Construct the items to share
            if let result = analysisResult, let image = capturedImage {
                let shareText = "I just weighed \(result.overall_food_item) with PocketScale! It's \(String(format: "%.1f", Double(result.total_weight_grams) * 0.035274)) oz (\(result.total_weight_grams)g)."
                ShareSheet(activityItems: [image, shareText])
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: capturedImage) { oldValue, newValue in
            if newValue != nil && shouldAnalyzeAfterCapture && oldValue != newValue {
                shouldAnalyzeAfterCapture = false
                startMeasurement()
            }
        }
        .onAppear {
            if !isAnimatingIn {
                withAnimation {
                    isAnimatingIn = true
                }
            }
        }
    }
    
    // MARK: - Child Views

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PocketScale")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Camera-based food scale")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
            
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemBackground).opacity(0.5))
                    .clipShape(Circle())
            }
            .popover(isPresented: $showingSettings) {
                settingsMenu.presentationCompactAdaptation(.popover)
            }
        }
    }

    // MODIFIED: This view has been refactored to fix the layout bug.
    private var cameraView: some View {
        ZStack {
            SmoothCameraPreview(
                onImageCaptured: handleImageCaptured,
                onTap: handleCameraTap
            )
            // FIXED: By placing the image in an overlay, it is constrained
            // to the bounds of the SmoothCameraPreview, preventing it from
            // expanding the layout horizontally.
            .overlay {
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .onTapGesture {
                            if !isWeighing && !showWeight {
                                capturedImage = nil
                                shouldAnalyzeAfterCapture = false
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .overlay(
                Group {
                    if showingFocusIndicator {
                        FocusIndicator()
                            .position(focusPoint)
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }
                }
            )
            
            if isWeighing {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Analyzing...")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .transition(.opacity)
            }
        }
        .frame(height: 330)
    }

    private func weightResultsView(for result: WeightAnalysisResponse) -> some View {
        VStack(spacing: 24) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("Measurement Complete")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }

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

                HStack(spacing: 12) {
                    Button(action: {
                        isShowingShareSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                            Text("Share")
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
    }

    private var footerActionsView: some View {
        HStack(spacing: 20) {
            Button(action: { cameraManager.toggleFlash() }) {
                Image(systemName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(cameraManager.isFlashEnabled ? .yellow : .primary)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemBackground).opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Button(action: {
                if !isWeighing {
                    shouldAnalyzeAfterCapture = true
                    cameraManager.capturePhoto()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .shadow(radius: 5)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            }

            Spacer()
            
            Button(action: {
                // Turn flash off when opening photo library
                cameraManager.turnFlashOff()
                shouldAnalyzeAfterCapture = true
                showingImagePicker = true
            }) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemBackground).opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .disabled(isWeighing || showWeight)
        .opacity(isWeighing || showWeight ? 0 : 1)
        .animation(.easeInOut, value: isWeighing || showWeight)
    }
    
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

    // MARK: - Methods

    private func handleImageCaptured(_ image: UIImage) {
        // Turn flash off after image is captured
        cameraManager.turnFlashOff()
        if shouldAnalyzeAfterCapture {
            capturedImage = image
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                capturedImage = image
            }
        }
    }
    
    private func handleCameraTap(_ point: CGPoint) {
        guard capturedImage == nil else { return }
        focusPoint = point
        withAnimation { showingFocusIndicator = true }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showingFocusIndicator = false }
        }
    }
    
    private func resetView() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showWeight = false
            isWeighing = false
            analysisResult = nil
            capturedImage = nil
            shouldAnalyzeAfterCapture = false
        }
    }

    private func startMeasurement() {
        guard let image = capturedImage else { return }
        
        withAnimation(.easeInOut) { isWeighing = true }

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
                    resetView()
                }
            }
        }
    }
    
    private func confidenceColor(_ confidence: Int) -> Color {
        if confidence >= 80 { return .green }
        if confidence >= 60 { return .orange }
        return .red
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            Task { await SubscriptionManager.shared.refreshSubscriptionStatus() }
        } catch let signOutError as NSError {
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
            self.showingError = true
        }
    }
}

// MARK: - Focus Indicator

struct FocusIndicator: View {
    var body: some View {
        Circle()
            .strokeBorder(Color.yellow, lineWidth: 2)
            .frame(width: 70, height: 70)
            .opacity(0.8)
    }
}

// MARK: - Share Sheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    MainView()
}
