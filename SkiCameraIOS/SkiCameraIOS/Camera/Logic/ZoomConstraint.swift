import Foundation

class ZoomConstraint {
    var minZoomScale: Double = 0.05 // 20x
    var maxZoomScale: Double = 1.0  // 1x
    
    func clamp(_ proposedScale: Double) -> Double {
        return max(minZoomScale, min(maxZoomScale, proposedScale))
    }
}
