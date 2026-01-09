//
//  DemoApp.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/20.
//

import SwiftUI
import AppIntents

import OSLog

@main
struct SkiCameraIOSApp: App {
    @StateObject private var sessionImporter = SessionImporter()
    
    init() {
        let logger = Logger(subsystem: "com.vcnt.skicamera", category: "AppLifecycle")
        logger.log(level: .default, "Main App Launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(configProvider: AppStorageConfigProvider.standard)
                .environmentObject(sessionImporter)
        }
    }
}
