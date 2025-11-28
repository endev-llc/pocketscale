//
//  CameraManager.swift
//  pocketscale
//
//  Created by Jake Adams on 11/21/25.
//

import Foundation
import SwiftUI
import AVFoundation
import UIKit
import CoreGraphics

// ========== NEW: MODE ENUM ==========
enum CameraMode {
    case standard  // Back camera for standard photo capture
    case volume    // Front TrueDepth camera for depth + photo
}

// MARK: - Flash Overlay Window
class FlashOverlayWindow: UIWindow {
    static let shared = FlashOverlayWindow()
    private var originalBrightness: CGFloat = 0
    
    private init() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            super.init(frame: windowScene.coordinateSpace.bounds)
            self.windowScene = windowScene
        } else {
            super.init(frame: UIScreen.main.bounds)
        }
        self.windowLevel = .alert + 1
        self.isHidden = true
        self.backgroundColor = .clear
        
        let flashView = UIView(frame: self.bounds)
        flashView.backgroundColor = .white
        flashView.tag = 999
        self.addSubview(flashView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func flash(duration: TimeInterval = 1.0) {
        guard let flashView = self.viewWithTag(999) else { return }
        
        // Store original brightness and crank it to maximum
        originalBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        
        self.isHidden = false
        flashView.alpha = 1.0  // Instant full brightness
        
        // Hold at full brightness for the duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            flashView.alpha = 0
            self.isHidden = true
            // Restore original brightness
            UIScreen.main.brightness = self.originalBrightness
        }
    }
}

// MARK: - Enhanced Camera Manager
class CameraManager: NSObject, ObservableObject, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate {
    // ========== EXISTING PROPERTIES (UNCHANGED) ==========
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.example.sessionQueue")
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthDataQueue = DispatchQueue(label: "com.example.depthQueue")

    @Published var showError = false
    @Published var isProcessing = false
    @Published var lastSavedFileName: String?
    @Published var showShareSheet = false
    @Published var capturedDepthImage: UIImage?
    @Published var capturedPhoto: UIImage?
    @Published var croppedFileToShare: URL?
    @Published var hasOutline = false
    @Published var show3DView = false
    @Published var croppedPhoto: UIImage?
    @Published var refinementMask: UIImage?
    @Published var refinementImageFrame: CGRect = .zero
    @Published var refinementDepthImageSize: CGSize = .zero
    @Published var samManagerDepth = MobileSAMManager()
    @Published var samManagerPhoto = MobileSAMManager()
    @Published var isEncodingImages = false
    private var initialCroppedCSV: URL?
    
    var errorMessage = ""
    var fileToShare: URL?
    var refinementMaskForBackground: UIImage?

    private var latestDepthData: AVDepthData?
    private var currentDepthData: AVDepthData?
    private var currentPhotoData: Data?
    private var captureCompletion: ((Bool) -> Void)?
    var rawDepthData: AVDepthData?
    private var cameraCalibrationData: AVCameraCalibrationData?
    var uploadedCSVData: [DepthPoint] = []
    
    var maskBoundaryPoints: [(x: Int, y: Int)] = []
    var maskDimensions: CGSize = .zero
    var boundaryDepthPoints: [DepthPoint] = []
    var backgroundSurfacePoints: [DepthPoint] = []
    var backgroundSurfacePointsForPlane: [DepthPoint] = []

    // ========== NEW: STANDARD MODE PROPERTIES ==========
    @Published var mode: CameraMode = .standard
    @Published var isSessionRunning = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var isFlashEnabled = false
    private var currentDevice: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    var onImageCaptured: ((UIImage) -> Void)?  // Callback for standard mode

