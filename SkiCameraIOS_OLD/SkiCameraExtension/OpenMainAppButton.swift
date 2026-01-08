import SwiftUI
import LockedCameraCapture

@available(iOS 18.0, *)
struct OpenMainAppButton: View {
    let session: LockedCameraCaptureSession
    
    var body: some View {
        Button(action: {
            // Using the activity type we will define in the Info.plist
            let activity = NSUserActivity(activityType: "com.vcnt.skicamera.capture") 
            Task {
                try? await session.openApplication(for: activity)
            }
        }) {
            HStack {
                Image(systemName: "arrow.up.right.square")
                Text("Open App")
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
            .padding(10)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .padding(.top, 40) // Avoid dynamic island overlap
        }
    }
}
