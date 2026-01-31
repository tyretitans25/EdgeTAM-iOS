import Foundation
import CoreGraphics
import CoreVideo

/// Protocol defining object tracking operations across video frames
protocol ObjectTrackerProtocol: AnyObject, Sendable {
    /// Initializes tracking for a set of segmented objects
    /// - Parameter objects: Initial segmented objects to track
    /// - Throws: EdgeTAMError if tracking initialization fails
    func initializeTracking(for objects: [SegmentedObject]) throws
    
    /// Updates tracking with a new processed frame
    /// - Parameter newFrame: The latest processed frame
    /// - Returns: Array of updated tracked objects
    /// - Throws: EdgeTAMError if tracking update fails
    func updateTracking(with newFrame: ProcessedFrame) throws -> [TrackedObject]
    
    /// Removes a specific object from tracking
    /// - Parameter id: Unique identifier of the object to remove
    func removeObject(withId id: UUID)
    
    /// Removes all objects from tracking
    func clearAllObjects()
    
    /// Handles camera switching by clearing tracking state appropriately
    func handleCameraSwitch()
    
    /// Attempts to re-acquire a lost object
    /// - Parameters:
    ///   - objectId: ID of the object to re-acquire
    ///   - frame: Current frame to search in
    /// - Returns: True if re-acquisition was successful
    func attemptReacquisition(for objectId: UUID, in frame: ProcessedFrame) -> Bool
    
    /// Currently tracked objects
    var trackedObjects: [TrackedObject] { get }
    
    /// Maximum number of objects that can be tracked simultaneously
    var maxTrackedObjects: Int { get set }
    
    /// Minimum confidence threshold for maintaining tracking
    var confidenceThreshold: Float { get set }
    
    /// Tracking configuration
    var configuration: TrackingConfiguration { get set }
    
    /// Delegate for tracking events
    var delegate: ObjectTrackerDelegate? { get set }
}

/// Delegate protocol for object tracker events
protocol ObjectTrackerDelegate: AnyObject {
    /// Called when tracking is initialized for new objects
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didInitializeTracking objects: [TrackedObject])
    
    /// Called when tracking is updated
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didUpdateTracking objects: [TrackedObject])
    
    /// Called when an object is lost (confidence below threshold)
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didLoseObject object: TrackedObject)
    
    /// Called when an object is successfully re-acquired
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didReacquireObject object: TrackedObject)
    
    /// Called when an object is removed from tracking
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didRemoveObject objectId: UUID)
    
    /// Called when an error occurs
    func objectTracker(_ tracker: ObjectTrackerProtocol, 
                      didFailWithError error: EdgeTAMError)
}

/// Configuration for object tracking behavior
struct TrackingConfiguration {
    let maxTrajectoryLength: Int
    let reacquisitionAttempts: Int
    let temporalSmoothingFactor: Float
    let motionPredictionEnabled: Bool
    let occlusionHandlingEnabled: Bool
    
    init(maxTrajectoryLength: Int = 30,
         reacquisitionAttempts: Int = 5,
         temporalSmoothingFactor: Float = 0.8,
         motionPredictionEnabled: Bool = true,
         occlusionHandlingEnabled: Bool = true) {
        self.maxTrajectoryLength = maxTrajectoryLength
        self.reacquisitionAttempts = reacquisitionAttempts
        self.temporalSmoothingFactor = temporalSmoothingFactor
        self.motionPredictionEnabled = motionPredictionEnabled
        self.occlusionHandlingEnabled = occlusionHandlingEnabled
    }
}