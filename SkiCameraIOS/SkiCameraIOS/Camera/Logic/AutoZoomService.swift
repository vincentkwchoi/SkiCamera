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
    private let detection = SkierDetection()
    private let selection = SkierSelection()
    private let targetCalc = TargetZoomCalc()
    private let gate = HysteresisGate()
    // Kp increased to 5.0 to compensate for Log Scaling (multiplying by Scale < 1.0)
    private let pid = PIDController(kp: 5.0, kd: 2.5) // Critically damped (~2*sqrt(kp))
    private let scaling = ZoomLogScaling()
    private let constraint = ZoomConstraint()
    
    // Pan Logic helper (kept simple here or moved to component)
    private let centerXSmoother = SmoothingFilter(alpha: 0.2)
    private let centerYSmoother = SmoothingFilter(alpha: 0.2)
    
    // State
    private var currentZoomScale: Double = 1.0
    private var currentCropCenterX: Double = 0.5
    private var currentCropCenterY: Double = 0.5
    
    weak var videoDevice: AVCaptureDevice?
    
    // Throttling
    private var frameCounter: Int = 0
    private let frameSkipInterval: Int = 1
    
    private let processingQueue = DispatchQueue(label: "auto_zoom_processing")
    
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // 1. Throttling
        frameCounter += 1
        if frameCounter % frameSkipInterval != 0 {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let startTime = Date()
        
        // 2. Analysis
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
// Step 1: Detection
            self.detection.detect(pixelBuffer: pixelBuffer) { detections in
                let duration = Date().timeIntervalSince(startTime) * 1000 // ms
                
                // Step 2: Selection
                let primaryRect = self.selection.selectTarget(from: detections)
                
                guard let target = primaryRect else {
                    DispatchQueue.main.async {
                        self.analysisDurationMs = duration
                        self.detectedRect = nil
                        self.allDetectedRects = detections
                        self.skierHeight = 0.0
                        self.debugLabel = "Label: None"
                    }
                    return
                }
                
                // Manual Mode Check
                if self.isManualZoomMode {
                     DispatchQueue.main.async {
                         self.analysisDurationMs = duration
                         self.detectedRect = primaryRect
                         self.allDetectedRects = detections
                         self.skierHeight = target.height
                         self.debugLabel = "Label: Person (Manual)"
                     }
                     return
                }
                
                // Calculate dt
                var fps: Double = 60.0
                if let device = self.videoDevice {
                     let duration = device.activeVideoMinFrameDuration
                     if duration.seconds > 0 { fps = 1.0 / duration.seconds }
                }
                let dt = (1.0 / fps) * Double(self.frameSkipInterval)
                
                // --- PIPELINE EXECUTION ---
                
                // Step 3: Target Calc
                // Note: We use currentZoomScale from our state tracker
                let zoomError = self.targetCalc.calculateError(subject: target, currentZoom: self.currentZoomScale)
                
                // Calculate Relative Error for Gate
                let targetH = self.targetCalc.targetSubjectHeightRatio
                let relativeError = targetH > 0 ? (zoomError / targetH) : 0.0
                
                // Step 4: Hysteresis (Using Relative Error)
                let shouldZoom = self.gate.shouldZoom(relativeError: relativeError)
                
                var velocity: Double = 0.0
                if shouldZoom {
                    // Step 5: PID (Keeps using Absolute Error for control dynamics)
                    velocity = self.pid.update(zoomError, dt)
                    
                    // Step 6: Log Scaling
                    let scaleChange = -velocity * self.currentZoomScale * dt
                    self.currentZoomScale += scaleChange
                } else {
                    // Reset PID state if gate is closed to prevent windup or jumps
                    self.pid.reset()
                }
                
                // Step 7: Constraint
                self.currentZoomScale = self.constraint.clamp(self.currentZoomScale)
                
                // Step 8: Pan Logic
                let smoothedCenterX = self.centerXSmoother.filter(target.centerX)
                let smoothedCenterY = self.centerYSmoother.filter(target.centerY)
                self.currentCropCenterX = smoothedCenterX
                self.currentCropCenterY = smoothedCenterY
                
                // Clamp Pan
                let halfScale = self.currentZoomScale / 2.0
                self.currentCropCenterX = max(halfScale, min(1.0 - halfScale, self.currentCropCenterX))
                self.currentCropCenterY = max(halfScale, min(1.0 - halfScale, self.currentCropCenterY))
                
                // Update Hardware
                let newCrop = self.getRectFromCenterAndScale(cx: self.currentCropCenterX, cy: self.currentCropCenterY, scale: self.currentZoomScale)
                let targetZoom = 1.0 / max(0.01, newCrop.width)
                self.applyZoom(targetZoom)
                
                // Final UI Update with Debug Info
                let currentScale = self.currentZoomScale
                let gateState = shouldZoom ? "OPEN" : "CLOSED"
                let threshold = self.gate.zoomTriggerThreshold
                
                DispatchQueue.main.async {
                    self.analysisDurationMs = duration
                    self.detectedRect = primaryRect
                    self.allDetectedRects = detections
                    self.skierHeight = target.height
                    
                    let hStr = String(format: "%.2f", target.height)
                    let tStr = String(format: "%.2f", targetH)
                    // Display Absolute Error + Relative %
                    let eStr = String(format: "%.2f(%.0f%%)", zoomError, relativeError * 100)
                    let gStr = String(format: "\(gateState)(%.0f%%)", threshold * 100)
                    let vStr = String(format: "%.2f", velocity)
                    let zStr = String(format: "%.2f", currentScale)
                    
                    self.debugLabel = "H:\(hStr) T:\(tStr) E:\(eStr) \(gStr) V:\(vStr) Z:\(zStr)"
                }
            }
        }
    }
    
    private func getRectFromCenterAndScale(cx: Double, cy: Double, scale: Double) -> Rect {
        let half = scale / 2.0
        return Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half)
    }
    
    private func applyZoom(_ zoom: CGFloat) {
         guard let device = videoDevice else { return }
         do {
             try device.lockForConfiguration()
             let clamped = max(1.0, min(device.activeFormat.videoMaxZoomFactor, zoom))
             device.videoZoomFactor = clamped
             device.unlockForConfiguration()
             
             DispatchQueue.main.async {
                 self.currentZoom = clamped
             }
         } catch {
             // Squelch errors to avoid log spam
         }
     }
     
     // Manual Override Hooks
     private var uiUpdateTimer: Timer?
     private var manualZoomFactor: CGFloat = 1.0
     @Published var currentZoom: CGFloat = 1.0
     @Published var buttonStatus: String = "No button pressed"

     func startZoomingIn(rate: Float = 2.0) {
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
            device.ramp(toVideoZoomFactor: maxZoom, withRate: rate) // User defined rate
            device.unlockForConfiguration()
        } catch {
            logger.log(level: .default, "Failed to start ramp: \(error.localizedDescription)")
        }
        
        // Timer for UI updates only
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateZoomUI()
        }
    }
    
    func startZoomingOut(rate: Float = 2.0) {
        guard let device = videoDevice else { return }
        if !isManualZoomMode {
            logger.log(level: .default, "Switching to Manual Zoom (Zoom Out)")
            manualZoomFactor = device.videoZoomFactor
        }
        isManualZoomMode = true
        
        stopUIUpdates()
        
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: 1.0, withRate: rate)
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
         // Sync internal state
         self.currentZoomScale = 1.0 / max(1.0, Double(factor))
         self.currentCropCenterX = 0.5 // Reset to center
         self.currentCropCenterY = 0.5
         
         // Reset components
         self.targetCalc.reset()
         self.gate.reset()
         self.pid.reset()
     }
     
     func resetToAutoZoom() {
         guard let device = videoDevice else { return }
         // Stop manual ramp first
         stopZooming()
         
         // Sync state
         self.currentZoomScale = 1.0 / max(1.0, Double(device.videoZoomFactor))
         self.currentCropCenterX = 0.5
         self.currentCropCenterY = 0.5
         
         // Reset components
         self.targetCalc.reset()
         self.gate.reset()
         self.pid.reset()
         
         DispatchQueue.main.async {
             self.isManualZoomMode = false
             self.debugLabel = "Label: Auto Resumed"
             self.buttonStatus = "Auto Zoom Active"
         }
     }
}
