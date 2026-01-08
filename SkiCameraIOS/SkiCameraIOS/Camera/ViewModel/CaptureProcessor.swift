//
//  CaptureProcessor.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/21.
//
import AVFoundation
import Photos

class CaptureProcessor: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published var saveResultText: String = ""
    
    let configProvider: AppStorageConfigProvider
    
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
            print("photoOutput didFinishProcessingPhoto error \(error)")
            return
        }
        
        Task { @MainActor in
            await savePhotoToLibrary(photo)
        }
    }
    
    // MARK: - Video Delegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording failed: \(error)")
            return
        }
        
        Task { @MainActor in
            await saveMovieToLibrary(outputFileURL)
        }
    }
    
    @MainActor
    private func saveMovieToLibrary(_ fileURL: URL) async {
        let saved = await saveMovieToLibraryInternal(fileURL)
        if saved {
            saveResultText = "Video Saved to Photos"
        } else {
            saveResultText = "Failed to save video"
        }
        
        do {
            try await Task.sleep(for: .seconds(2))
            saveResultText = ""
        } catch {
            // ignored
        }
    }
    
    private nonisolated func saveMovieToLibraryInternal(_ fileURL: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                print("saveMovieToLibrary, success: \(success), error: \(String(describing: error))")
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
        guard let photoData = photo.fileDataRepresentation() else {
            print("can't get photoData")
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
            print("can't get fileURL")
            return false
        }
        
        print("savePhotoToLibraryInternal, fileURL is \(String(describing: fileURL))")
        
        do {
            try photoData.write(to: fileURL)
        } catch {
            print("savePhotoToLibraryInternal, failed to write to file \(error)")
            return false
        }
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let _ = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            } completionHandler: { success, error in
                print("savePhotoToLibrary, success: \(success), error: \(String(describing: error))")
                continuation.resume(returning: success)
            }
        }
    }
}
