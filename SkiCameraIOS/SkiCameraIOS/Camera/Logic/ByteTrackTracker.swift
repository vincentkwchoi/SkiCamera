import Foundation
import CoreGraphics

// The ByteTrack Algorithm in Swift
class ByteTrack {
    struct Track {
        let id: Int
        var rect: Rect
        var state: TrackState
        var missedFrames: Int
        let kf: KalmanFilter
        
        // ByteTrack Specifics
        var isActivated: Bool = false
        var score: Float = 0.0
    }
    
    enum TrackState {
        case new
        case tracked
        case lost
        case removed
    }
    
    // Config
    private let highThresh: Float = 0.5
    private let matchThresh: Double = 0.8 // 1 - IoU (So < 0.8 means IoU > 0.2)
    // Wait, typical IoU threshold is "Min IoU". Let's stick to "Min IoU > 0.2" logic.
    private let minIoU: Double = 0.2
    private let maxMissedFrames: Int = 30
    
    private var tracks: [Track] = []
    private var lostTracks: [Track] = [] // Tracks that are lost but not removed
    private var nextID: Int = 1
    
    func update(detections: [Rect]) -> [(Rect, Int)] {
        // 1. Prediction: Predict next state for all tracks
        // Combine active and lost tracks for prediction (we try to recover lost ones too)
        
        // Simplify: Just keep everything in `tracks` or separate `active` and `lost`.
        // ByteTrack reference keeps `tracked_stracks`, `lost_stracks`, `removed_stracks`.
        // We will keep a unified list for simplicity but filter by state.
        
        var combinedTracks: [Int: Track] = [:] // Map ID -> Track for easier updates
        var jointTracks = tracks + lostTracks
        
        for i in 0..<jointTracks.count {
            _ = jointTracks[i].kf.predict()
            // Update the track's rect to the predicted position for matching
            jointTracks[i].rect = jointTracks[i].kf.currentStateRect()
            combinedTracks[jointTracks[i].id] = jointTracks[i]
        }
        
        // 2. Detection Split
        let highConfDets = detections.filter { $0.confidence >= highThresh }
        let lowConfDets = detections.filter { $0.confidence < highThresh && $0.confidence > 0.1 }
        
        // 3. First Association: High Conf Dets to Active Tracks
        // "Active" tracks are those that were TRACKED or LOST (but we try to match LOST in 2nd stage usually? 
        // No, in ByteTrack: 
        // 1. High Conf -> Match against (Tracked + Lost? No, usually Tracked + (Lost w/ prediction)).
        // ByteTrack paper: Match High Dets with ALL Tracks first? No.
        // Standard ByteTrack:
        //    Pool = Tracked Tracks + Lost Tracks
        //    Match High Dets -> Pool
        //    Remaining Tracks -> (Tracked - Matched) + (Lost - Matched) => These go to Stage 2?
        //    Actually: 
        //      Dets_high match Tracked_objects (and Lost objects? Reference implementation uses both).
        
        var u_track = [Track]() // Unmatched tracks from stage 1
        var u_detection = [Rect]() // Unmatched detections from stage 1
        
        // Separate tracks by state
        let tracked_tracks = tracks // Previous 'tracked'
        let lost_tracks = lostTracks // Previous 'lost'
        
        // Pool for First Match: Tracked + Lost (Attempt to re-find/continue)
        var pool = tracked_tracks + lost_tracks
        
        // Match High Conf
        let (matches1, unmatched_tracks1, unmatched_dets1) = match(tracks: pool, detections: highConfDets, threshold: minIoU)
        
        // Update Matched Tracks
        for (tIdx, dIdx) in matches1 {
            let det = highConfDets[dIdx]
            let trackObj = pool[tIdx]
            
            // Re-fetch mutable track from map or list? Ideally work with IDs.
            if var track = combinedTracks[trackObj.id] {
                track.kf.update(measurement: det)
                track.rect = det // Update to measurement
                track.state = .tracked
                track.isActivated = true
                track.missedFrames = 0
                track.score = det.confidence
                combinedTracks[track.id] = track
            }
        }
        
        u_detection = unmatched_dets1.map { highConfDets[$0] }
        
        // 4. Second Association: Low Conf Dets to Remaining Tracks
        // Only match against "Tracked" tracks that were unmatched in Stage 1?
        // ByteTrack logic: Match Low Dets against (Tracked Tracks that were unmatched in Stage 1).
        // Lost tracks that were unmatched in Stage 1 are usually left alone (don't risk matching noise to lost track).
        
        // So, candidate tracks for Stage 2 are:
        // `unmatched_tracks1` ONLY if they were previously `.tracked`.
        
        let candidates2 = unmatched_tracks1.compactMap { idx -> Track? in
            let t = pool[idx]
            return t.state == .tracked ? t : nil
        }
        
        let (matches2, unmatched_tracks2, unmatched_dets2) = match(tracks: candidates2, detections: lowConfDets, threshold: 0.5) // Higher IoU required for low conf? Or 0.5 reasonable.
        
        // Update Matched Low Conf
        for (tIdx, dIdx) in matches2 {
            let det = lowConfDets[dIdx]
            // tIdx is index into `candidates2`
            let trackObj = candidates2[tIdx]
            
            if var track = combinedTracks[trackObj.id] {
                track.kf.update(measurement: det)
                track.rect = det
                track.state = .tracked
                track.isActivated = true
                track.missedFrames = 0
                track.score = det.confidence
                combinedTracks[track.id] = track
            }
        }
        
        // 5. Unmatched Tracks handling
        // Tracks from Stage 1 (Lost) that weren't matched -> Remain Lost / Increment Age
        // Tracks from Stage 2 (Tracked) that weren't matched -> Become Lost / Increment Age
        
        // Process `unmatched_tracks1` (that were .lost)
        for idx in unmatched_tracks1 {
            let t = pool[idx]
            if t.state == .lost {
                markLost(track: t, map: &combinedTracks)
            }
        }
        
        // Process `unmatched_tracks2` (that were .tracked)
        for idx in unmatched_tracks2 {
             let t = candidates2[idx]
             markLost(track: t, map: &combinedTracks)
        }
        
        // 6. New Tracks Initialization
        // Use `u_detection` (Unmatched High Conf Dets)
        for det in u_detection {
            // New Track
            if det.confidence >= highThresh {
                let newTrack = Track(
                    id: nextID,
                    rect: det,
                    state: .tracked, // Start as tracked if high conf? Or .new?
                    // Original ByteTrack uses .isActivated logic (needs 2 frames to confirm).
                    // For Ski Camera, fast acquisition is better. Let's trust High Conf immediately.
                    missedFrames: 0,
                    kf: KalmanFilter(initialRect: det),
                    isActivated: true,
                    score: det.confidence
                )
                nextID += 1
                combinedTracks[newTrack.id] = newTrack
            }
        }
        
        // 7. Cleanup & Output
        self.tracks = []
        self.lostTracks = []
        
        var outputs: [(Rect, Int)] = []
        
        for (_, track) in combinedTracks {
            if track.state == .removed { continue }
            
            if track.state == .tracked {
                self.tracks.append(track)
                outputs.append((track.rect, track.id))
            } else if track.state == .lost {
                self.lostTracks.append(track)
                // Do NOT output lost tracks
            }
        }
        
        return outputs
    }
    
