import Foundation
import CoreVideo
import CoreMedia
import CoreGraphics

/// Implementation of object tracking for temporal consistency across video frames
class ObjectTracker: ObjectTrackerProtocol {
    
    // MARK: - Properties
    
    /// Currently tracked objects
    private(set) var trackedObjects: [TrackedObject] = []
    
    /// Maximum number of objects that can be tracked simultaneously
    var maxTrackedObjects: Int = 5
    
    /// Minimum confidence threshold for maintaining tracking
    var confidenceThreshold: Float = 0.7
    
    /// Tracking configuration
    var configuration: TrackingConfiguration = TrackingConfiguration()
    
    /// Delegate for tracking events
    weak var delegate: ObjectTrackerDelegate?
    
    // MARK: - Private Properties
    
    /// Queue for thread-safe tracking operations
    private let trackingQueue = DispatchQueue(label: "com.edgetam.objecttracker", qos: .userInitiated)
    
    /// Dictionary to store lost objects for re-acquisition attempts
    private var lostObjects: [UUID: LostObjectInfo] = [:]
    
    /// Frame history for temporal analysis
    private var frameHistory: [ProcessedFrame] = []
    
    /// Motion predictor for tracking enhancement
    private let motionPredictor = MotionPredictor()
    
    /// Occlusion handler for managing temporarily hidden objects
    private let occlusionHandler = OcclusionHandler()
    
    // MARK: - Initialization
    
    init(configuration: TrackingConfiguration = TrackingConfiguration()) {
        self.configuration = configuration
    }
    
    // MARK: - ObjectTrackerProtocol Implementation
    
    func initializeTracking(for objects: [SegmentedObject]) throws {
        try trackingQueue.sync {
            guard objects.count <= maxTrackedObjects else {
                throw EdgeTAMError.trackingFailed("Cannot track more than \(maxTrackedObjects) objects simultaneously")
            }
            
            // Clear existing tracking
            trackedObjects.removeAll()
            lostObjects.removeAll()
            frameHistory.removeAll()
            
            // Initialize tracking for each object
            var initializedObjects: [TrackedObject] = []
            
            for segmentedObject in objects {
                let trackedObject = TrackedObject(
                    id: segmentedObject.id,
                    masks: [segmentedObject.mask],
                    trajectory: [segmentedObject.mask.centroid],
                    confidence: segmentedObject.mask.confidence,
                    isActive: true,
                    lastSeen: segmentedObject.mask.timestamp,
                    createdAt: segmentedObject.mask.timestamp
                )
                
                initializedObjects.append(trackedObject)
            }
            
            trackedObjects = initializedObjects
            
            // Store initial frame in history
            if let firstObject = objects.first {
                frameHistory.append(firstObject.initialFrame)
            }
            
            // Notify delegate
            delegate?.objectTracker(self, didInitializeTracking: trackedObjects)
        }
    }
    
    func updateTracking(with newFrame: ProcessedFrame) throws -> [TrackedObject] {
        return try trackingQueue.sync {
            // Add frame to history
            frameHistory.append(newFrame)
            
            // Limit frame history size
            if frameHistory.count > configuration.maxTrajectoryLength {
                frameHistory.removeFirst()
            }
            
            var updatedObjects: [TrackedObject] = []
            
            // Update tracking for each active object
            for trackedObject in trackedObjects {
                if let updatedObject = try updateSingleObject(trackedObject, with: newFrame) {
                    updatedObjects.append(updatedObject)
                } else {
                    // Object lost, move to lost objects for re-acquisition
                    handleLostObject(trackedObject, in: newFrame)
                }
            }
            
            // Attempt re-acquisition for lost objects
            if configuration.occlusionHandlingEnabled {
                let reacquiredObjects = attemptReacquisitionForLostObjects(in: newFrame)
                updatedObjects.append(contentsOf: reacquiredObjects)
            }
            
            // Update tracked objects
            trackedObjects = updatedObjects
            
            // Notify delegate
            delegate?.objectTracker(self, didUpdateTracking: trackedObjects)
            
            return trackedObjects
        }
    }
    
