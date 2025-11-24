//
//  MainView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import SwiftUI
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct MainView: View {
    @EnvironmentObject var authStateObserver: AuthStateObserver
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var geminiService = GeminiService()
    @StateObject private var cameraManager = PersistentCameraManager.shared
    
    // TrueDepth Integration
    @State private var isVolumeMode = false
    @StateObject private var trueDepthManager = CameraManager()
    @State private var showingTrueDepthOverlay = false
    
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
    @State private var showingFeedbackSheet = false // State for the feedback sheet
    @State private var showingDeleteConfirmation = false // State for the delete account alert
    @State private var showingScanHistory = false // State for scan history sheet
    @State private var showingAuthView = false
    @State private var showingSubscriptionView = false
    @State private var showingCameraPermission = false
    @State private var showingPreferences = false // New state for preferences view


    // Animation States
    @State private var focusPoint: CGPoint = .zero
    @State private var showingFocusIndicator = false
    @State private var isAnimatingIn = false
    
    // User Preferences
    @AppStorage("unitPreference") private var unitPreference: UnitPreference = .ounces


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

                    // Mode Toggle
                    Picker("Mode", selection: $isVolumeMode) {
                        Text("Standard").tag(false)
                        Text("Volume").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .opacity(isAnimatingIn ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).delay(0.1), value: isAnimatingIn)

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
        // MARK: - MODIFIED
        // This now uses the completion handler from AuthView to manage the presentation flow.
        .fullScreenCover(isPresented: $showingAuthView) {
            AuthView { result in
                // First, always dismiss the AuthView
                showingAuthView = false
                
                // Then, check the result to see what to do next
                if result == .signedInAndFree {
                    // If the user is free, present the subscription view.
                    // A slight delay is needed to allow the first sheet to finish its dismiss animation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showingSubscriptionView = true
                    }
                }
                // For .signedInAndSubscribed or .cancelled, we do nothing else.
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            // Construct the items to share
            if let result = analysisResult, let image = capturedImage {
                let shareText = "I just weighed \(result.overall_food_item) with PocketScale! It's \(String(format: "%.1f", Double(result.total_weight_grams) * 0.035274)) oz (\(result.total_weight_grams)g)."
                ShareSheet(activityItems: [image, shareText])
            }
        }
        .sheet(isPresented: $showingFeedbackSheet) {
            FeedbackView(isPresented: $showingFeedbackSheet)
        }
        .sheet(isPresented: $showingScanHistory) {
            ScanHistoryView(isPresented: $showingScanHistory)
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView(isPresented: $showingPreferences)
        }
        .fullScreenCover(isPresented: $showingSubscriptionView) {
            SubscriptionView(onDismiss: { showingSubscriptionView = false })
        }
        .fullScreenCover(isPresented: $showingTrueDepthOverlay) {
            if let depthImage = trueDepthManager.capturedDepthImage {
                AutoFlowOverlayView(
                    depthImage: depthImage,
                    photo: trueDepthManager.capturedPhoto,
                    cameraManager: trueDepthManager,
                    onComplete: {
                        showingTrueDepthOverlay = false
                        trueDepthManager.capturedDepthImage = nil
                        trueDepthManager.capturedPhoto = nil
                    }
                )
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .alert("Camera Permission Required", isPresented: $showingCameraPermission) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("PocketScale needs camera access to scan and analyze your food for weight estimation.")
        }
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone.")
        }
        .onChange(of: capturedImage) { oldValue, newValue in
            if newValue != nil && shouldAnalyzeAfterCapture && oldValue != newValue {
                shouldAnalyzeAfterCapture = false
                startMeasurement()
            }
        }
        .onChange(of: authStateObserver.user) { oldValue, newValue in
            checkAndPresentRequiredViews()
        }
        .onChange(of: subscriptionManager.hasAccessToApp) { oldValue, newValue in
            checkAndPresentRequiredViews()
        }
        .onChange(of: isVolumeMode) { _, newValue in
            if newValue {
                // Switching to Volume mode
                cameraManager.stopSession()
                trueDepthManager.startSession()
            } else {
                // Switching back to Standard mode
                trueDepthManager.stopSession()
                cameraManager.startSession()
            }
        }
        .onChange(of: trueDepthManager.capturedDepthImage) { _, newImage in
            if newImage != nil && isVolumeMode {
                showingTrueDepthOverlay = true
            }
        }
        .onAppear {
            if !isAnimatingIn {
                withAnimation {
                    isAnimatingIn = true
                }
            }
            // Check if we need to present auth or subscription views
            checkAndPresentRequiredViews()
        }
    }
    
    // MARK: - Helper Method
    private func checkAndPresentRequiredViews() {
        // Don't present if we're already showing something
        if showingAuthView || showingSubscriptionView {
            return
        }
        
        if authStateObserver.user == nil {
            showingAuthView = true
        } else if !subscriptionManager.hasAccessToApp {
            showingSubscriptionView = true
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
                
                // Scan History Button - requires auth
                Button(action: {
                    if authStateObserver.user == nil {
                        showingAuthView = true
                    } else {
                        showingScanHistory.toggle()
                    }
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground).opacity(0.5))
                        .clipShape(Circle())
                }

                // Settings Button
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
            FlexibleCameraPreview(
                isVolumeMode: isVolumeMode,
                persistentManager: cameraManager,
                trueDepthManager: trueDepthManager,
                onImageCaptured: handleImageCaptured,
                onTap: handleCameraTap
            )
            .overlay {
                if let image = capturedImage, !isVolumeMode {
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
                if unitPreference == .grams {
                    Text("\(result.total_weight_grams)")
                        .font(.system(size: 58, weight: .light, design: .rounded))
                        .foregroundColor(.primary)
                        .kerning(-1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("g")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("(\(String(format: "%.1f", Double(result.total_weight_grams) * 0.035274)) oz)")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .offset(y: -10)
                } else {
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
                }
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
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 23, weight: .medium))
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

            // MODIFIED: Check auth first, then subscription
            Button(action: {
                if authStateObserver.user == nil {
                    showingAuthView = true
                } else if subscriptionManager.hasAccessToApp {
                    if cameraManager.authorizationStatus != .authorized {
                        showingCameraPermission = true
                    } else {
                        if !isWeighing {
                            if isVolumeMode {
                                // Trigger TrueDepth flow
                                trueDepthManager.captureDepthAndPhoto()
                            } else {
                                // Standard flow
                                shouldAnalyzeAfterCapture = true
                                cameraManager.capturePhoto()
                            }
                        }
                    }
                } else {
                    showingSubscriptionView = true
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
            
            // MODIFIED: Check auth first, then subscription
            Button(action: {
                if authStateObserver.user == nil {
                    showingAuthView = true
                } else if subscriptionManager.hasAccessToApp {
                    // Turn flash off when opening photo library
                    cameraManager.turnFlashOff()
                    shouldAnalyzeAfterCapture = true
                    showingImagePicker = true
                } else {
                    showingSubscriptionView = true
                }
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
                
                // Preferences Button - always available
                Button(action: {
                    showingSettings = false
                    showingPreferences = true
                }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Preferences")
                    }
                    .padding()
                }

                if authStateObserver.user == nil {
                    // Menu for unauthenticated users
                    Divider()
                    Button(action: {
                        showingSettings = false
                        showingAuthView = true
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Sign In")
                        }
                        .padding()
                    }
                } else {
                    // Menu for authenticated users
                    Divider()
                    Button(action: {
                        showingSettings = false
                        showingFeedbackSheet = true
                    }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Send Us Feedback")
                        }
                        .padding()
                    }
                    Divider()
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
                    Divider()
                    Button(action: {
                        showingSettings = false
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Account")
                        }
                        .foregroundColor(.red)
                        .padding()
                    }
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
                
                // Immediately update the UI on the main thread
                await MainActor.run {
                    self.analysisResult = result
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.isWeighing = false
                        self.showWeight = true
                    }
                }
                
                // Start a new Task to save the scan in the background (only if user is authenticated)
                if authStateObserver.user != nil {
                    Task {
                        await saveScan(result: result, image: image)
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

    private func saveScan(result: WeightAnalysisResponse, image: UIImage) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // 1. Upload image to Firebase Storage
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }
        let storageRef = Storage.storage().reference()
        let imageId = UUID().uuidString
        let imageRef = storageRef.child("scans/\(userId)/\(imageId).jpg")

        do {
            _ = try await imageRef.putDataAsync(imageData)
            let downloadURL = try await imageRef.downloadURL()

            // 2. Prepare scan data for Firestore
            let scanData: [String: Any] = [
                "userId": userId,
                "timestamp": Timestamp(date: Date()),
                "imageUrl": downloadURL.absoluteString,
                "overall_food_item": result.overall_food_item,
                "constituent_food_items": result.constituent_food_items.map { ["name": $0.name, "weight_grams": $0.weight_grams] },
                "total_weight_grams": result.total_weight_grams,
                "confidence_percentage": result.confidence_percentage
            ]

            // 3. Save to Firestore using a batch write for atomicity
            let db = Firestore.firestore()
            let batch = db.batch()

            // Path for root `scans` collection
            let rootScanRef = db.collection("scans").document()
            
            // Path for user's subcollection `userScans`
            let userScanRef = db.collection("users").document(userId).collection("userScans").document(rootScanRef.documentID)

            batch.setData(scanData, forDocument: rootScanRef)
            batch.setData(scanData, forDocument: userScanRef)

            try await batch.commit()
            print("✅ Scan saved successfully to both collections.")

        } catch {
            print("❌ Failed to save scan: \(error.localizedDescription)")
            // Optionally update UI to show this specific error
            await MainActor.run {
                self.errorMessage = "Failed to save scan to history: \(error.localizedDescription)"
                self.showingError = true
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
    
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else {
            self.errorMessage = "You must be signed in to delete your account."
            self.showingError = true
            return
        }

        let db = Firestore.firestore()
        let userDocRef = db.collection("users").document(user.uid)

        // 1. Delete Firestore document
        userDocRef.delete { error in
            if let error = error {
                self.errorMessage = "Error deleting user data: \(error.localizedDescription)"
                self.showingError = true
                return
            }

            // 2. Delete Firebase Auth user
            user.delete { error in
                if let error = error {
                    self.errorMessage = "Error deleting account: \(error.localizedDescription)"
                    self.showingError = true
                } else {
                    // 3. Sign out, which will trigger view redirection via AuthStateObserver
                    print("Account deleted successfully.")
                    signOut()
                }
            }
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

// MARK: - Flexible Camera Preview
struct FlexibleCameraPreview: UIViewRepresentable {
    let isVolumeMode: Bool
    @ObservedObject var persistentManager: PersistentCameraManager
    @ObservedObject var trueDepthManager: CameraManager
    let onImageCaptured: ((UIImage) -> Void)?
    let onTap: ((CGPoint) -> Void)?
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let previewView = CameraPreviewUIView()
        updatePreviewLayer(for: previewView)
        
        // Set up image capture callback for standard mode
        if !isVolumeMode {
            persistentManager.onImageCaptured = onImageCaptured
        }
        
        // Add tap gesture if provided
        if onTap != nil {
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            previewView.addGestureRecognizer(tapGesture)
        }
        
        return previewView
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Update preview layer if mode changed
        let currentSession = uiView.previewLayer?.session
        let targetSession = isVolumeMode ? trueDepthManager.session : persistentManager.getPreviewLayer().session
        
        if currentSession !== targetSession {
            updatePreviewLayer(for: uiView)
        }
        
        uiView.previewLayer?.frame = uiView.bounds
    }
    
    private func updatePreviewLayer(for view: CameraPreviewUIView) {
        // Remove old layer
        view.previewLayer?.removeFromSuperlayer()
        
        // Add new layer based on mode
        let previewLayer: AVCaptureVideoPreviewLayer
        if isVolumeMode {
            previewLayer = AVCaptureVideoPreviewLayer(session: trueDepthManager.session)
        } else {
            previewLayer = persistentManager.getPreviewLayer()
        }
        previewLayer.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        previewLayer.frame = view.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: FlexibleCameraPreview
        
        init(_ parent: FlexibleCameraPreview) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !parent.isVolumeMode else { return } // Only handle tap in standard mode
            
            let point = gesture.location(in: gesture.view)
            parent.onTap?(point)
            
            if let view = gesture.view {
                DispatchQueue.global(qos: .userInitiated).async {
                    PersistentCameraManager.shared.setFocus(at: point, in: view)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .environmentObject(AuthStateObserver())
        .environmentObject(SubscriptionManager.shared)
}
