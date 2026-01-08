import Foundation
import Vision
import CoreImage
import CoreML

class SkierAnalyzer {
    
    // State
    private var lastKnownCenter: CGPoint?
    
    // YOLOv8 Model
    private let model: VNCoreMLModel
    private let request: VNCoreMLRequest
    
    init() {
        // Load YOLOv8 CoreML model
        guard let mlModel = try? yolov8n(configuration: MLModelConfiguration()).model else {
            fatalError("Failed to load yolov8n model")
        }
        
        guard let visionModel = try? VNCoreMLModel(for: mlModel) else {
            fatalError("Failed to create VNCoreMLModel")
        }
        
        self.model = visionModel
        self.request = VNCoreMLRequest(model: visionModel)
        self.request.imageCropAndScaleOption = .scaleFill
    }
    
    func analyze(pixelBuffer: CVPixelBuffer, completion: @escaping ((Rect?, [Rect])?) -> Void) {
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                self.lastKnownCenter = nil
                completion(nil)
                return
            }
            
            // Filter for "person" class (class 0 in COCO)
            let persons = results.filter { observation in
                guard let label = observation.labels.first?.identifier else { return false }
                return label == "person"
            }
            
            guard !persons.isEmpty else {
                self.lastKnownCenter = nil
                completion(nil)
                return
            }
            
            // Convert all observations to our Rect format
            let allRects = persons.map { person -> Rect in
                let vRect = person.boundingBox
                let left = vRect.minX
                let top = 1.0 - (vRect.minY + vRect.height)
                let right = left + vRect.width
                let bottom = top + vRect.height
                return Rect.fromLTRB(left, top, right, bottom)
            }
            
            // Sticky Tracking: Select closest to lastKnownCenter or frame center
            let targetPoint = lastKnownCenter ?? CGPoint(x: 0.5, y: 0.5)
            
            let bestPerson = persons.min(by: { p1, p2 in
                let c1 = CGPoint(x: p1.boundingBox.midX, y: p1.boundingBox.midY)
                let c2 = CGPoint(x: p2.boundingBox.midX, y: p2.boundingBox.midY)
                
                let dist1 = pow(c1.x - targetPoint.x, 2) + pow(c1.y - targetPoint.y, 2)
                let dist2 = pow(c2.x - targetPoint.x, 2) + pow(c2.y - targetPoint.y, 2)
                
                return dist1 < dist2
            })
            
            var primaryRect: Rect? = nil
            if let best = bestPerson {
                lastKnownCenter = CGPoint(x: best.boundingBox.midX, y: best.boundingBox.midY)
                
                let vRect = best.boundingBox
                let left = vRect.minX
                let top = 1.0 - (vRect.minY + vRect.height)
                let right = left + vRect.width
                let bottom = top + vRect.height
                primaryRect = Rect.fromLTRB(left, top, right, bottom)
            }
            
            completion((primaryRect, allRects))
            
        } catch {
            print("Vision failed: \(error)")
            completion(nil)
        }
    }
}
