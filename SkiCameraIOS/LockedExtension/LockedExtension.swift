//
//  LockedExtension.swift
//  LockedExtension
//
//  Created by Photon Juniper on 2024/8/20.
//

import Foundation
import LockedCameraCapture
import SwiftUI

import OSLog

@main
struct LockedExtension: LockedCameraCaptureExtension {
    init() {
        let logger = Logger(subsystem: "com.vcnt.skicamera", category: "AppLifecycle")
        logger.log(level: .default, "Locked Capture Extension Launched")
    }

    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCameraCaptureView(session: session)
        }
    }
}

struct LockedCameraCaptureView: View {
    let session: LockedCameraCaptureSession
    @StateObject private var sessionImporter = SessionImporter()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        // In LockedCameraCaptureExtensionScene, scenePhase will not be active.
        // Thus we need to set the scenePhase to active manually.
        ContentView(configProvider: AppStorageConfigProvider(session))
            .environment(\.scenePhase, .active)
            .environment(\.openMainApp, OpenMainAppAction(session: session))
            .environmentObject(sessionImporter)
            .onChange(of: scenePhase) { newPhase in
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "LockedExtension")
                logger.log(level: .default, "Real Scene Phase changed to: \(newPhase == .background ? "Background" : (newPhase == .inactive ? "Inactive" : "Active"), privacy: .public)")
                
                if newPhase == .inactive || newPhase == .background {
                    logger.log(level: .default, "Posting notification to stop recording...")
                    NotificationCenter.default.post(name: Notification.Name("LockedCameraStopRecording"), object: nil)
                }
            }
            .onCameraCaptureEvent { event in
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "LockedExtension")
                switch event.phase {
                case .began:
                    logger.log(level: .default, "Capture event began")
                case .ended:
                    logger.log(level: .default, "Capture event ended")
                case .cancelled:
                    logger.log(level: .default, "Capture event cancelled - ensuring recording stops")
                    NotificationCenter.default.post(name: Notification.Name("LockedCameraStopRecording"), object: nil)
                @unknown default:
                    break
                }
            }
    }
}
