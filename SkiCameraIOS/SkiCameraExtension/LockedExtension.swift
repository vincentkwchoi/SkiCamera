import Foundation
import LockedCameraCapture
import SwiftUI
import ExtensionKit

@main
struct SkiCameraExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedContentView(session: session)
        }
    }
}

struct LockedContentView: View {
    let session: LockedCameraCaptureSession
    
    var body: some View {
        ZStack {
            // Re-use our main app content
            // NOTE: ContentView.swift must be added to the Extension Target
            ContentView()
            
            // Overlay "Open App" button top-right
            VStack {
                HStack {
                    Spacer()
                    OpenMainAppButton(session: session)
                }
                Spacer()
            }
            .padding()
        }
    }
}
