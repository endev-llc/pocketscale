//
//  CameraView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Singleton Camera Manager for Persistent Session
class PersistentCameraManager: NSObject, ObservableObject {
    static let shared = PersistentCameraManager()
    
    private let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentDevice: AVCaptureDevice?
    
    @Published var isSessionRunning = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    // Callbacks for image capture
    var onImageCaptured: ((UIImage) -> Void)?
    
    private override init() {
        super.init()
        checkCameraAuthorization()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        // Handle app lifecycle to pause/resume camera appropriately
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        stopSession()
    }
    
    @objc private func appWillEnterForeground() {
        if authorizationStatus == .authorized {
            startSession()
        }
    }
    
    private func checkCameraAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .authorized:
            configureCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.configureCameraSession()
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Camera access denied")
        @unknown default:
            break
        }
    }
    
    private func configureCameraSession() {
        guard authorizationStatus == .authorized else { return }
        
        session.beginConfiguration()
        
        // Clear existing inputs and outputs
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        // Set session preset for optimal quality and performance
        session.sessionPreset = .high
        
        // Configure camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ Failed to setup camera input")
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(cameraInput) {
            session.addInput(cameraInput)
            currentDevice = camera
        }
        
        // Configure camera settings for optimal performance
        configureCameraSettings(camera)
        
        // Add photo output
        photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            // Configure photo output
            if let connection = photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
        
        session.commitConfiguration()
        
        // Start session on background queue
        startSession()
        
        print("✅ Persistent camera session configured successfully")
    }
    
    private func configureCameraSettings(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            
            // Optimize focus for better performance
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            
            // Set exposure mode
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            
            // Set frame rate for smooth video (30 FPS)
            if let format = camera.activeFormat.videoSupportedFrameRateRanges.first {
                let targetFrameRate: Int32 = 30
                camera.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: targetFrameRate)
                camera.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: targetFrameRate)
            }
            
            // Enable low light boost if available
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure camera settings: \(error)")
        }
    }
    
    func startSession() {
        guard !isSessionRunning && authorizationStatus == .authorized else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                print("✅ Camera session started")
            }
        }
    }
    
    func stopSession() {
        guard isSessionRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = false
                print("🛑 Camera session stopped")
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existingLayer = previewLayer {
            return existingLayer
        }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }
    
    func capturePhoto() {
        guard isSessionRunning else {
            print("❌ Camera session not running")
            return
        }
        
        var settings = AVCapturePhotoSettings()
        
        // Use HEIF format if available for better compression
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
        // Enable high resolution if available
        settings.isHighResolutionPhotoEnabled = photoOutput.isHighResolutionCaptureEnabled
        
        photoOutput.capturePhoto(with: settings, delegate: self)
        print("📸 Photo capture initiated")
    }
    
    func setFocus(at point: CGPoint, in view: UIView) {
        guard let device = currentDevice,
              let previewLayer = previewLayer else { return }
        
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to set focus: \(error)")
        }
    }
}

// MARK: - Photo Capture Delegate
extension PersistentCameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            print("❌ Photo capture error: \(error!)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let capturedImage = UIImage(data: imageData) else {
            print("❌ Failed to process captured photo")
            return
        }
        
        // Send the raw image immediately, optimize in background
        DispatchQueue.main.async { [weak self] in
            self?.onImageCaptured?(capturedImage)
            print("✅ Photo captured and sent immediately")
        }
        
        // Optimize image in background (for future use if needed)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let optimizedImage = self?.optimizeImage(capturedImage) ?? capturedImage
            // Could store optimized version for later use if needed
        }
    }
    
    private func optimizeImage(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
        let compressionQuality: CGFloat = 0.8
        
        // If image is already small enough, just compress it
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            if let compressedData = image.jpegData(compressionQuality: compressionQuality),
               let compressedImage = UIImage(data: compressedData) {
                return compressedImage
            }
            return image
        }
        
        // Calculate the scaling factor to maintain aspect ratio
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        // Use UIGraphicsImageRenderer for better memory management
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // Compress the resized image
        if let compressedData = resizedImage.jpegData(compressionQuality: compressionQuality),
           let finalImage = UIImage(data: compressedData) {
            return finalImage
        }
        
        return resizedImage
    }
}

// MARK: - Smooth Camera Preview View
struct SmoothCameraPreview: UIViewRepresentable {
    @ObservedObject private var cameraManager = PersistentCameraManager.shared
    let onImageCaptured: (UIImage) -> Void
    let onTap: ((CGPoint) -> Void)?
    
    init(onImageCaptured: @escaping (UIImage) -> Void, onTap: ((CGPoint) -> Void)? = nil) {
        self.onImageCaptured = onImageCaptured
        self.onTap = onTap
    }
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let previewView = CameraPreviewUIView()
        let previewLayer = cameraManager.getPreviewLayer()
        
        previewView.layer.addSublayer(previewLayer)
        previewView.previewLayer = previewLayer
        
        // Set up image capture callback
        cameraManager.onImageCaptured = onImageCaptured
        
        // Add tap gesture for focus
        if onTap != nil {
            let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            previewView.addGestureRecognizer(tapGesture)
        }
        
        return previewView
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Update preview layer frame
        uiView.previewLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: SmoothCameraPreview
        
        init(_ parent: SmoothCameraPreview) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            
            // Call the parent's tap handler first (for UI feedback)
            parent.onTap?(point)
            
            // Set camera focus at tapped point (on background queue to prevent UI blocking)
            if let view = gesture.view {
                DispatchQueue.global(qos: .userInitiated).async {
                    PersistentCameraManager.shared.setFocus(at: point, in: view)
                }
            }
        }
    }
}

// MARK: - Camera Preview UI View
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Legacy Image Picker for Photo Library
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool
    let sourceType: UIImagePickerController.SourceType
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        
        if sourceType == .photoLibrary {
            picker.mediaTypes = ["public.image"]
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            print("📷 Photo library picker finished")
            
            if let pickedImage = info[.originalImage] as? UIImage {
                print("✅ Successfully got image from photo library")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    let optimizedImage = self.optimizeImage(pickedImage)
                    self.parent.image = optimizedImage
                    
                    print("✅ Photo library image set, dismissing picker")
                    self.parent.isPresented = false
                }
            } else {
                print("❌ Failed to get image from photo library")
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isPresented = false
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("📷 Photo library picker cancelled")
            DispatchQueue.main.async { [weak self] in
                self?.parent.isPresented = false
            }
        }
        
        private func optimizeImage(_ image: UIImage) -> UIImage {
            let maxDimension: CGFloat = 1024
            let compressionQuality: CGFloat = 0.8
            
            guard image.size.width > maxDimension || image.size.height > maxDimension else {
                if let compressedData = image.jpegData(compressionQuality: compressionQuality),
                   let compressedImage = UIImage(data: compressedData) {
                    return compressedImage
                }
                return image
            }
            
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            
            if let compressedData = resizedImage.jpegData(compressionQuality: compressionQuality),
               let finalImage = UIImage(data: compressedData) {
                return finalImage
            }
            
            return resizedImage
        }
    }
}
