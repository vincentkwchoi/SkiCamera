import Foundation

class HysteresisGate {
    var zoomTriggerThreshold: Double = 0.15 // 15% (Relative Error)
    var zoomStopThreshold: Double = 0.05    // 5% (Relative Error)
    
    private(set) var isZooming: Bool = false
    
    func shouldZoom(relativeError: Double) -> Bool {
        let magnitude = abs(relativeError)
        
        if !isZooming {
            // Stable -> Zooming?
            if magnitude > zoomTriggerThreshold {
                isZooming = true
            }
        } else {
            // Zooming -> Stable?
            if magnitude < zoomStopThreshold {
                isZooming = false
            }
        }
        return isZooming
    }
    
    func reset() {
        isZooming = false
    }
}
