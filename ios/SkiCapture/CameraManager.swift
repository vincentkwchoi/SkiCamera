//
//  CameraManager.swift
//  SkiCapture
//
//  Created by Vincent Choi on 2025-12-27.
//

import AVFoundation
import Foundation
import UIKit
import Combine

class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var session = AVCaptureSession()
    
    private var movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .back)
    
    // Zoom properties
    @Published var zoomFactor: CGFloat = 1.0
    private var device: AVCaptureDevice?

    override init() {
        super.init()
        setupSession()
    }
    
    func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Setup Video Input
        if let bestDevice = discoverySession.devices.first(where: { $0.position == .back }) {
            device = bestDevice
            do {
                let input = try AVCaptureDeviceInput(device: bestDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                    videoDeviceInput = input
                }
            } catch {
                print("Failed to create video device input: \(error)")
            }
        }
        
        // Setup Audio Input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            } catch {
                print("Failed to create audio device input: \(error)")
            }
        }
        
        // Setup Movie Output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        session.commitConfiguration()
        
        Task {
            session.startRunning()
        }
    }
    
    func toggleRecording(outputURL: URL) {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            // State update happens in delegate didFinishRecording
        } else {
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }
    
    func startRecording(outputURL: URL) {
         if !movieOutput.isRecording {
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }
    
    func stopRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            // isRecording will be set to false in delegate
        }
    }
    
    // Zoom control
    func setZoom(_ factor: CGFloat) {
        guard let device = device else { return }
        do {
            try device.lockForConfiguration()
            let newFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = newFactor
            zoomFactor = newFactor
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for zoom: \(error)")
        }
    }
    
    func rampZoom(to factor: CGFloat, rate: Float) {
         guard let device = device else { return }
         do {
             try device.lockForConfiguration()
             device.ramp(toVideoZoomFactor: factor, withRate: rate)
             device.unlockForConfiguration()
         } catch {
             print("Failed to ramp zoom: \(error)")
         }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording finished with error: \(error)")
        } else {
            print("Recording finished successfully: \(outputFileURL)")
        }
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
}
