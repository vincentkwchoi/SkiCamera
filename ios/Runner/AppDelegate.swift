import Flutter
import UIKit
import Photos
#if canImport(LockedCameraCapture)
import LockedCameraCapture
#endif
import AppIntents

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    if #available(iOS 18.0, *) {
        Task {
            for await sessionUpdate in LockedCameraCaptureManager.shared.sessionContentUpdates {
                switch sessionUpdate {
                case .initial(let urls):
                    for url in urls {
                        await processCapturedContent(at: url)
                        try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: url)
                    }
                case .added(let url):
                    await processCapturedContent(at: url)
                    try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: url)
                case .removed:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
    
  @available(iOS 18.0, *)
  @available(iOS 18.0, *)
  func processCapturedContent(at directoryURL: URL) async {
       // The URL is a directory containing the captured content.
       // We need to iterate over the files in this directory.
       
       guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
           return
       }
       
       for url in fileURLs {
           let fileExtension = url.pathExtension.lowercased()
           if fileExtension == "mov" || fileExtension == "mp4" {
               try? await PHPhotoLibrary.shared().performChanges {
                   PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
               }
           } else if fileExtension == "jpg" || fileExtension == "jpeg" || fileExtension == "heic" || fileExtension == "dng" {
                try? await PHPhotoLibrary.shared().performChanges {
                   PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
               }
           }
       }
  }
}


// Add imports for iOS 18 specific frameworks
// NOTE: These weak imports ensure code compiles even if target is lower, 
// though actual usage is guarded by @available.

