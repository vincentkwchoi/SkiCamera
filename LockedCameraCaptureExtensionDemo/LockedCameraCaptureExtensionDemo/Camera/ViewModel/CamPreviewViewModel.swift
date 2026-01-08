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
    @Published var detectedRect: Rect? = nil
    @Published var debugLabel: String = "Initializing..."
    @Published var skierHeight: Double = 0.0
    @Published var currentZoom: CGFloat = 1.0
    @Published var buttonStatus: String = "No button pressed"
    @Published var isManualZoomMode: Bool = false

    private(set) var previewQueue = DispatchQueue(label: "preview_queue")
    
    // AutoZoom Components
    var videoDevice: AVCaptureDevice?
    private let analyzer = SkierAnalyzer()
    private let autoZoomManager = AutoZoomManager()
    
    // Manual Zoom
    private var manualZoomFactor: CGFloat = 1.0
    private let zoomStep: CGFloat = 0.2
    

    
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
            guard let detected = rect else {
                DispatchQueue.main.async {
                    self.detectedRect = nil
                    self.debugLabel = "Label: None"
                }
                return
            }
            
            // Skip auto-zoom if in manual mode
            if self.isManualZoomMode {
                DispatchQueue.main.async {
                    self.detectedRect = detected
                    self.skierHeight = detected.height
                    self.debugLabel = "Label: Person (Manual)"
                    // self.currentZoom is updated by manual zoom methods
                }
                return
            }
            
            let dt = 1.0 / 60.0 // Approximate 60fps
            let newCrop = self.autoZoomManager.update(skierRect: detected, dt: dt)
            
            let targetZoom = 1.0 / max(0.01, newCrop.width)
            self.applyZoom(targetZoom)
            
            // Update UI
            DispatchQueue.main.async {
                self.detectedRect = detected
                self.skierHeight = detected.height
                self.debugLabel = "Label: Person"
                self.currentZoom = targetZoom
            }
        }
    }
    
    func zoomIn() {
        guard let device = videoDevice else { return }
        if !isManualZoomMode {
            manualZoomFactor = device.videoZoomFactor
        }
        isManualZoomMode = true
        
        manualZoomFactor += zoomStep
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0) // Cap at 10x
        manualZoomFactor = min(manualZoomFactor, maxZoom)
        
        applyZoom(manualZoomFactor)
        currentZoom = manualZoomFactor
    }
    
    func zoomOut() {
        guard let device = videoDevice else { return }
        if !isManualZoomMode {
            manualZoomFactor = device.videoZoomFactor
        }
        isManualZoomMode = true
        
        manualZoomFactor -= zoomStep
        manualZoomFactor = max(1.0, manualZoomFactor) // Min 1x
        
        applyZoom(manualZoomFactor)
        currentZoom = manualZoomFactor
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
