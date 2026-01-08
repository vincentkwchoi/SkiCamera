import Foundation
import CoreGraphics

// MARK: - Rect Helper
struct Rect {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
    
    var width: Double { right - left }
    var height: Double { bottom - top }
    var centerX: Double { (left + right) / 2.0 }
    var centerY: Double { (top + bottom) / 2.0 }
    
    static func fromLTRB(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> Rect {
        return Rect(left: left, top: top, right: right, bottom: bottom)
    }
}

// MARK: - PID Controller
class PIDController {
    var kp: Double
    var kd: Double
    private var lastError: Double = 0.0
    
    init(kp: Double, kd: Double) {
        self.kp = kp
        self.kd = kd
    }
    
    func update(_ error: Double, _ dt: Double) -> Double {
        if dt <= 0 { return 0.0 }
        let derivative = (error - lastError) / dt
        lastError = error
        return (kp * error) + (kd * derivative)
    }
}

// MARK: - Smoothing Filter
class SmoothingFilter {
    var alpha: Double
    private var value: Double?
    
    init(alpha: Double) {
        self.alpha = alpha
    }
    
    func filter(_ input: Double) -> Double {
        guard let current = value else {
            value = input
            return input
        }
        let newValue = (alpha * input) + ((1.0 - alpha) * current)
        value = newValue
        return newValue
    }
    
    func reset() {
        value = nil
    }
}

// MARK: - AutoZoomManager
class AutoZoomManager {
    // Components
    private let heightSmoother = SmoothingFilter(alpha: 0.2)
    private let centerXSmoother = SmoothingFilter(alpha: 0.2)
    private let centerYSmoother = SmoothingFilter(alpha: 0.2)
    
    // Sticky Framing
    private let targetFramingXIntent = SmoothingFilter(alpha: 0.05)
    private let targetFramingYIntent = SmoothingFilter(alpha: 0.05)
    
    private let panXPid = PIDController(kp: 1.0, kd: 0.5)
    private let panYPid = PIDController(kp: 1.0, kd: 0.5)
    
    // State
    private var currentZoomScale: Double = 1.0 // 1.0 = Full Frame
    private var currentCropCenterX: Double = 0.5
    private var currentCropCenterY: Double = 0.5
    
    // Config
    var targetSubjectHeightRatio: Double = 0.15
    var maxZoomSpeed: Double = 5.0
    var maxPanSpeed: Double = 5.0
    
    func update(skierRect: Rect, dt: Double) -> Rect {
        if dt <= 0 {
            return getRectFromCenterAndScale(cx: currentCropCenterX, cy: currentCropCenterY, scale: currentZoomScale)
        }
        
        // 1. Smooth Input
        let smoothedHeight = heightSmoother.filter(skierRect.height)
        let smoothedCenterX = centerXSmoother.filter(skierRect.centerX)
        let smoothedCenterY = centerYSmoother.filter(skierRect.centerY)
        
        // 2. Sticky Framing Intent
        let targetPanX = targetFramingXIntent.filter(smoothedCenterX)
        let targetPanY = targetFramingYIntent.filter(smoothedCenterY)
        
        // 3. Zoom Logic
        // iOS Vision receives the ZOOMED buffer. So 'smoothedHeight' IS the height in crop.
        // We do NOT need to divide by currentZoomScale.
        // let currentSkierHeightInCrop = smoothedHeight / currentZoomScale
        let currentSkierHeightInCrop = smoothedHeight
        let zoomError = targetSubjectHeightRatio - currentSkierHeightInCrop
        
        // Gain
        let kZoom = 10.0
        
        // Error > 0 (Too small) -> Decrease Scale (Zoom In)
        let scaleChange = -zoomError * kZoom * dt
        currentZoomScale += scaleChange
        
        // Clamp (0.1 = 10x Zoom, 1.0 = 1x Zoom)
        // Note: iOS videoZoomFactor is 1.0 -> 20.0 (Reciprocal of scale)
        // Here we track 'Scale' (FOV portion). 1.0 is full, 0.1 is 10% FOV.
        currentZoomScale = max(0.05, min(1.0, currentZoomScale))
        
        // 4. Pan Logic
        let panXError = targetPanX - currentCropCenterX
        let panYError = targetPanY - currentCropCenterY
        
        let panXVel = max(-maxPanSpeed, min(maxPanSpeed, panXPid.update(panXError, dt)))
        let panYVel = max(-maxPanSpeed, min(maxPanSpeed, panYPid.update(panYError, dt)))
        
        currentCropCenterX += panXVel * dt
        currentCropCenterY += panYVel * dt
        
        // Clamp Center
        let halfScale = currentZoomScale / 2.0
        let minCenter = halfScale
        let maxCenter = 1.0 - halfScale
        
        currentCropCenterX = max(minCenter, min(maxCenter, currentCropCenterX))
        currentCropCenterY = max(minCenter, min(maxCenter, currentCropCenterY))
        
        return getRectFromCenterAndScale(cx: currentCropCenterX, cy: currentCropCenterY, scale: currentZoomScale)
    }
    
    private func getRectFromCenterAndScale(cx: Double, cy: Double, scale: Double) -> Rect {
        let half = scale / 2.0
        return Rect.fromLTRB(cx - half, cy - half, cx + half, cy + half)
    }
}
