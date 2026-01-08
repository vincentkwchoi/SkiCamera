import Foundation
import Vision
import CoreImage

class SkierAnalyzer {
    
    private var completion: ((Rect?) -> Void)?
    private var sequenceHandler = VNSequenceRequestHandler()
    
    // Config
    private let humanRequest = VNDetectHumanRectanglesRequest()
    
    init() {
        humanRequest.upperBodyOnly = false // Force full body detection
    }
    
    func analyze(pixelBuffer: CVPixelBuffer, completion: @escaping (Rect?) -> Void) {
        
        // Vision request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        // Note: Orientation .right means Home button on right (Landscape). 
        // We assume the sensor raw data is landscape. AVFoundation usually delivers landscape buffers.
        
        do {
            try handler.perform([humanRequest])
            
            guard let observations = humanRequest.results, !observations.isEmpty else {
                completion(nil)
                return
            }
            
            // Heuristic: Select person CLOSEST TO CENTER
            // Center is (0.5, 0.5)
            // Vision BoundingBox is normalized 0..1
            let person = observations.min(by: { p1, p2 in
                let c1 = CGPoint(x: p1.boundingBox.midX, y: p1.boundingBox.midY)
                let c2 = CGPoint(x: p2.boundingBox.midX, y: p2.boundingBox.midY)
                let dist1 = pow(c1.x - 0.5, 2) + pow(c1.y - 0.5, 2)
                let dist2 = pow(c2.x - 0.5, 2) + pow(c2.y - 0.5, 2)
                return dist1 < dist2
            })!
            
            // Vision Coords: (0,0) is Bottom-Left. Normalized 0..1
            // We need Top-Left normalized.
            // Rect (x, y, w, h)
            // Vision y is from bottom.
            // Converted Y (top-left origin) = 1.0 - (y + height)
            
            let vRect = person.boundingBox
            
            // Fix Coordinate System
            // Vision: Origin Bottom-Left.
            // Target: Origin Top-Left.
            // x = x
            // y_top = 1.0 - (y_bottom + height)
            
            let left = vRect.minX
            let bottomFromVision = vRect.minY // Distance from bottom
            let height = vRect.height
            
            // Top in Top-Left coords = 1.0 - (bottomFromVision + height) -> No
            // Let's trace.
            // Vision Y=0 is bottom. Y=1 is top.
            // A box at bottom: y=0, h=0.2.
            // In Top-Left: Top is at 1.0 - (0 + 0.2) = 0.8?
            // Wait.
            // TL(0,0) is Top.
            // TL y = (1 - VisionMaxY)
            
            let top = 1.0 - (vRect.minY + vRect.height)
            let right = left + vRect.width
            let bottom = top + vRect.height
            
            let rect = Rect.fromLTRB(left, top, right, bottom)
            completion(rect)
            
        } catch {
            print("Vision failed: \(error)")
            completion(nil)
        }
    }
}
