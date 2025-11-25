//
//  CameraView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import SwiftUI
import AVFoundation
import UIKit

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
