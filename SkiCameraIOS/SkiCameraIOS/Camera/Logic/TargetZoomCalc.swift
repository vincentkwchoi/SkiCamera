import Foundation

class TargetZoomCalc {
    var targetSubjectHeightRatio: Double = 0.15
    private let smoother = SmoothingFilter(alpha: 0.2)
    
    func calculateError(subject: Rect, currentZoom: Double) -> Double {
        // 1. Smooth Input
        let smoothedHeight = smoother.filter(subject.height)
        
        // 2. Calculate Error (Target - Current)
        // iOS Vision receives the ZOOMED buffer, so smoothedHeight IS the height in crop.
        // Error = Target - HeightInCrop
        let error = targetSubjectHeightRatio - smoothedHeight
        return error
    }
    
    func reset() {
        smoother.reset()
    }
}
