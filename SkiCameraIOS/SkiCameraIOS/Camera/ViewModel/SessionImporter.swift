//
//  SessionImporter.swift
//  SkiCameraIOS
//
//  Created by SkiCamera Team on 2026/01/08.
//

import Foundation
import LockedCameraCapture
import Photos
import SwiftUI
import OSLog

@available(iOS 18.0, *)
@MainActor
class SessionImporter: ObservableObject {
    @Published var isImporting = false
    @Published var importStatus = ""
    @Published var detectedFiles: [URL] = []
    
    // Create a logger instance for your specific module
    let logger = Logger(subsystem: "com.vcnt.skicamera", category: "SessionImporter")
    
    init() {
        logger.log(level: .default, "Initialized")
    }
    
    func scanForSessions() async {
        let sessionURLs = LockedCameraCaptureManager.shared.sessionContentURLs
        
        logger.log(level: .default, "--- DEBUG TEMP STORAGE CHECK ---")
        logger.log(level: .default, "Found \(sessionURLs.count) session directories.")
        
        var foundFiles: [URL] = []
        
        for url in sessionURLs {
            logger.log(level: .default, "Scanning session directory: \(url.path, privacy: .public)")
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
                let videos = contents.filter { $0.pathExtension.lowercased() == "mov" }
                
                for video in videos {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: video.path)
                    let size = attributes?[.size] as? Int64 ?? -1
                    logger.log(level: .default, "  - File: \(video.lastPathComponent, privacy: .public)")
                    logger.log(level: .default, "    Path: \(video.path, privacy: .public)")
                    logger.log(level: .default, "    Size: \(size) bytes")
                    foundFiles.append(video)
                }
            } catch {
                logger.log(level: .default, "  - Error scanning \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        logger.log(level: .default, "--------------------------------")
        logger.log(level: .default, "Total found video files: \(foundFiles.count)")
        
        self.detectedFiles = foundFiles
        
        if foundFiles.isEmpty {
            importStatus = "No new videos found"
        } else {
            importStatus = "Found \(foundFiles.count) videos ready to import"
        }
    }
    
    func performImport() async {
        guard await requestPermission() else {
            logger.log(level: .default, "Missing Photo Library permissions")
            importStatus = "Missing Permissions"
            return
        }
        
        guard !detectedFiles.isEmpty else { return }
        
        isImporting = true
        importStatus = "Importing \(detectedFiles.count) videos..."
        
        var successCount = 0
        
        for url in detectedFiles {
            logger.log(level: .default, "Importing: \(url.lastPathComponent, privacy: .public)")
            let success = await saveToPhotos(url)
            
            if success {
                do {
                    try FileManager.default.removeItem(at: url)
                    logger.log(level: .default, "Imported and deleted: \(url.lastPathComponent)")
                    successCount += 1
                } catch {
                    logger.log(level: .default, "Failed to delete original: \(error.localizedDescription)")
                }
            } else {
                logger.log(level: .default, "Failed to save to Photos: \(url.lastPathComponent)")
            }
        }
        
        isImporting = false
        importStatus = "Imported \(successCount) videos"
        
        // Rescan to update list
        await scanForSessions()
    }
    
    private func saveToPhotos(_ url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    let logger = Logger(subsystem: "com.vcnt.skicamera", category: "SessionImporter")
                    logger.log(level: .default, "PHPhotoLibrary error: \(String(describing: error))")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func requestPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }
}
