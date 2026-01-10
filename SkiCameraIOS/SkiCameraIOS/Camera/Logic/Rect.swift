import Foundation

struct Rect {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
    let confidence: Float // Added for ByteTrack
    
    init(left: Double, top: Double, right: Double, bottom: Double, confidence: Float = 1.0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.confidence = confidence
    }
    
    var width: Double { right - left }
    var height: Double { bottom - top }
    var centerX: Double { (left + right) / 2.0 }
    var centerY: Double { (top + bottom) / 2.0 }
    
    // Helper property to convert to CGPoint
    var center: CGPoint {
        return CGPoint(x: centerX, y: centerY)
    }
    
    static func fromCenter(cx: Double, cy: Double, width: Double, height: Double, confidence: Float = 1.0) -> Rect {
        let left = cx - width / 2.0
        let top = cy - height / 2.0
        return Rect(left: left, top: top, right: left + width, bottom: top + height, confidence: confidence)
    }
    
    static func fromLTRB(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, confidence: Float = 1.0) -> Rect {
        return Rect(left: left, top: top, right: right, bottom: bottom, confidence: confidence)
    }
}
