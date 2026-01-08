//
//  CamPreviewViewModel.swift
//  LockedCameraCaptureExtensionDemo
//
//  Created by Photon Juniper on 2024/8/21.
//
import SwiftUI
import AVFoundation
import MetalLib

class CamPreviewViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var previewImage: CIImage? = nil
    @Published private(set) var renderer = MetalRenderer()

    private(set) var previewQueue = DispatchQueue(label: "preview_queue")
    
    // AutoZoom Components
    var videoDevice: AVCaptureDevice?
    private let analyzer = SkierAnalyzer()
    private let autoZoomManager = AutoZoomManager()
    
    func initializeRenderer() {
        renderer.initializeCIContext(colorSpace: nil, name: "preview")
    }
    
    @MainActor
    func updatePreviewImage(_ previewImage: CIImage?) {
        self.previewImage = previewImage
        self.renderer.requestChanged(displayedImage: previewImage)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 1. Update Preview
        if let image = getVideoOutputImage(output, didOutput: sampleBuffer) {
            DispatchQueue.main.async {
                self.updatePreviewImage(image)
            }
        }
        
        // 2. AutoZoom Analysis
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        analyzer.analyze(pixelBuffer: pixelBuffer) { [weak self] rect in
            guard let self = self else { return }
            
            // Logic Loop
            // If rect is nil, we treat it as no detection.
            // But AutoZoomManager.update expects a Rect. 
            // If nil, we can skip or pass a dummy? 
            // Ideally we should handle 'lost subject' to decay or hold.
            // For now, if nil, we return.
            guard let detected = rect else { return }
            
            let dt = 1.0 / 60.0 // Approximate 60fps
            let newCrop = self.autoZoomManager.update(skierRect: detected, dt: dt)
            
            let targetZoom = 1.0 / max(0.01, newCrop.width)
            self.applyZoom(targetZoom)
        }
    }
    
    private func applyZoom(_ zoom: CGFloat) {
        guard let device = videoDevice else { return }
        
        do {
            try device.lockForConfiguration()
            let clamped = max(1.0, min(device.activeFormat.videoMaxZoomFactor, zoom))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("Zoom failed: \(error)")
        }
    }
    
    private func getVideoOutputImage(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer
    ) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
}
