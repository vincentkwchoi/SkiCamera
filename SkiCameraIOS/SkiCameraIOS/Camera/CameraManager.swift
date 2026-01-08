import Foundation
import AVFoundation
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    // MARK: - Published State
    @Published var isRecording = false
    @Published var currentZoom: CGFloat = 1.0
    @Published var detectedRect: Rect? = nil
    @Published var skierHeight: Double = 0.0
    @Published var debugLabel: String = "Initializing..."
    
    // MARK: - Capture Session
    public let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    private let sessionQueue = DispatchQueue(label: "camera_session_queue")
    private let analysisQueue = DispatchQueue(label: "camera_analysis_queue")
    
    // MARK: - Logic / Components
    private let analyzer = SkierAnalyzer()
    private let autoZoomManager = AutoZoomManager()
    
    // MARK: - Init
    override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Setup
    private func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high // 1080p or 4K usually
            
            // 1. Inputs (Video + Audio)
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                return
            }
            
            if self.session.canAddInput(videoInput) {
                self.session.addInput(videoInput)
                self.videoDeviceInput = videoInput
                
                // Configure 60fps
                try? videoDevice.lockForConfiguration()
                if let range = videoDevice.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= 60 }) {
                    videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                }
                videoDevice.unlockForConfiguration()
            }
            
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
                if self.session.canAddInput(audioInput) {
                    self.session.addInput(audioInput)
                }
            }
            
            // 2. Outputs
            // Movie File Output
            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }
            
            // Video Data Output (Analysis)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                
                // Ensure Pixel Format is compatible with Vision (kCVPixelFormatType_32BGRA is good)
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    // MARK: - Actions
    func startRecording() {
        guard !movieOutput.isRecording else { return }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("SkiCam_\(Date().timeIntervalSince1970).mov")
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
    }
    
    func stopRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }
    
    func manualZoom(factor: CGFloat) {
        // Handle manual override intent if needed, or just set zoom directly
        // For now, let's just let AutoZoom handle it or verify parity.
        // If we want manual override, we'd add it to AutoZoomManager state.
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Analysis Loop)
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. Analyze
        analyzer.analyze(pixelBuffer: pixelBuffer) { [weak self] rect in
            guard let self = self else { return }
            
            // 2. Update Logic
            // If rect is nil, we treat it as empty or use sticky state in Manager?
            // Manager expects a Rect. We can pass a "dummy" or just skip update?
            // Manager logic needs continuous updates for smoothing ideally.
            // If no person, we can pass a center rect?
            
            let inputRect = rect ?? Rect.fromLTRB(0.5, 0.5, 0.5, 0.5) // Center point, 0 size
            
            // Let's modify AutoZoomManager to handle "no detection" or handle it here.
            // Android code passes "SharedRect(0.0, 0.0, 1.0, 1.0)" (Full size?) or similar if not found.
            // Let's pass nil or default.
            // If we pass 0 size, it might cause issues. 
            // In Android: `if (bestObject == null) ... onZoomResult(..., "None", ...)`
            // We should do same.
            
            if rect == nil {
                DispatchQueue.main.async {
                    self.detectedRect = nil
                    self.debugLabel = "Label: None"
                }
                // Don't update zoom if nothing found? Or slowly revert?
                // For now, skip zoom update if no detection.
                return
            }
            
            let detected = rect!
            let dt = 1.0 / 60.0 // Approximate
            
            let newCrop = self.autoZoomManager.update(skierRect: detected, dt: dt)
            
            // 3. Actuate Zoom
            // newCrop.width is the scale factor (0.0 - 1.0)
            // Zoom Factor = 1.0 / width
            let targetZoom = 1.0 / max(0.01, newCrop.width)
            
            self.applyZoom(targetZoom)
            
            // 4. Update UI State
            DispatchQueue.main.async {
                self.detectedRect = detected
                self.skierHeight = detected.height
                self.debugLabel = "Label: Person"
                self.currentZoom = targetZoom
            }
        }
    }
    
    private func applyZoom(_ zoom: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            // Ramp for smoothness? Or set directly (since AutoZoomManager already smoothes)?
            // AutoZoomManager is smoothed. Set directly.
            let clamped = max(1.0, min(device.activeFormat.videoMaxZoomFactor, zoom))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("Zoom failed: \(error)")
        }
    }
    
    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        if error == nil {
            // Save to Photos
            UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
}
