//
//  ContentView.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/20.
//

import SwiftUI
import MetalLib

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var previewViewModel: CamPreviewViewModel
    @StateObject private var viewModel: MainViewModel
    @StateObject private var captureProcessor: CaptureProcessor
    
    /// Construct ``ContentView`` given the instance of ``AppStorageConfigProvider``, which provides the information
    /// about the current environment.
    init(configProvider: AppStorageConfigProvider) {
        let previewViewModel = CamPreviewViewModel()
        let captureProcessor = CaptureProcessor(configProvider: configProvider)
        let mainViewModel = MainViewModel(
            camPreviewViewModel: previewViewModel,
            captureProcessor: captureProcessor
        )
        
        self._previewViewModel = StateObject(wrappedValue: previewViewModel)
        self._captureProcessor = StateObject(wrappedValue: captureProcessor)
        self._viewModel = StateObject(wrappedValue: mainViewModel)
    }
    
    // State for Simultaneous Press Detection
    @State private var isVolDownPressed = false
    @State private var isVolUpPressed = false
    
    // Auto-Recording State
    @State private var countdown: Int = 5
    @State private var isRecording: Bool = false
    @State private var hasAutoResumed: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showNoPermissionHint {
                Text("NoPermissionHint")
            } else {
                ZStack {
                    if let session = viewModel.session {
                        CameraPreview(session: session)
                            .ignoresSafeArea()
                            .overlay {
                                // Bounding Box Overlay
                                GeometryReader { geo in
                                    // Draw All Detections (Gray)
                                    ForEach(previewViewModel.allDetectedRects.indices, id: \.self) { index in
                                        let rect = previewViewModel.allDetectedRects[index]
                                        Path { path in
                                            let w = geo.size.width
                                            let h = geo.size.height
                                            
                                            let left = rect.left * w
                                            let top = rect.top * h
                                            let width = rect.width * w
                                            let height = rect.height * h
                                            
                                            path.addRect(CGRect(x: left, y: top, width: width, height: height))
                                        }
                                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                    }
                                    
                                    // Draw Primary Target (Green)
                                    if let rect = previewViewModel.detectedRect {
                                        Path { path in
                                            let w = geo.size.width
                                            let h = geo.size.height
                                            
                                            let left = rect.left * w
                                            let top = rect.top * h
                                            let width = rect.width * w
                                            let height = rect.height * h
                                            
                                            path.addRect(CGRect(x: left, y: top, width: width, height: height))
                                        }
                                        .stroke(Color.green, lineWidth: 4)
                                    }
                                }
                            }
                    } else {
                        Text("Initializing Camera...")
                    }
                }
                    .overlay(alignment: .top) {
                        // Debug Info Overlay
                        VStack(alignment: .leading) {
                            Text(previewViewModel.isManualZoomMode ? "MANUAL ZOOM" : "AUTO ZOOM")
                                .foregroundColor(previewViewModel.isManualZoomMode ? .orange : .green)
                            Text("Skier Height: \(String(format: "%.2f", previewViewModel.skierHeight))")
                                .foregroundColor(.white)
                            Text("Zoom: \(String(format: "%.2f", previewViewModel.currentZoom))x")
                                .foregroundColor(.yellow)
                            Text(previewViewModel.debugLabel)
                                .foregroundColor(.gray)
                                .font(.system(size: 14))
                        }
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.top, 40)
                    }
                    .overlay(alignment: .center) {
                        // Countdown Overlay
                        if countdown > 0 {
                            Text("\(countdown)")
                                .font(.system(size: 120, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 10)
                        } else if isRecording {
                            // Minimal Recording Indicator
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(.top, 40)
                        }
                    }
                
                // Bottom controls removed
            }
        }
        .overlay {
            if !captureProcessor.saveResultText.isEmpty {
                Text(captureProcessor.saveResultText)
                    .padding(12)
                    .foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(12)
            }
        }
        .background {
            Color.black.ignoresSafeArea()
        }
        .animation(.default, value: viewModel.isSettingUpCamera)
        .animation(.default, value: captureProcessor.saveResultText)
        .onPressCapture(
            onPress: {
                // Primary action (Volume Down / Shutter)
                isVolDownPressed = true
                if isVolUpPressed {
                    previewViewModel.resetToAutoZoom()
                } else {
                    previewViewModel.buttonStatus = "Volume DOWN held"
                    previewViewModel.startZoomingOut()
                }
            },
            onRelease: {
                isVolDownPressed = false
                previewViewModel.buttonStatus = "Volume DOWN released"
                previewViewModel.stopZooming()
            },
            secondaryPress: {
                // Secondary action (Volume Up)
                isVolUpPressed = true
                if isVolDownPressed {
                    previewViewModel.resetToAutoZoom()
                } else {
                    previewViewModel.buttonStatus = "Volume UP held"
                    previewViewModel.startZoomingIn()
                }
            },
            secondaryRelease: {
                isVolUpPressed = false
                previewViewModel.buttonStatus = "Volume UP released"
                previewViewModel.stopZooming()
            }
        )
        .task(id: scenePhase) {
            switch scenePhase {
            case .background:
                // Stop Recording on Background
                viewModel.stopRecording()
                await viewModel.stopCamera()
                isRecording = false
                countdown = 5 // Reset countdown for next launch
            case .active:
                await viewModel.updateFromAppContext()
                await viewModel.setup()
                
                // Start Countdown Timer
                 if !isRecording {
                     for i in stride(from: 5, to: 0, by: -1) {
                         try? await Task.sleep(nanoseconds: 1_000_000_000)
                         countdown = i - 1
                     }
                     // Start Recording if session is active
                     if viewModel.session != nil {
                         viewModel.startRecording()
                         isRecording = true
                     }
                 }
                
            default:
                break
            }
        }
        .task {
            previewViewModel.initializeRenderer()
        }
    }
}
