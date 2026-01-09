//
//  MainViewModel.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/20.
//
import SwiftUI
import AVFoundation
import Photos
import LockedCameraCapture
import Models
import OSLog

class MainViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.vcnt.skicamera", category: "MainViewModel")
    
    @Published var showNoPermissionHint: Bool = false
    @Published var cameraPosition: CameraPosition = .back {
        didSet {
            Task {
                await updateAppContext()
            }
        }
    }
    @Published var isSettingUpCamera = false
    @Published var showFlashScreen = false
    
    public var session: AVCaptureSession? = nil
    private var photoOutput: AVCapturePhotoOutput? = nil
    private var movieOutput: AVCaptureMovieFileOutput? = nil
    private var videoDevice: AVCaptureDevice? = nil
    
    private let camPreviewViewModel: CamPreviewViewModel
    private let captureProcessor: CaptureProcessor
    private let autoZoomService: AutoZoomService
    
    // Distributors
    private let frameDistributor = FrameDistributor()
    
    init(camPreviewViewModel: CamPreviewViewModel, captureProcessor: CaptureProcessor, autoZoomService: AutoZoomService) {
        self.camPreviewViewModel = camPreviewViewModel
        self.captureProcessor = captureProcessor
        self.autoZoomService = autoZoomService
    }

    @MainActor
    func setup() async {
        logger.log(level: .default, "Setup requested")
        guard await requestForPermission() else {
            logger.log(level: .default, "Permissions denied")
            showNoPermissionHint = true
            return
        }
        
        await setupInternal()
    }
    
    @MainActor
    func startRecording() {
        guard let movieOutput = movieOutput else { return }
        if !movieOutput.isRecording {
            logger.log(level: .default, "Start Recording Requested")
            // We use a temp URL or delegate method. 
            // AVCaptureMovieFileOutput.startRecording(to: recordingDelegate:)
            // We need a file URL.
            let tempParams = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            movieOutput.startRecording(to: tempParams, recordingDelegate: captureProcessor)
        }
    }
    
    @MainActor
    func stopRecording() {
        guard let movieOutput = movieOutput else { return }
        if movieOutput.isRecording {
            logger.log(level: .default, "Stop Recording Requested")
            movieOutput.stopRecording()
        }
    }
    
    @MainActor
    func capturePhoto() async {
        guard let photoOutput = photoOutput else {
            logger.log(level: .default, "can't find photo output")
            return
        }
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: captureProcessor)
        
        self.showFlashScreen = true
        try? await Task.sleep(for: .seconds(0.2))
        self.showFlashScreen = false
    }
    
    @MainActor
    func toggleCameraPositionSwitch() async {
        logger.log(level: .default, "Toggling Camera Position")
        self.cameraPosition = self.cameraPosition == .back ? .front : .back
        await reconfigureCamera()
    }
    
    @MainActor
    func reconfigureCamera() async {
        await stopCamera()
        await setupInternal()
    }
    
    @MainActor
    func stopCamera() async {
        guard let cameraSession = self.session else {
            return
        }
        
        logger.log(level: .default, "Stopping Camera Session")
        cameraSession.stopRunning()
        self.session = nil
    }
    
    @MainActor
    private func setupInternal() async {
        if isSettingUpCamera {
            logger.log(level: .default, "isSettingUpCamera, skip")
            return
        }
        
        isSettingUpCamera = true
        
        defer {
            isSettingUpCamera = false
        }
        
        logger.log(level: .default, "start setting up camera session")
        
        guard let (cameraSession, photoOutput, movieOutput, device) = await setupCameraSession(position: cameraPosition) else {
            return
        }
        
        self.session = cameraSession
        self.photoOutput = photoOutput
        self.movieOutput = movieOutput
        self.videoDevice = device
        
        // Wire up Dependencies
        self.camPreviewViewModel.videoDevice = device
        self.autoZoomService.videoDevice = device
        
        // Wire up Distributor Outputs
        frameDistributor.onPreviewFrame = { [weak self] buffer in
            self?.camPreviewViewModel.handlePreviewFrame(buffer)
        }
        
        frameDistributor.onAnalysisFrame = { [weak self] buffer in
            self?.autoZoomService.processFrame(buffer)
        }
    }
    
    private nonisolated func setupCameraSession(position: CameraPosition) async -> (AVCaptureSession, AVCapturePhotoOutput, AVCaptureMovieFileOutput, AVCaptureDevice)? {
        let logger = Logger(subsystem: "com.vcnt.skicamera", category: "MainViewModel")
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .high // Use high for video
            
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position.avFoundationPosition
            ) else {
                logger.log(level: .default, "can't find AVCaptureDevice")
                return nil
            }
            
            session.addInput(try AVCaptureDeviceInput(device: device))
            
            let videoOutput = AVCaptureVideoDataOutput()
            // Set Delegate to FrameDistributor
            // Queue must be serial
            // We use the PreviewQueue from VM or create a new one. FrameDistributor needs a queue.
            // Let's use a new labeled queue for the distributor
            let distributorQueue = DispatchQueue(label: "frame_distributor_queue")
            videoOutput.setSampleBufferDelegate(frameDistributor, queue: distributorQueue)
            
            if session.canAddOutput(videoOutput) {
                 session.addOutput(videoOutput)
            }
            
            let photoOutput = AVCapturePhotoOutput()
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            
            if let connection = videoOutput.connection(with: .video) {
                // connection.imgRotationAngle = 90 // REMOVED to match Production behavior
                if connection.isVideoMirroringSupported && position == .front {
                    connection.isVideoMirrored = true
                }
            }
            
            // Mirroring for movie output if front camera
            if let movieConnection = movieOutput.connection(with: .video) {
                if movieConnection.isVideoMirroringSupported && position == .front {
                    movieConnection.isVideoMirrored = true
                }
                 // Ensure video orientation matches preview if possible, but usually automatic or device orientation
                 if movieConnection.isVideoOrientationSupported {
                     movieConnection.videoOrientation = .landscapeRight 
                 }
            }
            
            session.commitConfiguration()
            session.startRunning()
            
            return (session, photoOutput, movieOutput, device)
        } catch {
            print("error while setting up camera \(error)")
            return nil
        }
    }
    
    private func requestForPermission() async -> Bool {
        let photoLibraryPermissionResult = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        let cameraPermissionPermitted = await AVCaptureDevice.requestAccess(for: .video)
        return photoLibraryPermissionResult == .authorized && cameraPermissionPermitted
    }
    
    @MainActor
    private func updateAppContext() async {
#if !CAPTURE_EXTENSION
        AppUserDefaultSettings.shared.cameraPosition = self.cameraPosition
#endif
        
        if #available(iOS 18, *) {
            let appContext = AppCaptureIntent.AppContext(cameraPosition: cameraPosition)
            
            do {
                try await AppCaptureIntent.updateAppContext(appContext)
                print("app context updated")
            } catch {
                print("error on updating app context \(error)")
            }
        }
    }
    
    @MainActor
    func updateFromAppContext() async {
#if !CAPTURE_EXTENSION
        // If it's in the main app, first read the value from the UserDefaults.
        self.cameraPosition = AppUserDefaultSettings.shared.cameraPosition
#endif
        
        if #available(iOS 18, *) {
            do {
                // If `AppCaptureIntent.appContext` exists, then read from it.
                if let appContext = try await AppCaptureIntent.appContext {
                    self.cameraPosition = appContext.cameraPosition
                    print("updated from app context")
                } else {
                    print("app context is nil")
                }
            } catch {
                print("error on getting app context")
            }
        }
    }
}
