//
//  CaptureProcessor.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/21.
//
import AVFoundation
import Photos
import OSLog

class CaptureProcessor: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published var saveResultText: String = ""
    
    // Create a logger instance for your specific module
    private let logger = Logger(subsystem: "com.vcnt.skicamera", category: "CaptureProcessor")
    
    let configProvider: AppStorageConfigProvider
    var onSaveSuccess: (() -> Void)?
    
    init(configProvider: AppStorageConfigProvider) {
        self.configProvider = configProvider
    }
    
    // MARK: - Photo Delegate
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error = error {
            logger.log(level: .default, "photoOutput didFinishProcessingPhoto error \(error.localizedDescription)")
            return
        }
        
        Task { @MainActor in
            await savePhotoToLibrary(photo)
        }
    }
    
    // MARK: - Video Delegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        var recordingSuccesfullyFinished = false
        if let error = error as NSError? {
             if let success = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool, success {
                 recordingSuccesfullyFinished = success
                 logger.log(level: .default, "Recording stopped by system but file is valid: \(error.localizedDescription)")
             } else {
                 logger.log(level: .default, "Video recording failed: \(error.localizedDescription)")
                 Task { @MainActor in
                      saveResultText = "Rec Error: \(error.localizedDescription)"
                 }
                 return
             }
         }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? -1
        logger.log(level: .default, "Recording finished. File size: \(fileSize) bytes at \(outputFileURL.path, privacy: .public)")

        if fileSize < 10000 {
            logger.log(level: .default, "Video too short (less than 10KB), deleting.")
            try? FileManager.default.removeItem(at: outputFileURL)
             Task { @MainActor in
                 saveResultText = "Video too short/empty"
            }
            return
        }
        
        // Use the centralized save logic
        Task { @MainActor in
            await saveMovieToLibrary(outputFileURL)
        }
    }
    
    @MainActor
    private func saveMovieToLibrary(_ fileURL: URL) async {
        // Use PhotoKit for saving
        let success = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                // Logic runs on arbitrary queue, so capturing logger or self is tricky if not careful.
                // But we are inside an async function on MainActor.
                // The completion handler is escaping.
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "CaptureProcessor")
                if success {
                    logger.log(level: .default, "saveMovieToLibrary: Successfully saved to Photos")
                } else {
                    logger.log(level: .default, "saveMovieToLibrary failed: \(String(describing: error))")
                }
                
                // Cleanup temp file
                try? FileManager.default.removeItem(at: fileURL)
                continuation.resume(returning: success)
            }
        }
        
        saveResultText = success ? "Video Saved to Photos" : "Failed to save video"
        
        if success {
            onSaveSuccess?()
        }
        
        do {
            try await Task.sleep(for: .seconds(2))
            saveResultText = ""
        } catch {
            // ignored
        }
    }
    
    @MainActor
    private func savePhotoToLibrary(_ photo: AVCapturePhoto) async {
        let logger = Logger(subsystem: "com.vcnt.skicamera", category: "CaptureProcessor")

        guard let photoData = photo.fileDataRepresentation() else {
            logger.log(level: .default, "can't get photoData")
            saveResultText = "Failed to process photo"
            return
        }
        
        // Save directly using Data (no temp file needed)
        let success = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                // We can just use the standard creation request for data
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: photoData, options: options)
            } completionHandler: { success, error in
                logger.log(level: .default, "savePhotoToLibrary, success: \(success), error: \(String(describing: error))")
                continuation.resume(returning: success)
            }
        }
        
        if success {
            saveResultText = "Saved to Photo Library"
        } else {
            saveResultText = "Failed to save, see the console for more details"
        }
        
        do {
            try await Task.sleep(for: .seconds(2))
            saveResultText = ""
        } catch {
            // ignored
        }
    }
}
