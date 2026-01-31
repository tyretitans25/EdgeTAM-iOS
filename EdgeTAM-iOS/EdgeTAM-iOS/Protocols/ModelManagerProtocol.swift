import Foundation
import CoreML
import CoreVideo

/// Protocol defining EdgeTAM CoreML model management and inference operations
protocol ModelManagerProtocol: AnyObject {
    /// Loads the EdgeTAM CoreML model into memory
    /// - Throws: EdgeTAMError if model loading fails
    func loadModel() async throws
    
    /// Performs inference on a video frame with given prompts
    /// - Parameters:
    ///   - pixelBuffer: The input video frame
    ///   - prompts: User interaction prompts (points/boxes)
    /// - Returns: Segmentation result with masks and metadata
    /// - Throws: EdgeTAMError if inference fails
    func performInference(on pixelBuffer: CVPixelBuffer, 
                         with prompts: [Prompt]) async throws -> SegmentationResult
    
    /// Unloads the model to free memory
    func unloadModel()
    
    /// Indicates if the model is currently loaded and ready for inference
    var isModelLoaded: Bool { get }
    
    /// The last inference time in seconds
    var inferenceTime: TimeInterval { get }
    
    /// Current memory usage of the model in bytes
    var memoryUsage: UInt64 { get }
    
    /// Model configuration settings
    var configuration: ModelConfiguration { get set }
    
    /// Delegate for model manager events
    var delegate: ModelManagerDelegate? { get set }
}

/// Delegate protocol for model manager events
protocol ModelManagerDelegate: AnyObject {
    /// Called when model loading completes successfully
    func modelManagerDidLoadModel(_ manager: ModelManagerProtocol)
    
    /// Called when model is unloaded
    func modelManagerDidUnloadModel(_ manager: ModelManagerProtocol)
    
    /// Called when inference completes
    func modelManager(_ manager: ModelManagerProtocol, didCompleteInference result: SegmentationResult)
    
    /// Called when an error occurs
    func modelManager(_ manager: ModelManagerProtocol, didFailWithError error: EdgeTAMError)
}