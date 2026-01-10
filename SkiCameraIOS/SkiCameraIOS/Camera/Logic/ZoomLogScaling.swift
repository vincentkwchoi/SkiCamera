import Foundation

class ZoomLogScaling {
    // Zoom Gain
    var kZoom: Double = 10.0
    
    func computeLogVelocity(error: Double, currentZoomScale: Double, dt: Double) -> Double {
        // Log Scaling: v = Error * Gain * CurrentScale
        // This ensures the velocity is a percentage of the current field of view.
        return -error * kZoom * currentZoomScale * dt
    }
}