    func removeObject(withId id: UUID) {
        trackingQueue.sync {
            trackedObjects.removeAll { $0.id == id }
            lostObjects.removeValue(forKey: id)
            delegate?.objectTracker(self, didRemoveObject: id)
        }
    }
    
    func clearAllObjects() {
        trackingQueue.sync {
            let removedIds = trackedObjects.map { $0.id }
            trackedObjects.removeAll()
            lostObjects.removeAll()
            frameHistory.removeAll()
            
            // Notify delegate for each removed object
            for id in removedIds {
                delegate?.objectTracker(self, didRemoveObject: id)
            }
        }
    }
    
    func handleCameraSwitch() {
        trackingQueue.sync {
            // Clear all tracking state since objects will appear different from new camera angle
            let removedIds = trackedObjects.map { $0.id }
            trackedObjects.removeAll()
            lostObjects.removeAll()
            frameHistory.removeAll()
            
            // Reset motion predictor
            motionPredictor.clearAllTrajectories()
            
            // Notify delegate for each removed object
            for id in removedIds {
                delegate?.objectTracker(self, didRemoveObject: id)
            }
        }
    }
    
    func attemptReacquisition(for objectId: UUID, in frame: ProcessedFrame) -> Bool {
        return trackingQueue.sync {
            guard let lostObjectInfo = lostObjects[objectId] else {
                return false
            }
            
            // Try to find the object in the current frame
            if let reacquiredObject = performReacquisition(for: lostObjectInfo.object, in: frame) {
                // Successfully reacquired
                trackedObjects.append(reacquiredObject)
                lostObjects.removeValue(forKey: objectId)
                
                delegate?.objectTracker(self, didReacquireObject: reacquiredObject)
                return true
            }
            
            // Update attempt count
            lostObjects[objectId]?.attemptCount += 1
            
            // Remove from lost objects if max attempts reached
            if lostObjects[objectId]?.attemptCount ?? 0 >= configuration.reacquisitionAttempts {
                lostObjects.removeValue(forKey: objectId)
            }
            
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Updates tracking for a single object
    private func updateSingleObject(_ trackedObject: TrackedObject, with frame: ProcessedFrame) throws -> TrackedObject? {
        // Find the best matching mask in the new frame
        guard let bestMatch = findBestMatch(for: trackedObject, in: frame) else {
            return nil
        }
        
        // Check if confidence is above threshold
        guard bestMatch.confidence >= confidenceThreshold else {
            return nil
        }
        
        // Apply temporal smoothing if enabled
        let smoothedMask = applyTemporalSmoothing(to: bestMatch, for: trackedObject)
        
        // Update trajectory with motion prediction if enabled
        var newTrajectory = trackedObject.trajectory
        newTrajectory.append(smoothedMask.centroid)
        
        // Limit trajectory length
        if newTrajectory.count > configuration.maxTrajectoryLength {
            newTrajectory.removeFirst()
        }
        
        // Predict next position if motion prediction is enabled
        if configuration.motionPredictionEnabled {
            motionPredictor.updateTrajectory(for: trackedObject.id, with: newTrajectory)
        }
        
        // Create updated tracked object
        var updatedMasks = trackedObject.masks
        updatedMasks.append(smoothedMask)
        
        // Limit mask history
        if updatedMasks.count > configuration.maxTrajectoryLength {
            updatedMasks.removeFirst()
        }
        
        let updatedObject = TrackedObject(
            id: trackedObject.id,
            masks: updatedMasks,
            trajectory: newTrajectory,
            confidence: smoothedMask.confidence,
            isActive: true,
            lastSeen: frame.timestamp,
            createdAt: trackedObject.createdAt,
            objectClass: trackedObject.objectClass
        )
        
        return updatedObject
    }
    
    /// Finds the best matching mask for a tracked object in a new frame
    private func findBestMatch(for trackedObject: TrackedObject, in frame: ProcessedFrame) -> SegmentationMask? {
        guard let currentMask = trackedObject.currentMask else {
            return nil
        }
        
        var bestMatch: SegmentationMask?
        var bestScore: Float = 0.0
        
        // Predict expected position if motion prediction is enabled
        let predictedPosition = configuration.motionPredictionEnabled ?
            motionPredictor.predictNextPosition(for: trackedObject.id) :
            currentMask.centroid
        
        // Search for matches in the new frame
        for mask in frame.segmentationMasks {
            let score = calculateMatchingScore(
                candidateMask: mask,
                referenceMask: currentMask,
                predictedPosition: predictedPosition
            )
            
            if score > bestScore {
                bestScore = score
                bestMatch = mask
            }
        }
        
        return bestMatch
    }
    
    /// Calculates matching score between candidate and reference masks
    private func calculateMatchingScore(candidateMask: SegmentationMask, 
                                      referenceMask: SegmentationMask,
                                      predictedPosition: CGPoint) -> Float {
        // Spatial distance score
        let spatialDistance = distance(candidateMask.centroid, predictedPosition)
        let maxDistance: Float = 200.0 // Maximum expected movement between frames
        let spatialScore = max(0, 1.0 - spatialDistance / maxDistance)
        
        // Size similarity score
        let sizeRatio = min(candidateMask.area, referenceMask.area) / max(candidateMask.area, referenceMask.area)
        let sizeScore = sizeRatio
        
        // Confidence score
        let confidenceScore = candidateMask.confidence
        
        // Bounding box overlap score
        let overlapScore = calculateBoundingBoxOverlap(candidateMask.boundingBox, referenceMask.boundingBox)
        
        // Weighted combination
        let totalScore = spatialScore * 0.4 + sizeScore * 0.2 + confidenceScore * 0.2 + overlapScore * 0.2
        
        return totalScore
    }
    
    /// Calculates bounding box overlap (IoU)
    private func calculateBoundingBoxOverlap(_ rect1: CGRect, _ rect2: CGRect) -> Float {
        let intersection = rect1.intersection(rect2)
        if intersection.isNull {
            return 0.0
        }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    /// Applies temporal smoothing to reduce jitter
    private func applyTemporalSmoothing(to mask: SegmentationMask, for trackedObject: TrackedObject) -> SegmentationMask {
        guard configuration.temporalSmoothingFactor > 0,
              let previousMask = trackedObject.currentMask else {
            return mask
        }
        
        let smoothingFactor = configuration.temporalSmoothingFactor
        
        // Smooth centroid
        let smoothedCentroid = CGPoint(
            x: CGFloat(smoothingFactor) * previousMask.centroid.x + CGFloat(1 - smoothingFactor) * mask.centroid.x,
            y: CGFloat(smoothingFactor) * previousMask.centroid.y + CGFloat(1 - smoothingFactor) * mask.centroid.y
        )
        
        // Smooth bounding box
        let smoothedBoundingBox = CGRect(
            x: CGFloat(smoothingFactor) * previousMask.boundingBox.origin.x + CGFloat(1 - smoothingFactor) * mask.boundingBox.origin.x,
            y: CGFloat(smoothingFactor) * previousMask.boundingBox.origin.y + CGFloat(1 - smoothingFactor) * mask.boundingBox.origin.y,
            width: CGFloat(smoothingFactor) * previousMask.boundingBox.width + CGFloat(1 - smoothingFactor) * mask.boundingBox.width,
            height: CGFloat(smoothingFactor) * previousMask.boundingBox.height + CGFloat(1 - smoothingFactor) * mask.boundingBox.height
        )
        
        // Smooth area
        let smoothedArea = smoothingFactor * previousMask.area + (1 - smoothingFactor) * mask.area
        
        return SegmentationMask(
            objectId: mask.objectId,
            maskBuffer: mask.maskBuffer, // Keep original mask buffer
            confidence: mask.confidence,
            boundingBox: smoothedBoundingBox,
            area: smoothedArea,
            centroid: smoothedCentroid,
            timestamp: mask.timestamp
        )
    }
    
    /// Handles a lost object by moving it to the lost objects collection
    private func handleLostObject(_ trackedObject: TrackedObject, in frame: ProcessedFrame) {
        let lostObjectInfo = LostObjectInfo(
            object: trackedObject,
            lostAt: frame.timestamp,
            attemptCount: 0
        )
        
        lostObjects[trackedObject.id] = lostObjectInfo
        delegate?.objectTracker(self, didLoseObject: trackedObject)
    }
    
    /// Attempts re-acquisition for all lost objects
    private func attemptReacquisitionForLostObjects(in frame: ProcessedFrame) -> [TrackedObject] {
        var reacquiredObjects: [TrackedObject] = []
        var objectsToRemove: [UUID] = []
        
        for (objectId, lostObjectInfo) in lostObjects {
            if let reacquiredObject = performReacquisition(for: lostObjectInfo.object, in: frame) {
                reacquiredObjects.append(reacquiredObject)
                objectsToRemove.append(objectId)
                delegate?.objectTracker(self, didReacquireObject: reacquiredObject)
            } else {
                // Increment attempt count
                lostObjects[objectId]?.attemptCount += 1
                
                // Remove if max attempts reached
                if lostObjectInfo.attemptCount >= configuration.reacquisitionAttempts {
                    objectsToRemove.append(objectId)
                }
            }
        }
        
        // Remove processed objects
        for objectId in objectsToRemove {
            lostObjects.removeValue(forKey: objectId)
        }
        
        return reacquiredObjects
    }
    
    /// Performs re-acquisition for a specific lost object
    private func performReacquisition(for lostObject: TrackedObject, in frame: ProcessedFrame) -> TrackedObject? {
        // Use more relaxed matching criteria for re-acquisition
        let relaxedConfidenceThreshold = confidenceThreshold * 0.8
        
        guard let lastMask = lostObject.currentMask else {
            return nil
        }
        
        // Predict where the object might be based on its trajectory
        let predictedPosition = motionPredictor.predictNextPosition(for: lostObject.id)
        
        var bestMatch: SegmentationMask?
        var bestScore: Float = 0.0
        
        for mask in frame.segmentationMasks {
            // Skip if confidence is too low
            guard mask.confidence >= relaxedConfidenceThreshold else {
                continue
            }
            
            let score = calculateMatchingScore(
                candidateMask: mask,
                referenceMask: lastMask,
                predictedPosition: predictedPosition
            )
            
            if score > bestScore {
                bestScore = score
                bestMatch = mask
            }
        }
        
        guard let match = bestMatch, bestScore > 0.5 else {
            return nil
        }
        
        // Create reacquired object
        var updatedMasks = lostObject.masks
        updatedMasks.append(match)
        
        var updatedTrajectory = lostObject.trajectory
        updatedTrajectory.append(match.centroid)
        
        return TrackedObject(
            id: lostObject.id,
            masks: updatedMasks,
            trajectory: updatedTrajectory,
            confidence: match.confidence,
            isActive: true,
            lastSeen: frame.timestamp,
            createdAt: lostObject.createdAt,
            objectClass: lostObject.objectClass
        )
    }
    
    /// Calculates Euclidean distance between two points
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> Float {
        let dx = Float(point1.x - point2.x)
        let dy = Float(point1.y - point2.y)
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Supporting Classes

/// Information about a lost object for re-acquisition attempts
private struct LostObjectInfo {
    let object: TrackedObject
    let lostAt: CMTime
    var attemptCount: Int
}

/// Motion predictor for enhanced tracking
private class MotionPredictor {
    private var trajectories: [UUID: [CGPoint]] = [:]
    
    func updateTrajectory(for objectId: UUID, with trajectory: [CGPoint]) {
        trajectories[objectId] = trajectory
    }
    
    func predictNextPosition(for objectId: UUID) -> CGPoint {
        guard let trajectory = trajectories[objectId],
              trajectory.count >= 2 else {
            return trajectories[objectId]?.last ?? .zero
        }
        
        // Simple linear prediction based on last two points
        let lastPoint = trajectory[trajectory.count - 1]
        let secondLastPoint = trajectory[trajectory.count - 2]
        
        let velocity = CGPoint(
            x: lastPoint.x - secondLastPoint.x,
            y: lastPoint.y - secondLastPoint.y
        )
        
        return CGPoint(
            x: lastPoint.x + velocity.x,
            y: lastPoint.y + velocity.y
        )
    }
    
    func clearAllTrajectories() {
        trajectories.removeAll()
    }
}

/// Occlusion handler for managing temporarily hidden objects
private class OcclusionHandler {
    // Placeholder for future occlusion handling logic
    // Could include depth analysis, object relationship tracking, etc.
}