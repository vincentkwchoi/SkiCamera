//
//  SkiCaptureViewFinder.swift
//  SkiCapture
//
//  Created by Vincent Choi on 2025-12-26.
//

import SwiftUI
import LockedCameraCapture
import AVFoundation
import UIKit
import AVKit

struct SkiCaptureViewFinder: View {
    @ObservedObject var cameraManager = CameraManager()
    let session: LockedCameraCaptureSession
    
    var body: some View {
        ZStack {
            CameraPreview(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .onPressCapture(parent: self)
            
            VStack {
                // Top Indicators
                HStack {
                    Spacer()
                    if cameraManager.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("REC")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .bold))
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(4)
                        }
                        .padding(.top, 50) // Safe area padding estimate
                        .padding(.trailing, 20)
                    }
                }
                
                Spacer()
                
                // Custom Controls
                Button(action: {
                    if cameraManager.isRecording {
                        stopAndSave()
                    } else {
                        startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        if cameraManager.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.red, lineWidth: cameraManager.isRecording ? 4 : 0)
                .edgesIgnoringSafeArea(.all)
        )
        .onAppear {
             // Setup if needed
        }
    }
    
    func startRecording() {
        let filename = UUID().uuidString + ".mov"
        let outputURL = session.sessionContentURL.appendingPathComponent(filename)
        cameraManager.startRecording(outputURL: outputURL)
    }
    
    func stopAndSave() {
        cameraManager.stopRecording()
    }
    
    func handleInteractionEvent() {
        if cameraManager.isRecording {
            stopAndSave()
        } else {
            startRecording()
        }
    }
}


extension View {
    func onPressCapture(parent: SkiCaptureViewFinder) -> some View {
        self.background(CaptureInteractionView(parent: parent))
    }
}

struct CaptureInteractionView: UIViewRepresentable {
    var parent: SkiCaptureViewFinder
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { event in
                // Only trigger on the start of the press
                if event.phase == .began {
                    parent.handleInteractionEvent()
                }
            }
            view.addInteraction(interaction)
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
