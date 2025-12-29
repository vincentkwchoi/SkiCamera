//
//  SkiCaptureIntent.swift
//  SkiCapture
//
//  Created by Vincent Choi on 2025-12-26.
//

import AppIntents
import LockedCameraCapture

@available(iOS 18.0, *)
struct SkiCaptureIntent: CameraCaptureIntent {
    static var title: LocalizedStringResource = "Quick Record"
    static var description = IntentDescription("Immediately start recording a ski run.")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
