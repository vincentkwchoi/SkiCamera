//
//  ContentView.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/20.
//

import SwiftUI
import MetalLib
import OSLog

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var previewViewModel: CamPreviewViewModel
    @StateObject private var viewModel: MainViewModel
    @StateObject private var captureProcessor: CaptureProcessor
    @StateObject private var autoZoomService: AutoZoomService // [New]
    @StateObject private var autoZoomService: AutoZoomService // [New]
    
    /// Construct ``ContentView`` given the instance of ``AppStorageConfigProvider``, which provides the information
    /// about the current environment.
    init(configProvider: AppStorageConfigProvider) {
        let previewViewModel = CamPreviewViewModel()
        let captureProcessor = CaptureProcessor(configProvider: configProvider)
        let autoZoomService = AutoZoomService()
        let mainViewModel = MainViewModel(
            camPreviewViewModel: previewViewModel,
            captureProcessor: captureProcessor,
            autoZoomService: autoZoomService
        )
        
        self._previewViewModel = StateObject(wrappedValue: previewViewModel)
        self._captureProcessor = StateObject(wrappedValue: captureProcessor)
        self._viewModel = StateObject(wrappedValue: mainViewModel)
        self._autoZoomService = StateObject(wrappedValue: autoZoomService)
    }
    
    // State for Simultaneous Press Detection
    @State private var isVolDownPressed = false
    @State private var isVolUpPressed = false
    @State private var lastVolDownPressTime: Date? = nil
    @State private var lastVolUpPressTime: Date? = nil
    
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
                                    ForEach(autoZoomService.allDetectedRects.indices, id: \.self) { index in
                                        let rect = autoZoomService.allDetectedRects[index]
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
                                    if let rect = autoZoomService.detectedRect {
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
                            Text(autoZoomService.isManualZoomMode ? "MANUAL ZOOM" : "AUTO ZOOM")
                                .foregroundColor(autoZoomService.isManualZoomMode ? .orange : .green)
                            Text(captureProcessor.configProvider.isLockedCapture ? "LOCKED" : "UNLOCKED")
                                .foregroundColor(captureProcessor.configProvider.isLockedCapture ? .red : .green)
                            Text("Skier Height: \(String(format: "%.2f", autoZoomService.skierHeight))")
                                .foregroundColor(.white)
                            Text(autoZoomService.debugLabel) // Detailed Debug Info
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                            Text("Zoom: \(String(format: "%.2f", autoZoomService.currentZoom))x")
                                .foregroundColor(.yellow)
                            Text("Analysis: \(String(format: "%.1f", autoZoomService.analysisDurationMs))ms")
                                .foregroundColor(.cyan)
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
                    .overlay(alignment: .bottom) {
                        if isRecording {
                            Button(action: {
                                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                                logger.log(level: .default, "Stop Button Pressed")
                                viewModel.stopRecording()
                                isRecording = false
                            }) {
                                Image(systemName: "stop.circle.fill")
                                    .resizable()
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.red, .white)
                                    .frame(width: 80, height: 80)
                                    .shadow(radius: 4)
                                    .padding(.bottom, 50)
                            }
                        }
                    }
                
                // Bottom controls removed
            }
        }
        .overlay {
            // Import Button Overlay Removed

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
                // Double Click Detection (Volume Down)
                let now = Date()
                if let last = lastVolDownPressTime, now.timeIntervalSince(last) < 0.4 {
                    let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                    logger.log(level: .default, "Volume DOWN Double Click Detected")
                    if isRecording {
                        logger.log(level: .default, "Stopping Recording via Double Click")
                        viewModel.stopRecording()
                        isRecording = false
                    }
                    lastVolDownPressTime = nil // Reset to avoid triple click issues
                    return
                }
                lastVolDownPressTime = now
                
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Volume DOWN pressed (Primary)")
                // Primary action (Volume Down / Shutter)
                isVolDownPressed = true
                if isVolUpPressed {
                    autoZoomService.resetToAutoZoom()
                } else {
                    autoZoomService.buttonStatus = "Volume DOWN held"
                    autoZoomService.startZoomingOut()
                }
            },
            onRelease: {
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Volume DOWN released")
                isVolDownPressed = false
                autoZoomService.buttonStatus = "Volume DOWN released"
                autoZoomService.stopZooming()
            },
            secondaryPress: {
                // Double Click Detection (Volume Up)
                let now = Date()
                if let last = lastVolUpPressTime, now.timeIntervalSince(last) < 0.4 {
                    let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                    logger.log(level: .default, "Volume UP Double Click Detected")
                    if isRecording {
                        logger.log(level: .default, "Stopping Recording via Double Click")
                        viewModel.stopRecording()
                        isRecording = false
                    }
                    lastVolUpPressTime = nil // Reset
                    return
                }
                lastVolUpPressTime = now

                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Volume UP pressed (Secondary)")
                // Secondary action (Volume Up)
                isVolUpPressed = true
                if isVolDownPressed {
                    autoZoomService.resetToAutoZoom()
                } else {
                    autoZoomService.buttonStatus = "Volume UP held"
                    autoZoomService.startZoomingIn()
                }
            },
            secondaryRelease: {
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Volume UP released")
                isVolUpPressed = false
                autoZoomService.buttonStatus = "Volume UP released"
                autoZoomService.stopZooming()
            }
        )
        .task(id: scenePhase) {
            switch scenePhase {
            case .active:
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Scene Phase: Active")
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
                
            case .background, .inactive:
                let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
                logger.log(level: .default, "Scene Phase: \(scenePhase == .background ? "Background" : "Inactive")")
                // Stop Recording on Background or Inactive (e.g. screen lock)
                viewModel.stopRecording()
                // Only stop camera session on background to save power, but inactive might need it kept alive briefly?
                // For LockedCapture, we want to ensure recording stops and saves.
                if isRecording {
                    logger.log(level: .default, "Stopping recording due to phase change")
                    isRecording = false
                }
                
                if scenePhase == .background {
                     await viewModel.stopCamera()
                     countdown = 5 // Reset countdown for next launch
                }
            
            @unknown default:
                break
            }
        }
        .onDisappear {
            let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
            logger.log(level: .default, "ContentView Disappeared")
            // Ensure recording is stopped when view disappears (e.g. extension killed/dismissed)
            if isRecording {
                logger.log(level: .default, "Stopping recording due to onDisappear")
                viewModel.stopRecording()
                isRecording = false
            }
            Task {
                await viewModel.stopCamera()
            }
        }
        .task {
            previewViewModel.initializeRenderer()
            
            // Wire up CaptureProcessor to SessionImporter for auto-refresh (Main App Only) - REMOVED
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LockedCameraStopRecording"))) { _ in
            let logger = Logger(subsystem: "com.vcnt.skicamera", category: "ContentView")
            logger.log(level: .default, "Received LockedCameraStopRecording notification")
            if isRecording {
                logger.log(level: .default, "Stopping recording due to Notification")
                viewModel.stopRecording()
                isRecording = false
            }
            Task {
                await viewModel.stopCamera()
            }
        }
    }
}
