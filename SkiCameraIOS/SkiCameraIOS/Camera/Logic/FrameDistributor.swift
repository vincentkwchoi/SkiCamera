import AVFoundation
import Foundation

/// Acts as the delegate for AVCaptureVideoDataOutput and distributes frames
/// to multiple consumers: one for immediate preview, one for analysis.
class FrameDistributor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Consumers
    var onPreviewFrame: ((CMSampleBuffer) -> Void)?
    var onAnalysisFrame: ((CMSampleBuffer) -> Void)?
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 1. Fast Path: Immediate Preview
        onPreviewFrame?(sampleBuffer)
        
        // 2. Analysis Path
        // We pass the buffer to the analysis service. 
        // Throttling can happen here or inside the service.
        // For cleaner separation, let's pass every frame and let the Service decide what to skip.
        onAnalysisFrame?(sampleBuffer)
    }
}
