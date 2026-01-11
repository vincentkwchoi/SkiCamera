import Foundation
import SwiftUI
import Combine

class UserCueManager: ObservableObject {
    @Published var currentMessage: String = ""
    @Published var isVisible: Bool = false
    
    private var dismissTimer: Timer?
    
    enum CueType {
        case launch
        case recordingStarted
        case recordingStopped
        case custom(String)
    }
    
    func show(_ type: CueType) {
        // Cancel existing timer
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        // precise mapping from USER_CONTROLS_AND_CUES.md
        switch type {
        case .launch:
            currentMessage = "Start recording with Auto-Zoom in"
            isVisible = true
            scheduleDismiss(delay: 5.0)
            
        case .recordingStarted:
            currentMessage = "Recording"
            isVisible = true
            scheduleDismiss(delay: 2.0)
            
        case .recordingStopped:
            currentMessage = "Recording Saved"
            isVisible = true
            scheduleDismiss(delay: 2.0)
            
        case .custom(let msg):
            currentMessage = msg
            isVisible = true
            scheduleDismiss(delay: 2.0)
        }
    }
    
    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        isVisible = false
    }
    
    private func scheduleDismiss(delay: TimeInterval) {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            withAnimation {
                self?.isVisible = false
            }
        }
    }
}

struct UserCueView: View {
    @ObservedObject var manager: UserCueManager
    
    var body: some View {
        ZStack {
            if manager.isVisible {
                Text(manager.currentMessage)
                    .font(.system(size: 32, weight: .bold, design: .rounded)) // Slightly smaller for longer text
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2, x: 0, y: 0)
                    .shadow(color: .black, radius: 2, x: 0, y: 0)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                    .transition(.opacity)
                    .padding(.top, 100)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}
