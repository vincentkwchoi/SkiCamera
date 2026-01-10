import Foundation
import Vision
import CoreImage
import CoreML

class SkierDetection {
    
    // State (Stateless now, but keeping class structure)
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
    
    func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([Rect]) -> Void) {
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            // Refactor: Filter for "person" class and allow lower confidence for ByteTrack
            let persons = results.filter { observation in
                guard let label = observation.labels.first else { return false }
                // Allow low confidence (e.g. 0.1) so ByteTrack can "recover" faint tracks
                return label.identifier == "person" && label.confidence > 0.1
            }
            
            guard !persons.isEmpty else {
                completion([])
                return
            }
            
            // Convert all observations to our Rect format
            let allRects = persons.map { person -> Rect in
                let vRect = person.boundingBox
                let left = vRect.minX
                let top = 1.0 - (vRect.minY + vRect.height)
                let right = left + vRect.width
                let bottom = top + vRect.height
                // Extract Confidence
                let conf = person.labels.first?.confidence ?? 0.0
                return Rect.fromLTRB(left, top, right, bottom, confidence: conf)
            }
            
            // Refactor: We now return strictly ALL rects. 
            // Selection is handled downstream by SkierSelection.
            completion(allRects)
            
        } catch {
            print("Vision failed: \(error)")
            completion([])
        }
    }
}