    private func markLost(track: Track, map: inout [Int: Track]) {
        if var t = map[track.id] {
            t.state = .lost
            t.missedFrames += 1
            if t.missedFrames > maxMissedFrames {
                t.state = .removed
            }
            map[track.id] = t
        }
    }
    
    // Returns (Matches=[(TrackIdx, DetIdx)], UnmatchedTracks=[TrackIdx], UnmatchedDets=[DetIdx])
    private func match(tracks: [Track], detections: [Rect], threshold: Double) -> ([(Int, Int)], [Int], [Int]) {
        // Compute IoU Matrix
        var matches: [(Int, Int)] = []
        var usedTracks = Set<Int>()
        var usedDets = Set<Int>()
        
        // Simple Greedy Matching (Sufficient for sparse scenes)
        // For dense scenes, Hungarian (Munkres) is better but requires O(n^3).
        // Given N < 10 skiers, Greedy is fine.
        
        // Calculate all costs
        var costs: [(Double, Int, Int)] = [] // (IoU, TrackIdx, DetIdx)
        
        for (tIdx, track) in tracks.enumerated() {
            for (dIdx, det) in detections.enumerated() {
                let iou = calculateIoU(track.rect, det)
                if iou >= threshold {
                    costs.append((iou, tIdx, dIdx))
                }
            }
        }
        
        // Sort by IoU descending (Best match first)
        costs.sort { $0.0 > $1.0 }
        
        for (_, tIdx, dIdx) in costs {
            if !usedTracks.contains(tIdx) && !usedDets.contains(dIdx) {
                matches.append((tIdx, dIdx))
                usedTracks.insert(tIdx)
                usedDets.insert(dIdx)
            }
        }
        
        // Find Unmatched
        let uTracks = (0..<tracks.count).filter { !usedTracks.contains($0) }
        let uDets = (0..<detections.count).filter { !usedDets.contains($0) }
        
        return (matches, uTracks, uDets)
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
        lostTracks = []
        nextID = 1
    }
}