    // ========== EXISTING INIT (UNCHANGED) ==========
    override init() {
        super.init()
        checkCameraAuthorization()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // ========== NEW: NOTIFICATION SETUP ==========
    private func setupNotifications() {
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
    
    // ========== NEW: AUTHORIZATION CHECK ==========
    private func checkCameraAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Camera access denied")
            DispatchQueue.main.async { self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video) }
        @unknown default:
            break
        }
    }

    // ========== MODIFIED: MODE-AWARE SESSION SETUP ==========
    private func setupSession() {
        guard authorizationStatus == .authorized else { return }
        
        sessionQueue.async {
            self.session.beginConfiguration()

            // Clear existing inputs and outputs
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            
            // Set session preset
            self.session.sessionPreset = .high

            // Configure based on mode
            if self.mode == .volume {
                // ========== EXISTING TRUEDEPTH SETUP (UNCHANGED) ==========
                guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
                    self.presentError("TrueDepth camera is not available on this device.")
                    return
                }

                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(videoDeviceInput) {
                        self.session.addInput(videoDeviceInput)
                        self.currentDevice = device
                    } else {
                        self.presentError("Could not add video device input.")
                        return
                    }
                } catch {
                    self.presentError("Could not create video device input: \(error)")
                    return
                }

                // Add depth output (TrueDepth only)
                if self.session.canAddOutput(self.depthDataOutput) {
                    self.session.addOutput(self.depthDataOutput)
                    self.depthDataOutput.isFilteringEnabled = true
                    self.depthDataOutput.setDelegate(self, callbackQueue: self.depthDataQueue)
                } else {
                    self.presentError("Could not add depth data output.")
                    return
                }
                
                // Add photo output
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                } else {
                    self.presentError("Could not add photo output.")
                    return
                }
                
            } else {
                // ========== NEW: STANDARD MODE SETUP ==========
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let cameraInput = try? AVCaptureDeviceInput(device: camera) else {
                    print("❌ Failed to setup camera input")
                    self.session.commitConfiguration()
                    return
                }
                
                if self.session.canAddInput(cameraInput) {
                    self.session.addInput(cameraInput)
                    self.currentDevice = camera
                }
                
                // Configure camera settings for standard mode
                self.configureCameraSettings(camera)
                
                // Add photo output (no depth for standard mode)
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    self.photoOutput.isDepthDataDeliveryEnabled = false
                    
                    // Configure photo output connection
                    if let connection = self.photoOutput.connection(with: .video) {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                }
            }

            self.session.commitConfiguration()
            
            self.startSession()
            
            print("✅ Camera session configured successfully for \(self.mode) mode")
        }
    }
    
    // ========== NEW: CAMERA SETTINGS CONFIGURATION (FROM PERSISTENTCAMERAMANAGER) ==========
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

    // ========== MODIFIED: SESSION START (ENHANCED WITH PUBLISHED STATE) ==========
    func startSession() {
        guard authorizationStatus == .authorized else {
            if authorizationStatus != .authorized {
                print("❌ Camera not authorized")
            }
            return
        }
        
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                    print("✅ Camera session started")
                }
            }
        }
    }

    // ========== MODIFIED: SESSION STOP (ENHANCED WITH PUBLISHED STATE) ==========
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    print("🛑 Camera session stopped")
                }
            }
        }
    }
    
    // ========== NEW: MODE SWITCHING ==========
    func switchMode(to newMode: CameraMode) {
        guard newMode != mode else { return }
        
        print("🔄 Switching camera mode from \(mode) to \(newMode)")
        stopSession()
        mode = newMode
        setupSession()
        startSession()
    }
    
    // ========== NEW: PREVIEW LAYER GETTER ==========
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let existingLayer = previewLayer {
            return existingLayer
        }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }
    
    // ========== NEW: STANDARD MODE PHOTO CAPTURE ==========
    func capturePhotoStandard() {
        guard isSessionRunning, mode == .standard else {
            print("❌ Camera session not running or not in standard mode")
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
        print("📸 Standard photo capture initiated")
    }
    
    // ========== NEW: FOCUS CONTROL ==========
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
    
    // ========== NEW: FLASH CONTROL ==========
    func toggleFlash() {
        // For volume mode (front camera), just toggle the state without hardware control
        if mode == .volume {
            DispatchQueue.main.async {
                self.isFlashEnabled.toggle()
            }
            return
        }
        
        // For standard mode (back camera), control hardware torch
        guard let device = currentDevice, device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.torchMode == .on {
                device.torchMode = .off
                isFlashEnabled = false
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                isFlashEnabled = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to toggle flash: \(error)")
        }
    }
    
    func turnFlashOff() {
        guard let device = currentDevice, device.hasTorch, device.torchMode == .on else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.isFlashEnabled = false
            }
        } catch {
            print("❌ Failed to turn off flash: \(error)")
        }
    }

    // ========== EXISTING: ERROR PRESENTATION (UNCHANGED) ==========
    private func presentError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
            self.isProcessing = false
        }
    }

    // ========== EXISTING: PROCESS UPLOADED CSV (UNCHANGED) ==========
    func processUploadedCSV(_ fileURL: URL) {
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let csvContent = try String(contentsOf: fileURL)
                let depthPoints = self.parseCSVContent(csvContent)
                
                self.uploadedCSVData = depthPoints
                
                let depthImage = self.createDepthVisualizationFromCSV(depthPoints)
                
                DispatchQueue.main.async {
                    self.capturedDepthImage = depthImage
                    self.capturedPhoto = nil
                    self.fileToShare = fileURL
                    self.isProcessing = false
                    
                    self.lastSavedFileName = fileURL.lastPathComponent
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to process CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }
    
    // ========== EXISTING: CSV PARSING (UNCHANGED) ==========
    private func parseCSVContent(_ content: String) -> [DepthPoint] {
        var points: [DepthPoint] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            if line.hasPrefix("#") || line.contains("x,y,depth") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            let components = line.components(separatedBy: ",")
            if components.count >= 3 {
                guard let x = Float(components[0]),
                      let y = Float(components[1]),
                      let depth = Float(components[2]) else { continue }
                
                if depth.isNaN || depth.isInfinite || depth <= 0 { continue }
                
                points.append(DepthPoint(x: x, y: y, depth: depth))
            }
        }
        
        return points
    }
    
    // ========== EXISTING: CREATE DEPTH VISUALIZATION FROM CSV (UNCHANGED) ==========
    private func createDepthVisualizationFromCSV(_ points: [DepthPoint]) -> UIImage? {
        guard !points.isEmpty else { return nil }
        
        let maxX = Int(ceil(points.map { $0.x }.max() ?? 0))
        let maxY = Int(ceil(points.map { $0.y }.max() ?? 0))
        
        let originalWidth = maxX + 1
        let originalHeight = maxY + 1
        
        let rotatedWidth = originalHeight
        let rotatedHeight = originalWidth
        
        let depthValues = points.map { $0.depth }.filter { !$0.isNaN && !$0.isInfinite && $0 > 0 }
        guard !depthValues.isEmpty else { return nil }
        
        let sortedDepths = depthValues.sorted()
        let percentile5 = sortedDepths[Int(Float(sortedDepths.count) * 0.05)]
        let percentile95 = sortedDepths[Int(Float(sortedDepths.count) * 0.95)]
        let depthRange = percentile95 - percentile5
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                    width: rotatedWidth,
                                    height: rotatedHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: rotatedWidth * 4,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        let data = context.data!.bindMemory(to: UInt8.self, capacity: rotatedWidth * rotatedHeight * 4)
        
        for i in 0..<(rotatedWidth * rotatedHeight * 4) {
            data[i] = 0
        }
        
        let jetColormap: [[Float]] = [
            [0, 0, 128], [0, 0, 255], [0, 128, 255], [0, 255, 255],
            [128, 255, 128], [255, 255, 0], [255, 128, 0], [255, 0, 0], [128, 0, 0]
        ]
        
        for point in points {
            let x = Int(point.x)
            let y = Int(point.y)
            
            guard x >= 0 && x < originalWidth && y >= 0 && y < originalHeight else { continue }
            
            let clampedDepth = max(percentile5, min(percentile95, point.depth))
            let normalizedDepth = depthRange > 0 ? (clampedDepth - percentile5) / depthRange : 0
            let invertedDepth = 1.0 - normalizedDepth
            
            let gamma: Float = 0.5
            let enhancedDepth = pow(invertedDepth, gamma)
            
            let color = interpolateColor(colormap: jetColormap, t: enhancedDepth)
            
            let rotatedX = originalHeight - 1 - y
            let rotatedY = x
            let dataIndex = (rotatedY * rotatedWidth + rotatedX) * 4
            
            data[dataIndex] = UInt8(color[0])
            data[dataIndex + 1] = UInt8(color[1])
            data[dataIndex + 2] = UInt8(color[2])
            data[dataIndex + 3] = 255
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    // ========== EXISTING: MASK EXPANSION (UNCHANGED) ==========
    private func simpleExpandMask(_ maskImage: UIImage) -> UIImage? {
        guard let cgImage = maskImage.cgImage else {
            return maskImage
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        
        print("Expanding mask using fast boundary-based dilation...")
        
        var maskData = [UInt8](repeating: 0, count: totalPixels * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var binaryMask = [Bool](repeating: false, count: totalPixels)
        for i in 0..<totalPixels {
            let pixelIndex = i * 4
            let red = maskData[pixelIndex]
            binaryMask[i] = red > 128
        }
        
        let dilationRadius = max(50, min(width, height) / 100)
        print("Applying \(dilationRadius) iterations of fast morphological dilation")
        
        var boundaryPixels = Set<Int>()
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if binaryMask[index] {
                    var isBoundary = false
                    for dy in -1...1 {
                        for dx in -1...1 {
                            if dx == 0 && dy == 0 { continue }
                            let nx = x + dx
                            let ny = y + dy
                            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                                let neighborIndex = ny * width + nx
                                if !binaryMask[neighborIndex] {
                                    isBoundary = true
                                    break
                                }
                            }
                        }
                        if isBoundary { break }
                    }
                    if isBoundary {
                        boundaryPixels.insert(index)
                    }
                }
            }
        }
        
        print("Initial boundary pixels: \(boundaryPixels.count)")
        
        for iteration in 0..<dilationRadius {
            var newBoundaryPixels = Set<Int>()
            
            for boundaryIndex in boundaryPixels {
                let bx = boundaryIndex % width
                let by = boundaryIndex / width
                
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        
                        let nx = bx + dx
                        let ny = by + dy
                        
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            let neighborIndex = ny * width + nx
                            if !binaryMask[neighborIndex] {
                                binaryMask[neighborIndex] = true
                                newBoundaryPixels.insert(neighborIndex)
                            }
                        }
                    }
                }
            }
            
            boundaryPixels = newBoundaryPixels
            
            if boundaryPixels.isEmpty {
                print("Expansion complete at iteration \(iteration + 1) (no more pixels to expand)")
                break
            }
        }
        
        var expandedMaskData = [UInt8](repeating: 0, count: totalPixels * 4)
        for i in 0..<totalPixels {
            if binaryMask[i] {
                expandedMaskData[i * 4] = 139
                expandedMaskData[i * 4 + 1] = 69
                expandedMaskData[i * 4 + 2] = 19
                expandedMaskData[i * 4 + 3] = 255
            } else {
                expandedMaskData[i * 4 + 3] = 0
            }
        }
        
        guard let expandedContext = CGContext(
            data: &expandedMaskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let expandedCGImage = expandedContext.makeImage() else {
            return maskImage
        }
        
        print("Fast mask expansion complete")
        
        return UIImage(cgImage: expandedCGImage)
    }

    // ========== EXISTING: DEPTH DATA DELEGATE (UNCHANGED) ==========
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        self.latestDepthData = depthData
        
        if let calibrationData = depthData.cameraCalibrationData {
            self.cameraCalibrationData = calibrationData
        }
    }
    
    // ========== MODIFIED: PHOTO CAPTURE DELEGATE (HANDLES BOTH MODES) ==========
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else { return }
        
        if mode == .volume {
            // ========== EXISTING: TRUEDEPTH MODE HANDLING (UNCHANGED) ==========
            self.currentPhotoData = imageData
            
            if let depthData = photo.depthData {
                self.currentDepthData = depthData
                
                if let calibrationData = depthData.cameraCalibrationData {
                    self.cameraCalibrationData = calibrationData
                }
            }
            
            self.processSimultaneousCapture()
            
        } else {
            // ========== NEW: STANDARD MODE HANDLING ==========
            guard let capturedImage = UIImage(data: imageData) else {
                print("❌ Failed to process captured photo")
                return
            }
            
            // Send the raw image immediately
            DispatchQueue.main.async { [weak self] in
                self?.onImageCaptured?(capturedImage)
                print("✅ Standard photo captured and sent immediately")
            }
            
            // Optimize image in background
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let _ = self?.optimizeImage(capturedImage) ?? capturedImage
            }
        }
    }
    
    // ========== NEW: IMAGE OPTIMIZATION (FROM PERSISTENTCAMERAMANAGER) ==========
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

    // ========== EXISTING: SIMULTANEOUS CAPTURE (UNCHANGED) ==========
    func captureDepthAndPhoto() {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.capturedDepthImage = nil
            self.capturedPhoto = nil
            self.hasOutline = false
            self.croppedFileToShare = nil
            
            self.samManagerDepth = MobileSAMManager()
            self.samManagerPhoto = MobileSAMManager()
            self.isEncodingImages = false
        }
        
        // Trigger flash if enabled (for volume mode with front camera)
        if isFlashEnabled && mode == .volume {
            DispatchQueue.main.async {
                FlashOverlayWindow.shared.flash(duration: 1.0)
            }
            // Delay capture to middle of flash duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.performDepthCapture()
            }
        } else {
            performDepthCapture()
        }
    }

    private func performDepthCapture() {
        let settings = AVCapturePhotoSettings()
        settings.isDepthDataDeliveryEnabled = true
        
        self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // ========== EXISTING: PROCESS SIMULTANEOUS CAPTURE (UNCHANGED) ==========
    private func processSimultaneousCapture() {
        guard let depthData = currentDepthData,
              let photoData = currentPhotoData else {
            self.presentError("Missing depth data or photo data.")
            return
        }
        
        self.rawDepthData = depthData
        
        if let calibrationData = depthData.cameraCalibrationData {
            self.cameraCalibrationData = calibrationData
        }
        
        let depthImage = self.createDepthVisualization(from: depthData)
        
        let photo = UIImage(data: photoData)
        
        self.saveDepthDataToFile(depthData: depthData)
        
        DispatchQueue.main.async {
            self.capturedDepthImage = depthImage
            self.capturedPhoto = photo
            self.isProcessing = false
            
            if let depthImage = depthImage {
                let photoToEncode = photo ?? depthImage
                self.startBackgroundEncoding(depthImage: depthImage, photoImage: photoToEncode)
            }
        }
        
        self.currentDepthData = nil
        self.currentPhotoData = nil
    }

    // ========== EXISTING: ALL REMAINING METHODS (UNCHANGED) ==========
    // [All the remaining existing methods continue exactly as they were...]
    // Including: cropDepthDataWithPath, cropUploadedCSVWithPath, isPointInPolygon,
    // createDepthVisualization, interpolateColor, saveDepthDataToFile,
    // fastPointInPolygon, douglasPeuckerSimplify, perpendicularDistance,
    // cropDepthDataWithMask, cropPhoto, refineWithSecondaryMask, etc.
    
    func cropDepthDataWithPath(_ path: [CGPoint]) {
        if !uploadedCSVData.isEmpty {
            cropUploadedCSVWithPath(path)
        } else if let depthData = rawDepthData {
            saveDepthDataToFile(depthData: depthData, cropPath: path)
        } else {
            presentError("No depth data available for cropping.")
            return
        }
        
        DispatchQueue.main.async {
            self.hasOutline = true
        }
    }
    
    private func cropUploadedCSVWithPath(_ path: [CGPoint]) {
        guard !uploadedCSVData.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "depth_data_cropped_\(timestamp).csv"
            
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    self.presentError("Could not access Documents directory.")
                    self.isProcessing = false
                }
                return
            }
            
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            do {
                var csvLines: [String] = []
                csvLines.append("x,y,depth_meters")
                
                if let originalFileURL = self.fileToShare {
                    let originalContent = try String(contentsOf: originalFileURL)
                    let originalLines = originalContent.components(separatedBy: .newlines)
                    
                    for line in originalLines {
                        if line.hasPrefix("#") {
                            csvLines.append(line)
                        }
                    }
                }
                
                csvLines.append("# Cropped from uploaded CSV file")
                
                var croppedPixelCount = 0
                
                let originalMaxX = Int(ceil(self.uploadedCSVData.map { $0.x }.max() ?? 0))
                let originalMaxY = Int(ceil(self.uploadedCSVData.map { $0.y }.max() ?? 0))
                let originalWidth = originalMaxX + 1
                let originalHeight = originalMaxY + 1
                
                let simplifiedPath = self.douglasPeuckerSimplify(path, epsilon: 1.0)
                
                var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
                if !simplifiedPath.isEmpty {
                    let minX = Int(floor(simplifiedPath.map { $0.x }.min()!))
                    let maxX = Int(ceil(simplifiedPath.map { $0.x }.max()!))
                    let minY = Int(floor(simplifiedPath.map { $0.y }.min()!))
                    let maxY = Int(ceil(simplifiedPath.map { $0.y }.max()!))
                    
                    boundingBox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
                }
                
                print("Cropping \(self.uploadedCSVData.count) points...")
                
                var minDepth: Float = Float.infinity
                var maxDepth: Float = -Float.infinity
                var validPixelCount = 0
                
                for point in self.uploadedCSVData {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    
                    var shouldInclude = true
                    
                    if let bbox = boundingBox {
                        let displayX = originalHeight - 1 - y
                        let displayY = x
                        
                        if displayX < bbox.minX || displayX > bbox.maxX ||
                           displayY < bbox.minY || displayY > bbox.maxY {
                            shouldInclude = false
                        } else {
                            let displayPoint = CGPoint(x: CGFloat(displayX), y: CGFloat(displayY))
                            shouldInclude = self.fastPointInPolygon(point: displayPoint, polygon: simplifiedPath)
                        }
                    }
                    
                    if shouldInclude {
                        csvLines.append("\(point.x),\(point.y),\(String(format: "%.6f", point.depth))")
                        croppedPixelCount += 1
                        
                        if !point.depth.isNaN && !point.depth.isInfinite && point.depth > 0 {
                            minDepth = min(minDepth, point.depth)
                            maxDepth = max(maxDepth, point.depth)
                            validPixelCount += 1
                        }
                    }
                }
                
                let csvContent = csvLines.joined(separator: "\n")
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                print("Successfully cropped \(croppedPixelCount) points from \(self.uploadedCSVData.count) total points")
                print("Depth range: \(minDepth) to \(maxDepth) meters, \(validPixelCount) valid depth values")
                
                DispatchQueue.main.async {
                    self.lastSavedFileName = fileName
                    self.croppedFileToShare = fileURL
                    self.isProcessing = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to save cropped CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func isPointInPolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        let x = point.x
        let y = point.y
        var inside = false
        
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }

    private func createDepthVisualization(from depthData: AVDepthData) -> UIImage? {
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                print("Failed to convert disparity to depth: \(error)")
                return nil
            }
        } else {
            processedDepthData = depthData
        }
        
        let depthMap = processedDepthData.depthDataMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let originalWidth = CVPixelBufferGetWidth(depthMap)
        let originalHeight = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: originalWidth * originalHeight)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var validDepths: [Float] = []
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    validDepths.append(depthValue)
                }
            }
        }
        
        guard !validDepths.isEmpty else { return nil }
        
        validDepths.sort()
        let percentile5 = validDepths[Int(Float(validDepths.count) * 0.05)]
        let percentile95 = validDepths[Int(Float(validDepths.count) * 0.95)]
        let depthRange = percentile95 - percentile5
        
        let rotatedWidth = originalHeight
        let rotatedHeight = originalWidth
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                    width: rotatedWidth,
                                    height: rotatedHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: rotatedWidth * 4,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        let data = context.data!.bindMemory(to: UInt8.self, capacity: rotatedWidth * rotatedHeight * 4)
        
        let jetColormap: [[Float]] = [
            [0, 0, 128], [0, 0, 255], [0, 128, 255], [0, 255, 255],
            [128, 255, 128], [255, 255, 0], [255, 128, 0], [255, 0, 0], [128, 0, 0]
        ]
        
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                var color: [Float] = [0, 0, 0]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 && depthRange > 0 {
                    let clampedDepth = max(percentile5, min(percentile95, depthValue))
                    let normalizedDepth = (clampedDepth - percentile5) / depthRange
                    let invertedDepth = 1.0 - normalizedDepth
                    
                    let gamma: Float = 0.5
                    let enhancedDepth = pow(invertedDepth, gamma)
                    
                    color = interpolateColor(colormap: jetColormap, t: enhancedDepth)
                }
                
                let rotatedX = originalHeight - 1 - y
                let rotatedY = x
                let dataIndex = (rotatedY * rotatedWidth + rotatedX) * 4
                
                data[dataIndex] = UInt8(color[0])
                data[dataIndex + 1] = UInt8(color[1])
                data[dataIndex + 2] = UInt8(color[2])
                data[dataIndex + 3] = 255
            }
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private func interpolateColor(colormap: [[Float]], t: Float) -> [Float] {
        let clampedT = max(0, min(1, t))
        let scaledT = clampedT * Float(colormap.count - 1)
        let index = Int(floor(scaledT))
        let frac = scaledT - Float(index)
        
        if index >= colormap.count - 1 {
            return colormap[colormap.count - 1]
        }
        
        let color1 = colormap[index]
        let color2 = colormap[index + 1]
        
        return [
            color1[0] + (color2[0] - color1[0]) * frac,
            color1[1] + (color2[1] - color1[1]) * frac,
            color1[2] + (color2[2] - color1[2]) * frac
        ]
    }

    private func saveDepthDataToFile(depthData: AVDepthData, cropPath: [CGPoint]? = nil) {
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert disparity to depth: \(error.localizedDescription)")
                return
            }
        } else {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert depth data format: \(error.localizedDescription)")
                return
            }
        }
        
        let depthMap = processedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = cropPath != nil ? "depth_data_cropped_\(timestamp).csv" : "depth_data_\(timestamp).csv"
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.presentError("Could not access Documents directory.")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            var csvLines: [String] = []
            csvLines.append("x,y,depth_meters")
            
            if let calibrationData = self.cameraCalibrationData {
                let intrinsics = calibrationData.intrinsicMatrix
                csvLines.append("# Camera Intrinsics: fx=\(intrinsics.columns.0.x), fy=\(intrinsics.columns.1.y), cx=\(intrinsics.columns.2.x), cy=\(intrinsics.columns.2.y)")
                let dimensions = calibrationData.intrinsicMatrixReferenceDimensions
                csvLines.append("# Reference Dimensions: width=\(dimensions.width), height=\(dimensions.height)")
            }
            
            let originalDataType = depthData.depthDataType
            if originalDataType == kCVPixelFormatType_DisparityFloat16 || originalDataType == kCVPixelFormatType_DisparityFloat32 {
                csvLines.append("# Original Data: Disparity (converted to depth using Apple's calibrated conversion)")
            } else {
                csvLines.append("# Original Data: Depth")
            }
            
            var minDepth: Float = Float.infinity
            var maxDepth: Float = -Float.infinity
            var validPixelCount = 0
            var croppedPixelCount = 0
            
            var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
            var simplifiedPath: [CGPoint] = []
            
            if let cropPath = cropPath {
                simplifiedPath = douglasPeuckerSimplify(cropPath, epsilon: 1.0)
                
                let minX = Int(floor(simplifiedPath.map { $0.x }.min()!))
                let maxX = Int(ceil(simplifiedPath.map { $0.x }.max()!))
                let minY = Int(floor(simplifiedPath.map { $0.y }.min()!))
                let maxY = Int(ceil(simplifiedPath.map { $0.y }.max()!))
                
                boundingBox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            }
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
                    var shouldInclude = true
                    
                    if let bbox = boundingBox {
                        let displayX = height - 1 - y
                        let displayY = x
                        
                        if displayX < bbox.minX || displayX > bbox.maxX ||
                           displayY < bbox.minY || displayY > bbox.maxY {
                            shouldInclude = false
                        } else {
                            let point = CGPoint(x: CGFloat(displayX), y: CGFloat(displayY))
                            shouldInclude = fastPointInPolygon(point: point, polygon: simplifiedPath)
                        }
                    }
                    
                    if shouldInclude {
                        csvLines.append("\(x),\(y),\(String(format: "%.6f", depthValue))")
                        croppedPixelCount += 1
                        
                        if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                            minDepth = min(minDepth, depthValue)
                            maxDepth = max(maxDepth, depthValue)
                            validPixelCount += 1
                        }
                    }
                }
            }
            
            let csvContent = csvLines.joined(separator: "\n")
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                self.lastSavedFileName = fileName
                if cropPath != nil {
                    self.croppedFileToShare = fileURL
                } else {
                    self.fileToShare = fileURL
                }
            }
            
        } catch {
            self.presentError("Failed to save depth data: \(error.localizedDescription)")
        }
    }

    private func fastPointInPolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        let x = point.x
        let y = point.y
        var windingNumber = 0
        
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if yi <= y {
                if yj > y {
                    let cross = (xj - xi) * (y - yi) - (x - xi) * (yj - yi)
                    if cross > 0 {
                        windingNumber += 1
                    }
                }
            } else {
                if yj <= y {
                    let cross = (xj - xi) * (y - yi) - (x - xi) * (yj - yi)
                    if cross < 0 {
                        windingNumber -= 1
                    }
                }
            }
        }
        
        return windingNumber != 0
    }

    private func douglasPeuckerSimplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        
        var maxDistance: CGFloat = 0
        var maxIndex = 0
        
        let firstPoint = points.first!
        let lastPoint = points.last!
        
        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[i], lineStart: firstPoint, lineEnd: lastPoint)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }
        
        if maxDistance > epsilon {
            let leftSegment = douglasPeuckerSimplify(Array(points[0...maxIndex]), epsilon: epsilon)
            let rightSegment = douglasPeuckerSimplify(Array(points[maxIndex..<points.count]), epsilon: epsilon)
            
            return leftSegment + Array(rightSegment.dropFirst())
        } else {
            return [firstPoint, lastPoint]
        }
    }

    private func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        
        if dx == 0 && dy == 0 {
            let px = point.x - lineStart.x
            let py = point.y - lineStart.y
            return sqrt(px * px + py * py)
        }
        
        let numerator = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        let denominator = sqrt(dx * dx + dy * dy)
        
        return numerator / denominator
    }
    
    func cropDepthDataWithMask(_ maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize, skipExpansion: Bool = false, completion: (() -> Void)? = nil) {
        
        let finalMask: UIImage
        if skipExpansion {
            print("⭐️ Skipping mask expansion - user drew mask with pen tool")
            finalMask = maskImage
        } else {
            print("🔄 Applying smart expansion - mask from tap-to-apply only")
            finalMask = simpleExpandMask(maskImage) ?? maskImage
        }
        
        extractAndPrintMaskBoundary(finalMask, depthImageSize: depthImageSize)
        
        if let photo = capturedPhoto {
            DispatchQueue.global(qos: .userInitiated).async {
                let croppedPhoto = self.cropPhoto(photo, withMask: finalMask, imageFrame: imageFrame)
                DispatchQueue.main.async {
                    self.croppedPhoto = croppedPhoto
                }
            }
        }
        
        if !uploadedCSVData.isEmpty {
            cropUploadedCSVWithMask(finalMask, imageFrame: imageFrame, depthImageSize: depthImageSize, completion: completion)
        } else if let depthData = rawDepthData {
            saveDepthDataToFileWithMask(depthData: depthData, maskImage: finalMask, imageFrame: imageFrame, depthImageSize: depthImageSize, completion: completion)
        } else {
            presentError("No depth data available for cropping.")
            completion?()
            return
        }
        
        DispatchQueue.main.async {
            self.hasOutline = true
        }
    }

    private func cropPhoto(_ photo: UIImage, withMask maskImage: UIImage, imageFrame: CGRect) -> UIImage? {
        guard let maskCGImage = maskImage.cgImage,
              let photoCGImage = photo.cgImage else { return nil }
        
        let size = photo.size
        
        UIGraphicsBeginImageContextWithOptions(size, false, photo.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        photo.draw(at: .zero)
        
        context.setBlendMode(.destinationIn)
        
        UIImage(cgImage: maskCGImage).draw(in: CGRect(origin: .zero, size: size), blendMode: .destinationIn, alpha: 1.0)
        
        let croppedPhoto = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return croppedPhoto
    }

    func refineWithSecondaryMask(_ secondaryMask: UIImage, imageFrame: CGRect, depthImageSize: CGSize, primaryCroppedCSV: URL, skipExpansion: Bool = false) {
        let finalMask: UIImage
        if skipExpansion {
            print("⭐️ Skipping refinement mask expansion - user drew mask with pen tool")
            finalMask = secondaryMask
        } else {
            print("ℹ️ Refinement mask from tap-to-apply (already precise, no expansion needed)")
            finalMask = secondaryMask
        }
        
        DispatchQueue.main.async {
            self.refinementMask = finalMask
            self.refinementImageFrame = imageFrame
            self.refinementDepthImageSize = depthImageSize
        }
    }

    private func cropUploadedCSVWithMask(_ maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize, completion: (() -> Void)? = nil) {
        guard !uploadedCSVData.isEmpty else {
            completion?()
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "depth_data_masked_\(timestamp).csv"
            
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    self.presentError("Could not access Documents directory.")
                    self.isProcessing = false
                    completion?()
                }
                return
            }
            
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            do {
                var csvLines: [String] = []
                csvLines.append("x,y,depth_meters")
                
                if let originalFileURL = self.fileToShare {
                    let originalContent = try String(contentsOf: originalFileURL)
                    let originalLines = originalContent.components(separatedBy: .newlines)
                    
                    for line in originalLines {
                        if line.hasPrefix("#") {
                            csvLines.append(line)
                        }
                    }
                }
                
                csvLines.append("# Cropped using AI mask segmentation")
                
                var croppedPixelCount = 0
                let maskPixelData = self.extractMaskPixelData(from: maskImage)
                
                let originalMaxX = Int(ceil(self.uploadedCSVData.map { $0.x }.max() ?? 0))
                let originalMaxY = Int(ceil(self.uploadedCSVData.map { $0.y }.max() ?? 0))
                let originalWidth = originalMaxX + 1
                let originalHeight = originalMaxY + 1
                
                print("Processing \(self.uploadedCSVData.count) points with mask...")
                
                for point in self.uploadedCSVData {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    
                    let displayX = originalHeight - 1 - y
                    let displayY = x
                    
                    if self.isPointInMask(displayX: displayX, displayY: displayY,
                                       originalWidth: originalWidth, originalHeight: originalHeight,
                                       maskPixelData: maskPixelData, maskImage: maskImage) {
                        csvLines.append("\(point.x),\(point.y),\(String(format: "%.6f", point.depth))")
                        croppedPixelCount += 1
                    }
                }
                
                let csvContent = csvLines.joined(separator: "\n")
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                print("Successfully cropped \(croppedPixelCount) points from \(self.uploadedCSVData.count) total points using AI mask")
                
                DispatchQueue.main.async {
                    self.lastSavedFileName = fileName
                    self.croppedFileToShare = fileURL
                    self.isProcessing = false
                    completion?()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to save masked CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                    completion?()
                }
            }
        }
    }

    private func saveDepthDataToFileWithMask(depthData: AVDepthData, maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize, completion: (() -> Void)? = nil) {
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert disparity to depth: \(error.localizedDescription)")
                completion?()
                return
            }
        } else {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert depth data format: \(error.localizedDescription)")
                completion?()
                return
            }
        }
        
        let depthMap = processedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "depth_data_masked_\(timestamp).csv"
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.presentError("Could not access Documents directory.")
            completion?()
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            var csvLines: [String] = []
            csvLines.append("x,y,depth_meters")
            
            if let calibrationData = self.cameraCalibrationData {
                let intrinsics = calibrationData.intrinsicMatrix
                csvLines.append("# Camera Intrinsics: fx=\(intrinsics.columns.0.x), fy=\(intrinsics.columns.1.y), cx=\(intrinsics.columns.2.x), cy=\(intrinsics.columns.2.y)")
                let dimensions = calibrationData.intrinsicMatrixReferenceDimensions
                csvLines.append("# Reference Dimensions: width=\(dimensions.width), height=\(dimensions.height)")
            }
            
            csvLines.append("# Cropped using AI mask segmentation")
            
            var croppedPixelCount = 0
            let maskPixelData = extractMaskPixelData(from: maskImage)
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
                    let displayX = height - 1 - y
                    let displayY = x
                    
                    if isPointInMask(displayX: displayX, displayY: displayY,
                                   originalWidth: width, originalHeight: height,
                                   maskPixelData: maskPixelData, maskImage: maskImage) {
                        csvLines.append("\(x),\(y),\(String(format: "%.6f", depthValue))")
                        croppedPixelCount += 1
                    }
                }
            }
            
            let csvContent = csvLines.joined(separator: "\n")
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            print("Successfully cropped \(croppedPixelCount) points using AI mask")
            
            DispatchQueue.main.async {
                self.lastSavedFileName = fileName
                self.croppedFileToShare = fileURL
                completion?()
            }
            
        } catch {
            self.presentError("Failed to save masked depth data: \(error.localizedDescription)")
            completion?()
        }
    }

    private func extractMaskPixelData(from maskImage: UIImage) -> [UInt8] {
        guard let cgImage = maskImage.cgImage else { return [] }
        
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixelData
    }

    private func isPointInMask(displayX: Int, displayY: Int, originalWidth: Int, originalHeight: Int,
                              maskPixelData: [UInt8], maskImage: UIImage) -> Bool {
        guard let cgImage = maskImage.cgImage else { return false }
        
        let maskWidth = cgImage.width
        let maskHeight = cgImage.height
        
        let maskX = Int((Float(displayX) / Float(originalHeight)) * Float(maskWidth))
        let maskY = Int((Float(displayY) / Float(originalWidth)) * Float(maskHeight))
        
        guard maskX >= 0 && maskX < maskWidth && maskY >= 0 && maskY < maskHeight else { return false }
        
        let pixelIndex = (maskY * maskWidth + maskX) * 4
        guard pixelIndex < maskPixelData.count else { return false }
        
        let red = maskPixelData[pixelIndex]
        return red > 128
    }
    
    private func extractAndPrintMaskBoundary(_ maskImage: UIImage, depthImageSize: CGSize) {
        guard let cgImage = maskImage.cgImage else { return }
        
        let width = cgImage.width
        let height = cgImage.height
        
        print("\n🎯 EXTRACTING ACTUAL PERIMETER POINTS FROM MASK")
        print(String(repeating: "=", count: 60))
        print("Mask dimensions: \(width) x \(height)")
        
        var maskData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var boundaryPoints: [(x: Int, y: Int)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let isInMask = maskData[index] > 128
                
                if isInMask {
                    var hasExternalNeighbor = false
                    
                    if x > 0 {
                        let leftIndex = (y * width + (x - 1)) * 4
                        if maskData[leftIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true
                    }
                    
                    if x < width - 1 {
                        let rightIndex = (y * width + (x + 1)) * 4
                        if maskData[rightIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true
                    }
                    
                    if y > 0 {
                        let topIndex = ((y - 1) * width + x) * 4
                        if maskData[topIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true
                    }
                    
                    if y < height - 1 {
                        let bottomIndex = ((y + 1) * width + x) * 4
                        if maskData[bottomIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true
                    }
                    
                    if hasExternalNeighbor {
                        boundaryPoints.append((x: x, y: y))
                    }
                }
            }
        }
        
        print("\n📊 MASK BOUNDARY STATISTICS:")
        print("Total boundary points found: \(boundaryPoints.count)")
        
        print("\n🔍 BOUNDARY POINTS (Display Coordinates):")
        print("First 50 points:")
        for (index, point) in boundaryPoints.prefix(50).enumerated() {
            print("  Point \(index + 1): (\(point.x), \(point.y))")
        }
        
        if boundaryPoints.count > 50 {
            print("  ... (\(boundaryPoints.count - 50) more points)")
        }
        
        self.maskBoundaryPoints = boundaryPoints
        self.maskDimensions = CGSize(width: width, height: height)
        print("\n✅ Stored \(boundaryPoints.count) boundary points for plane fitting")
        
        print("\n🔄 CONVERTING BOUNDARY POINTS TO DEPTH COORDINATES...")
        extractBoundaryDepthPoints(boundaryPoints: boundaryPoints, maskWidth: width, maskHeight: height)
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func extractBoundaryDepthPoints(boundaryPoints: [(x: Int, y: Int)], maskWidth: Int, maskHeight: Int) {
        var depthPoints: [DepthPoint] = []
        
        var originalWidth: Int = 0
        var originalHeight: Int = 0
        
        if !uploadedCSVData.isEmpty {
            let maxX = Int(ceil(uploadedCSVData.map { $0.x }.max() ?? 0))
            let maxY = Int(ceil(uploadedCSVData.map { $0.y }.max() ?? 0))
            originalWidth = maxX + 1
            originalHeight = maxY + 1
            
            print("Using uploaded CSV data: \(originalWidth) x \(originalHeight)")
            
            var depthMap: [String: Float] = [:]
            for point in uploadedCSVData {
                let key = "\(Int(point.x)),\(Int(point.y))"
                depthMap[key] = point.depth
            }
            
            for boundaryPoint in boundaryPoints {
                let originalY = originalHeight - 1 - Int((Float(boundaryPoint.x) / Float(maskWidth)) * Float(originalHeight))
                let originalX = Int((Float(boundaryPoint.y) / Float(maskHeight)) * Float(originalWidth))
                
                let key = "\(originalX),\(originalY)"
                if let depth = depthMap[key] {
                    depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depth))
                }
            }
            
        } else if let depthData = rawDepthData {
            let processedDepthData: AVDepthData
            if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
               depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            } else {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            }
            
            let depthMap = processedDepthData.depthDataMap
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            originalWidth = CVPixelBufferGetWidth(depthMap)
            originalHeight = CVPixelBufferGetHeight(depthMap)
            let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: originalWidth * originalHeight)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            
            print("Using raw depth data: \(originalWidth) x \(originalHeight)")
            
            for boundaryPoint in boundaryPoints {
                let originalY = originalHeight - 1 - Int((Float(boundaryPoint.x) / Float(maskWidth)) * Float(originalHeight))
                let originalX = Int((Float(boundaryPoint.y) / Float(maskHeight)) * Float(originalWidth))
                
                if originalX >= 0 && originalX < originalWidth && originalY >= 0 && originalY < originalHeight {
                    let pixelIndex = originalY * (bytesPerRow / MemoryLayout<Float32>.stride) + originalX
                    let depthValue = floatBuffer[pixelIndex]
                    
                    if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                        depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depthValue))
                    }
                }
            }
        }
        
        self.boundaryDepthPoints = depthPoints
        print("✅ Successfully converted \(depthPoints.count) boundary points with depth values")
    }
    
    func extractBackgroundSurfacePoints(_ maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize) {
        print("\n🎯 EXTRACTING BACKGROUND SURFACE POINTS FROM MASK")
        print(String(repeating: "=", count: 60))
        
        guard let maskCGImage = maskImage.cgImage else { return }
        
        let width = maskCGImage.width
        let height = maskCGImage.height
        
        var maskData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var maskContext = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        maskContext?.draw(maskCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var maskedPixels: [(x: Int, y: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if maskData[index] > 128 {
                    maskedPixels.append((x: x, y: y))
                }
            }
        }
        
        print("Found \(maskedPixels.count) masked pixels")
        
        var depthPoints: [DepthPoint] = []
        
        var originalWidth: Int = 0
        var originalHeight: Int = 0
        
        if !uploadedCSVData.isEmpty {
            let maxX = Int(ceil(uploadedCSVData.map { $0.x }.max() ?? 0))
            let maxY = Int(ceil(uploadedCSVData.map { $0.y }.max() ?? 0))
            originalWidth = maxX + 1
            originalHeight = maxY + 1
            
            print("Using uploaded CSV data: \(originalWidth) x \(originalHeight)")
            
            var depthMap: [String: Float] = [:]
            for point in uploadedCSVData {
                let key = "\(Int(point.x)),\(Int(point.y))"
                depthMap[key] = point.depth
            }
            
            for maskedPixel in maskedPixels {
                let originalY = originalHeight - 1 - Int((Float(maskedPixel.x) / Float(width)) * Float(originalHeight))
                let originalX = Int((Float(maskedPixel.y) / Float(height)) * Float(originalWidth))
                
                let key = "\(originalX),\(originalY)"
                if let depth = depthMap[key] {
                    depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depth))
                }
            }
            
        } else if let depthData = rawDepthData {
            let processedDepthData: AVDepthData
            if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
               depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            } else {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            }
            
            let depthMap = processedDepthData.depthDataMap
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            originalWidth = CVPixelBufferGetWidth(depthMap)
            originalHeight = CVPixelBufferGetHeight(depthMap)
            let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: originalWidth * originalHeight)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            
            print("Using raw depth data: \(originalWidth) x \(originalHeight)")
            
            for maskedPixel in maskedPixels {
                let originalY = originalHeight - 1 - Int((Float(maskedPixel.x) / Float(width)) * Float(originalHeight))
                let originalX = Int((Float(maskedPixel.y) / Float(height)) * Float(originalWidth))
                
                if originalX >= 0 && originalX < originalWidth && originalY >= 0 && originalY < originalHeight {
                    let pixelIndex = originalY * (bytesPerRow / MemoryLayout<Float32>.stride) + originalX
                    let depthValue = floatBuffer[pixelIndex]
                    
                    if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                        depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depthValue))
                    }
                }
            }
        }
        
        self.backgroundSurfacePoints = depthPoints

        let depthFilteredPoints = self.filterDepthOutliers(depthPoints)

        let filteredPoints = self.filterSteepGradientPoints(depthFilteredPoints, maxGradientThreshold: 0.01)
        self.backgroundSurfacePointsForPlane = filteredPoints

        print("✅ Successfully extracted \(depthPoints.count) background surface points with depth values")
        print("   Using \(filteredPoints.count) flat surface points for plane fitting (filtered out steep gradients)")
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func filterSteepGradientPoints(_ points: [DepthPoint], maxGradientThreshold: Float = 0.01) -> [DepthPoint] {
        guard !points.isEmpty else { return points }
        
        print("Filtering steep gradients from \(points.count) points...")
        
        var depthMap: [String: Float] = [:]
        for point in points {
            let key = "\(Int(point.x)),\(Int(point.y))"
            depthMap[key] = point.depth
        }
        
        var filteredPoints: [DepthPoint] = []
        
        for point in points {
            let x = Int(point.x)
            let y = Int(point.y)
            var maxGradient: Float = 0
            
            let neighbors = [
                (x-1, y), (x+1, y), (x, y-1), (x, y+1),
                (x-1, y-1), (x-1, y+1), (x+1, y-1), (x+1, y+1)
            ]
            
            for (nx, ny) in neighbors {
                let key = "\(nx),\(ny)"
                if let neighborDepth = depthMap[key] {
                    let depthDiff = abs(neighborDepth - point.depth)
                    let distance: Float = (nx == x || ny == y) ? 1.0 : 1.414
                    let gradient = depthDiff / distance
                    maxGradient = max(maxGradient, gradient)
                }
            }
            
            if maxGradient <= maxGradientThreshold {
                filteredPoints.append(point)
            }
        }
        
        let removedCount = points.count - filteredPoints.count
        print("✅ Filtered out \(removedCount) steep gradient points (\(String(format: "%.1f", Float(removedCount) / Float(points.count) * 100))%)")
        print("   Kept \(filteredPoints.count) flat surface points for plane fitting")
        
        return filteredPoints
    }
    
    private func filterDepthOutliers(_ points: [DepthPoint], depthThreshold: Float = 0.01) -> [DepthPoint] {
        guard points.count > 10 else { return points }
        
        print("Filtering depth outliers from \(points.count) background points...")
        
        let sortedDepths = points.map { $0.depth }.sorted()
        let medianDepth = sortedDepths[sortedDepths.count / 2]
        
        let percentile25Depth = sortedDepths[sortedDepths.count / 4]
        
        print("  Median depth: \(medianDepth)m, 25th percentile: \(percentile25Depth)m")
        
        let minAllowedDepth = percentile25Depth - depthThreshold
        
        let filteredPoints = points.filter { point in
            point.depth >= minAllowedDepth
        }
        
        let removedCount = points.count - filteredPoints.count
        print("✅ Filtered out \(removedCount) depth outliers (\(String(format: "%.1f", Float(removedCount) / Float(points.count) * 100))%)")
        print("   Removed points closer than \(minAllowedDepth)m (threshold: \(percentile25Depth)m - \(depthThreshold)m)")
        
        return filteredPoints
    }
    
    private func startBackgroundEncoding(depthImage: UIImage, photoImage: UIImage) {
        print("🚀 Starting background encoding of images...")
        isEncodingImages = true
        
        Task {
            async let depthEncodeTask = samManagerDepth.encodeImage(depthImage)
            async let photoEncodeTask = samManagerPhoto.encodeImage(photoImage)
            
            let (depthSuccess, photoSuccess) = await (depthEncodeTask, photoEncodeTask)
            
            await MainActor.run {
                isEncodingImages = false
                if depthSuccess && photoSuccess {
                    print("✅ Background encoding complete - images ready for segmentation!")
                } else {
                    print("⚠️ Background encoding had issues - Depth: \(depthSuccess), Photo: \(photoSuccess)")
                }
            }
        }
    }
}
