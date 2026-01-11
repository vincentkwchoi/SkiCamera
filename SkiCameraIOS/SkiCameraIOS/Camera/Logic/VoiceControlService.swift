import Foundation
import Speech
import AVFoundation
import Combine
import OSLog

class VoiceControlService: ObservableObject {
    private let logger = Logger(subsystem: "com.vcnt.skicamera", category: "VoiceControlService")
    
    struct VoiceCommandEvent: Equatable {
        let command: VoiceCommand
        let id = UUID()
        
        static func == (lhs: VoiceCommandEvent, rhs: VoiceCommandEvent) -> Bool {
            return lhs.id == rhs.id
        }
    }

    enum VoiceCommand: String, CustomStringConvertible {
        case startRecording
        case stopRecording
        case zoomIn
        case zoomOut
        case stopZoom
        case autoZoom
        case photo
        case debugOn
        case debugOff
        
        var description: String {
            return self.rawValue
        }
    }
    
    @Published var lastCommand: VoiceCommandEvent? = nil
    @Published var isListening: Bool = false
    @Published var errorMessage: String? = nil
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.logger.log(level: .default, "Speech Authorized")
                case .denied:
                    self?.errorMessage = "Speech Recognition Denied"
                case .restricted:
                    self?.errorMessage = "Speech Recognition Restricted"
                case .notDetermined:
                    self?.errorMessage = "Speech Recognition Not Determined"
                @unknown default:
                    break
                }
            }
        }
    }
    
    func startListening() throws {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        // Keep running even if user pauses speaking
        recognitionRequest.requiresOnDeviceRecognition = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                // Check latest segment
                if let bestString = result.bestTranscription.segments.last?.substring {
                     self?.processCommand(bestString)
                }
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                
                DispatchQueue.main.async {
                    self?.isListening = false
                }
                
                // Auto-restart if it wasn't an explicit error?
                // For now, let's just log.
                if let err = error {
                    self?.logger.log(level: .default, "Speech Error: \(err.localizedDescription)")
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        DispatchQueue.main.async {
            self.isListening = true
        }
        logger.log(level: .default, "Started Listening")
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            isListening = false
        }
    }
    
    private func processCommand(_ text: String) {
        let lower = text.lowercased()
        logger.log(level: .default, "Heard: \(lower)")
        
        var cmd: VoiceCommand? = nil
        
        // Simple keyword matching
        if lower.contains("start") || lower.contains("record") || lower.contains("go") {
            cmd = .startRecording
        } else if lower.contains("stop zoom") || lower.contains("hold") || lower.contains("stay") || lower.contains("lock") || lower.contains("freeze") {
             cmd = .stopZoom
        } else if lower.contains("stop") || lower.contains("cut") {
            cmd = .stopRecording
        } else if lower.contains("zoom in") || lower.contains("closer") {
            cmd = .zoomIn
        } else if lower.contains("zoom out") || lower.contains("wider") {
            cmd = .zoomOut
        } else if lower.contains("auto") || lower.contains("track") {
            cmd = .autoZoom
        } else if lower.contains("photo") || lower.contains("shoot") {
            cmd = .photo
        } else if lower.contains("show overlay") {
             cmd = .debugOn
        } else if lower.contains("hide overlay") {
             cmd = .debugOff
        }
        
        if let c = cmd {
            DispatchQueue.main.async {
                self.lastCommand = VoiceCommandEvent(command: c)
                // Debounce?
                self.logger.log(level: .default, "Command Recognized: \(c)")
            }
        }
    }
}
