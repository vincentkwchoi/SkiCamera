import Foundation
import CoreGraphics

class SkierSelection {
    // Logic:
    // 1. If we have a locked ID, look for it in current tracks.
    // 2. If found, return it.
    // 3. If NOT found (lost), fall back to finding the "best" candidate (closest to center) to re-acquire (or start fresh).
    
    private var lockedTrackID: Int?
    private let tracker = Tracker()
    
    // For "closest to center" fallback
    private var lastKnownCenter: CGPoint?
    
    func selectTarget(from rawDetections: [Rect]) -> Rect? {
        // 1. Run Tracker
        let tracks = tracker.update(detections: rawDetections)
        
        if tracks.isEmpty {
            // No objects at all
            // Do NOT clear lockedTrackID immediately? 
            // The tracker keeps "missing" tracks for 30 frames. 
            // If the tracker returns nothing, it means even coasting failed.
            // But tracker.update returns ALL tracks including missing ones (in my implementation).
            // Let's check Tracker implementation.
            // My implementation returns updatedTracks.
            return nil
        }
        
        var selectedTrack: (Rect, Int)? = nil
        
        // 2. Try to find Locked ID
        if let targetID = lockedTrackID {
            if let match = tracks.first(where: { $0.1 == targetID }) {
                selectedTrack = match
            }
        }
        
        // 3. Fallback: Find closest to center
        if selectedTrack == nil {
            // We lost the lock, or never had one.
            // Pick the best candidate based on distance to Center (0.5, 0.5)
            // Note: The Python code uses simple screen center distance.
            
            let centerPoint = CGPoint(x: 0.5, y: 0.5)
            
            // Filter tracks? Python code filters based on class/conf, but we already have valid tracks.
            // Logic: Find track closest to center.
            
            let bestMatch = tracks.min(by: { t1, t2 in
                let dist1 = distanceSquared(from: t1.0.center, to: centerPoint)
                let dist2 = distanceSquared(from: t2.0.center, to: centerPoint)
                return dist1 < dist2
            })
            
            if let best = bestMatch {
                selectedTrack = best
                lockedTrackID = best.1 // Lock onto this new target
            }
        }
        
        if let selected = selectedTrack {
            // Update last known state (optional, used for pan smoothing)
            lastKnownCenter = selected.0.center
            return selected.0
        }
        
        return nil
    }
    
    private func distanceSquared(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        return pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2)
    }
    
    func reset() {
        lockedTrackID = nil
        lastKnownCenter = nil
        tracker.reset()
    }
}
