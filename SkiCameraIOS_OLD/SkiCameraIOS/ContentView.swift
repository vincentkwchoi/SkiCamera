import SwiftUI
import AVFoundation
import MediaPlayer

struct ContentView: View {
    @StateObject var camera = CameraManager()
    
    // Volume Listener
    @State private var volumeObserver: NSKeyValueObservation?
    @State private var audioSession = AVAudioSession.sharedInstance()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. Camera Preview
            CameraPreview(session: camera.session)
                .edgesIgnoringSafeArea(.all)
            
            // 2. Bounding Box Overlay
             GeometryReader { geo in
                 if let rect = camera.detectedRect {
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
            
            // 3. UI Overlay
            VStack {
                // Top Status
                VStack(alignment: .leading) {
                    Text(camera.debugLabel)
                        .foregroundColor(.green)
                    Text("H: \(String(format: "%.2f", camera.skierHeight)) / 0.15")
                        .foregroundColor(.white)
                    Text("Zoom: \(String(format: "%.2f", camera.currentZoom))x")
                        .foregroundColor(.yellow)
                    Text("Mode: \(camera.isManualZoomMode ? "MANUAL" : "AUTO")")
                        .foregroundColor(camera.isManualZoomMode ? .orange : .cyan)
                    Text(camera.buttonStatus)
                        .foregroundColor(.cyan)
                }
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 40)
                
                Spacer()
                
                // Record Button
                Button(action: {
                    if camera.isRecording {
                        camera.stopRecording()
                    } else {
                        camera.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .fill(camera.isRecording ? Color.red : Color.white)
                            .frame(width: camera.isRecording ? 40 : 70, height: camera.isRecording ? 40 : 70)
                            .animation(.spring(), value: camera.isRecording)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onPressCapture {
            // Primary action (Volume Down)
            camera.buttonStatus = "Volume DOWN pressed"
            camera.zoomOut()
        } secondaryAction: {
            // Secondary action (Volume Up)
            camera.buttonStatus = "Volume UP pressed"
            camera.zoomIn()
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    // Session started in CameraManager init
                }
            }
        default:
            print("Camera permission denied")
        }
    }
}
