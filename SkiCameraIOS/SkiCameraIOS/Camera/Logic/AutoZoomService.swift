import Foundation
import AVFoundation
import CoreImage
import OSLog

class AutoZoomService: ObservableObject {
    private let logger = Logger(subsystem: "com.vcnt.skicamera", category: "AutoZoomService")
    
    // Published State (for UI)
    @Published var detectedRect: Rect? = nil
    @Published var allDetectedRects: [Rect] = []
    @Published var debugLabel: String = "Initializing..."
    @Published var skierHeight: Double = 0.0
    @Published var analysisDurationMs: Double = 0.0
    
    // Zoom Control
    @Published var isManualZoomMode: Bool = false
    
    // Dependencies
    private let analyzer = SkierAnalyzer()
    private let autoZoomManager = AutoZoomManager()
    weak var videoDevice: AVCaptureDevice?
    
    // Throttling
    private var frameCounter: Int = 0
    private let frameSkipInterval: Int = 3
    
    private let processingQueue = DispatchQueue(label: "auto_zoom_processing")
    
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // 1. Throttling
        frameCounter += 1
        if frameCounter % frameSkipInterval != 0 {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let startTime = Date()
        
        // 2. Analysis (Async on background queue if needed, but SkierAnalyzer is synchronous)
        // We run this on a dedicated serial queue to avoid blocking main thread or camera delegate
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.analyzer.analyze(pixelBuffer: pixelBuffer) { resultTuple in
                let duration = Date().timeIntervalSince(startTime) * 1000 // ms
                
                DispatchQueue.main.async {
                    self.analysisDurationMs = duration
                }
                
                // Unpack tuple
                guard let tuple = resultTuple else {
                    DispatchQueue.main.async {
                        self.detectedRect = nil
                        self.allDetectedRects = []
                        self.debugLabel = "Label: None"
                    }
                    return
                }
                
                let primaryRect = tuple.0
                let allRects = tuple.1
                
                // Update UI state
                DispatchQueue.main.async {
                    self.detectedRect = primaryRect
                    self.allDetectedRects = allRects
                    if let p = primaryRect {
                        self.skierHeight = p.height
                        self.debugLabel = "Label: Person"
                    } else {
                        self.debugLabel = "Label: None"
                    }
                }
                
                // Logic Loop
                guard let detected = primaryRect else { return }
                
                // Skip auto-zoom if in manual mode
                if self.isManualZoomMode {
                    DispatchQueue.main.async {
                        self.debugLabel = "Label: Person (Manual)"
                    }
                    // Zoom is controlled by UI, we just track
                    return
                }
                
                // Calculate Dynamic dt
                var fps: Double = 60.0
                if let device = self.videoDevice {
                     let duration = device.activeVideoMinFrameDuration
                     if duration.seconds > 0 {
                         fps = 1.0 / duration.seconds
                     }
                }
                let dt = (1.0 / fps) * Double(self.frameSkipInterval)
                
                let newCrop = self.autoZoomManager.update(skierRect: detected, dt: dt)
                let targetZoom = 1.0 / max(0.01, newCrop.width)
                
                self.applyZoom(targetZoom)
            }
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
             // Squelch errors to avoid log spam
         }
     }
     
     // Manual Override Hooks
     private var uiUpdateTimer: Timer?
     private var manualZoomFactor: CGFloat = 1.0
     @Published var currentZoom: CGFloat = 1.0
     @Published var buttonStatus: String = "No button pressed"

     func startZoomingIn() {
        guard let device = videoDevice else { return }
        if !isManualZoomMode {
            logger.log(level: .default, "Switching to Manual Zoom (Zoom In)")
            manualZoomFactor = device.videoZoomFactor
        }
        isManualZoomMode = true
        
        stopUIUpdates()
        
        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            device.ramp(toVideoZoomFactor: maxZoom, withRate: 2.0) // 2x per second
            device.unlockForConfiguration()
        } catch {
            logger.log(level: .default, "Failed to start ramp: \(error.localizedDescription)")
        }
        
        // Timer for UI updates only
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateZoomUI()
        }
    }
    
    func startZoomingOut() {
        guard let device = videoDevice else { return }
        if !isManualZoomMode {
            logger.log(level: .default, "Switching to Manual Zoom (Zoom Out)")
            manualZoomFactor = device.videoZoomFactor
        }
        isManualZoomMode = true
        
        stopUIUpdates()
        
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: 1.0, withRate: 2.0)
            device.unlockForConfiguration()
        } catch {
             logger.log(level: .default, "Failed to start ramp: \(error.localizedDescription)")
        }
        
        // Timer for UI updates only
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateZoomUI()
        }
    }
    
    func stopZooming() {
        guard let device = videoDevice else { return }
        
        stopUIUpdates()
        
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            manualZoomFactor = device.videoZoomFactor // Capture final value
            device.unlockForConfiguration()
            
            // Final UI update
            updateZoomUI()
        } catch {
            logger.log(level: .default, "Failed to stop ramp: \(error.localizedDescription)")
        }
    }
    
    private func stopUIUpdates() {
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
    }
    
    private func updateZoomUI() {
        guard let device = videoDevice else { return }
        let current = device.videoZoomFactor
        DispatchQueue.main.async {
            self.currentZoom = current
            self.manualZoomFactor = current
        }
    }
     
     func setManualZoom(_ factor: CGFloat) {
         isManualZoomMode = true
         autoZoomManager.syncZoomState(zoomFactor: factor)
     }
     
     func resetToAutoZoom() {
         guard let device = videoDevice else { return }
         // Stop manual ramp first
         stopZooming()
         
         // Sync state
         autoZoomManager.syncZoomState(zoomFactor: device.videoZoomFactor)
         DispatchQueue.main.async {
             self.isManualZoomMode = false
             self.debugLabel = "Label: Auto Resumed"
             self.buttonStatus = "Auto Zoom Active"
         }
     }
}
