import Foundation
import CoreGraphics

class Tracker {
    struct Track {
        let id: Int
        var rect: Rect
        var missedFrames: Int
    }
    
    private var tracks: [Track] = []
    private var nextID: Int = 1
    private let maxMissedFrames: Int = 30 // 0.5s at 60fps
    private let iouThreshold: Double = 0.3
    
    func update(detections: [Rect]) -> [(Rect, Int)] {
        // 1. Predict (Skip Kalman for now, assume minimal movement between 60fps frames)
        
        // 2. Match
        var updatedTracks: [Track] = []
        var unmatchedDetections = detections
        
        // Greedy matching
        // Sort tracks by age? Or just iterate.
        // For each existing track, find best IoU match in unmatched detections
        
        // We use a simple greedy approach:
        // For each track, find highest IoU detection.
        // Identify the best global match first?
        // Let's do a simple loop:
        // Calculate all IoUs.
        
        var activeTracks = self.tracks
        var currentDetections = detections
        
        // Matches: (TrackIndex, DetectionIndex)
        var matches: [(Int, Int)] = []
        
        // Use mapping to efficiently handle used detections
        var usedDetectionIndices = Set<Int>()
        var usedTrackIndices = Set<Int>()
        
        // Sort tracks? No, order shouldn't matter too much for sparse scenes.
        
        for (tIdx, track) in activeTracks.enumerated() {
            var bestIoU = 0.0
            var bestDIdx = -1
            
            for (dIdx, det) in currentDetections.enumerated() {
                if usedDetectionIndices.contains(dIdx) { continue }
                
                let iou = calculateIoU(track.rect, det)
                if iou > bestIoU && iou > iouThreshold {
                    bestIoU = iou
                    bestDIdx = dIdx
                }
            }
            
            if bestDIdx != -1 {
                // Found a match
                // Ideally we should find the GLOBAL best match, but greedy per track is usually okay for <5 objects.
                // To be slightly safer: collect all potential matches and sort by IoU?
                // Let's stick to simple greedy for v1.
                matches.append((tIdx, bestDIdx))
                usedDetectionIndices.insert(bestDIdx)
                usedTrackIndices.insert(tIdx)
            }
        }
        
        // 3. Update Matched Tracks
        for (tIdx, dIdx) in matches {
            var track = activeTracks[tIdx]
            track.rect = currentDetections[dIdx]
            track.missedFrames = 0
            updatedTracks.append(track)
        }
        
        // 4. Handle Unmatched Tracks (Age them)
        for (tIdx, track) in activeTracks.enumerated() {
            if !usedTrackIndices.contains(tIdx) {
                var agedTrack = track
                agedTrack.missedFrames += 1
                if agedTrack.missedFrames < maxMissedFrames {
                    updatedTracks.append(agedTrack)
                }
            }
        }
        
        // 5. Handle Unmatched Detections (New Tracks)
        for (dIdx, det) in currentDetections.enumerated() {
            if !usedDetectionIndices.contains(dIdx) {
                let newTrack = Track(id: nextID, rect: det, missedFrames: 0)
                nextID += 1
                updatedTracks.append(newTrack)
            }
        }
        
        self.tracks = updatedTracks
        
        // Return active tracks that were matched or just created (not missing ones)
        // Or should we return extrapolated ones?
        // Typically output should only include CONFIRMED detections for that frame.
        // Returning aged tracks is "coasting".
        // For Zoom, coasting is good.
        
        return updatedTracks.map { ($0.rect, $0.id) }
    }
    
    private func calculateIoU(_ r1: Rect, _ r2: Rect) -> Double {
        let intersectionLeft = max(r1.left, r2.left)
        let intersectionTop = max(r1.top, r2.top)
        let intersectionRight = min(r1.right, r2.right)
        let intersectionBottom = min(r1.bottom, r2.bottom)
        
        if intersectionRight < intersectionLeft || intersectionBottom < intersectionTop {
            return 0.0
        }
        
        let intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop)
        let area1 = r1.width * r1.height
        let area2 = r2.width * r2.height
        
        let unionArea = area1 + area2 - intersectionArea
        if unionArea <= 0 { return 0.0 }
        
        return intersectionArea / unionArea
    }
    
    func reset() {
        tracks = []
        nextID = 1
    }
}
