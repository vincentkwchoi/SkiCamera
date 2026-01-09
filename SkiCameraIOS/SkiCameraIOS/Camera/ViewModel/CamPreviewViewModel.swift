//
//  CamPreviewViewModel.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/21.
//
import SwiftUI
import AVFoundation
import MetalLib
import OSLog

/// Manages the camera preview rendering.
/// Decoupled from analysis logic (see AutoZoomService).
class CamPreviewViewModel: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.vcnt.skicamera", category: "CamPreviewViewModel")
    
    @Published private(set) var previewImage: CIImage? = nil
    @Published private(set) var renderer = MetalRenderer()
    
    // Note: Analysis properties (detectedRect, debugLabel, etc.) have been moved to AutoZoomService.
    // CamPreviewViewModel now strictly handles the visual preview pipe.
    
    private(set) var previewQueue = DispatchQueue(label: "preview_queue")
    
    // Manual Zoom State (Optional: Can stay here or move to Service. Moving to service makes sense for centralization,
    // but button bindings might still look here. For now, we assume ContentView looks at AutoZoomService).
    
    // Video Device reference (for max zoom queries if needed strictly for UI, but mostly in Service now)
    weak var videoDevice: AVCaptureDevice?
    
    func initializeRenderer() {
        renderer.initializeCIContext(colorSpace: nil, name: "preview")
    }
    
    @MainActor
    func updatePreviewImage(_ previewImage: CIImage?) {
        self.previewImage = previewImage
        self.renderer.requestChanged(displayedImage: previewImage)
    }

    /// Called by FrameDistributor for every frame
    func handlePreviewFrame(_ sampleBuffer: CMSampleBuffer) {
        if let image = getVideoOutputImage(sampleBuffer) {
            DispatchQueue.main.async {
                self.updatePreviewImage(image)
            }
        }
    }
    
    private func getVideoOutputImage(_ sampleBuffer: CMSampleBuffer) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
}
