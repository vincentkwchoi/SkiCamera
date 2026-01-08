//
//  ContentView.swift
//  LockedCameraCaptureExtensionDemo
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
                            Text(previewViewModel.debugLabel)
                                .foregroundColor(.green)
                            Text("H: \(String(format: "%.2f", previewViewModel.skierHeight)) / 0.15")
                                .foregroundColor(.white)
                            Text("Zoom: \(String(format: "%.2f", previewViewModel.currentZoom))x")
                                .foregroundColor(.yellow)
                            Text(previewViewModel.buttonStatus)
                                .foregroundColor(.cyan)
                        }
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.top, 40)
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
        .onPressCapture {
            // Primary action (Volume Down)
            previewViewModel.buttonStatus = "Volume DOWN pressed"
            previewViewModel.zoomOut()
        } secondaryAction: {
            // Secondary action (Volume Up)
            previewViewModel.buttonStatus = "Volume UP pressed"
            previewViewModel.zoomIn()
        }
        .task(id: scenePhase) {
            switch scenePhase {
            case .background:
                await viewModel.stopCamera()
            case .active:
                await viewModel.updateFromAppContext()
                await viewModel.setup()
            default:
                break
            }
        }
        .task {
            previewViewModel.initializeRenderer()
        }
    }
}
