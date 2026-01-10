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
        
        Task {
            let success = await saveMovieToLibraryInternal(outputFileURL)
            Task { @MainActor in
                saveResultText = success ? "Saved" : "Save Failed"
                if success {
                    onSaveSuccess?()
                }
            }
        }
    }
    
    @MainActor
    private func saveMovieToLibrary(_ fileURL: URL) async {
        let success = await saveMovieToLibraryInternal(fileURL)
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
    
    private nonisolated func saveMovieToLibraryInternal(_ fileURL: URL) async -> Bool {
        // We now use PhotoKit for BOTH Locked and Unlocked modes.
        // Locked Camera Extensions support writing to PhotoKit even when locked.
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
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
    }
    
    @MainActor
    private func savePhotoToLibrary(_ photo: AVCapturePhoto) async {
        let saved = await savePhotoToLibraryInternal(photo)
        if saved {
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
    
    private nonisolated func savePhotoToLibraryInternal(_ photo: AVCapturePhoto) async -> Bool {
        let logger = Logger(subsystem: "com.vcnt.skicamera", category: "CaptureProcessor")
        
        guard let photoData = photo.fileDataRepresentation() else {
            logger.log(level: .default, "can't get photoData")
            return false
        }
        
        // Saving the data to a file isn't strictly necessary since
        // PHAssetCreationRequest can accept Data directly.
        // However, this example demonstrates saving the photo data to a temporary file
        // using a container URL provided by the environment.
        guard let fileURL = configProvider.rootURL?.appendingPathComponent(
            UUID().uuidString,
            conformingTo: .heic
        ) else {
            logger.log(level: .default, "can't get fileURL")
            return false
        }
        
        logger.log(level: .default, "savePhotoToLibraryInternal, fileURL is \(fileURL.path, privacy: .public)")
        
        do {
            try photoData.write(to: fileURL)
        } catch {
            logger.log(level: .default, "savePhotoToLibraryInternal, failed to write to file \(error.localizedDescription)")
            return false
        }
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let _ = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            } completionHandler: { success, error in
                logger.log(level: .default, "savePhotoToLibrary, success: \(success), error: \(String(describing: error))")
                continuation.resume(returning: success)
            }
        }
    }
}
