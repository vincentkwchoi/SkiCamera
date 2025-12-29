//
//  SkiCapture.swift
//  SkiCapture
//
//  Created by Vincent Choi on 2025-12-26.
//

import ExtensionKit
import Foundation
import LockedCameraCapture
import AppIntents
import SwiftUI

@main
struct SkiCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            SkiCaptureViewFinder(session: session)
        }
    }
}

