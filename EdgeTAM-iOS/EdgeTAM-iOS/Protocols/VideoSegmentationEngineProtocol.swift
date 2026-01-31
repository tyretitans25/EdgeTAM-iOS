import Foundation
import CoreVideo
import CoreMedia

/// Protocol defining the core video segmentation processing engine
protocol VideoSegmentationEngineProtocol: AnyObject, Sendable {
    /// Processes a single video frame with user prompts
    /// - Parameters:
    ///   - pixelBuffer: The input video frame
    ///   - prompts: User interaction prompts for object selection
    /// - Returns: Processed frame with segmentation results
    /// - Throws: EdgeTAMError if processing fails
    func processFrame(_ pixelBuffer: CVPixelBuffer, 
                     with prompts: [Prompt]) async throws -> ProcessedFrame
    
    /// Updates object tracking for the current frame
    /// - Parameter frame: The processed frame to update tracking for
    /// - Returns: Array of tracked objects with updated positions
    /// - Throws: EdgeTAMError if tracking update fails
    func updateTracking(for frame: ProcessedFrame) async throws -> [TrackedObject]
    
    /// Starts the processing pipeline
    /// - Throws: EdgeTAMError if pipeline initialization fails
    func startProcessing() async throws
    
    /// Stops the processing pipeline
    func stopProcessing()
    
    /// Resets all tracking and segmentation state
    func reset()
    
    /// Handles camera switching while maintaining processing continuity
    func handleCameraSwitch()
    
    /// Current frames per second being processed
    var currentFPS: Double { get }
    
    /// Indicates if the engine is currently processing frames
    var isProcessing: Bool { get }
    
    /// Current performance metrics
    var performanceMetrics: PerformanceMetrics { get }
    
    /// Processing configuration
    var configuration: ProcessingConfiguration { get set }
    
    /// Delegate for engine events
    var delegate: VideoSegmentationEngineDelegate? { get set }
}

/// Delegate protocol for video segmentation engine events
protocol VideoSegmentationEngineDelegate: AnyObject {
    /// Called when processing starts
    func videoSegmentationEngineDidStartProcessing(_ engine: VideoSegmentationEngineProtocol)
    
    /// Called when processing stops
    func videoSegmentationEngineDidStopProcessing(_ engine: VideoSegmentationEngineProtocol)
    
    /// Called when a frame is processed
    func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, 
                                didProcessFrame frame: ProcessedFrame)
    
    /// Called when tracking is updated
    func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, 
                                didUpdateTracking objects: [TrackedObject])
    
    /// Called when an error occurs
    func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, 
                                didFailWithError error: EdgeTAMError)
}

/// Configuration for video processing pipeline
struct ProcessingConfiguration {
    let targetFPS: Int
    let maxTrackedObjects: Int
    let confidenceThreshold: Float
    let enableTemporalConsistency: Bool
    let processingQuality: ProcessingQuality
    
    init(targetFPS: Int = 15,
         maxTrackedObjects: Int = 5,
         confidenceThreshold: Float = 0.7,
         enableTemporalConsistency: Bool = true,
         processingQuality: ProcessingQuality = .balanced) {
        self.targetFPS = targetFPS
        self.maxTrackedObjects = maxTrackedObjects
        self.confidenceThreshold = confidenceThreshold
        self.enableTemporalConsistency = enableTemporalConsistency
        self.processingQuality = processingQuality
    }
}

/// Processing quality levels for performance optimization
enum ProcessingQuality {
    case low
    case balanced
    case high
}