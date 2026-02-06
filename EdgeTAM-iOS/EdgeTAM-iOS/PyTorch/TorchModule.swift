import Foundation
import CoreVideo
import CoreGraphics
import CoreMedia

/// Swift wrapper for PyTorch Mobile TorchModule
/// Provides a clean Swift interface to the Objective-C++ PyTorch bridge
final class PyTorchModule: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The underlying Objective-C++ module
    private let module: TorchModule
    
    /// Path to the model file
    let modelPath: String
    
    /// Whether the model is currently loaded
    var isLoaded: Bool {
        return module.isLoaded
    }
    
    /// Current memory usage in bytes
    var memoryUsage: UInt64 {
        return UInt64(module.memoryUsage)
    }
    
    // MARK: - Initialization
    
    /// Initialize with model file path
    /// - Parameter modelPath: Path to the TorchScript model file (.pt)
    init?(modelPath: String) {
        self.modelPath = modelPath
        guard let module = TorchModule(modelPath: modelPath) else {
            return nil
        }
        self.module = module
    }
    
    // MARK: - Model Management
    
    /// Load the model from file
    /// - Throws: EdgeTAMError if loading fails
    func loadModel() throws {
        do {
            try module.loadModel()
        } catch {
            throw EdgeTAMError.modelLoadingFailed(error.localizedDescription)
        }
    }
    
    /// Unload the model from memory
    func unloadModel() {
        module.unloadModel()
    }
    
    // MARK: - Inference
    
    /// Perform inference on an image with point prompts
    /// - Parameters:
    ///   - pixelBuffer: Input image as CVPixelBuffer (RGB, 1024x1024)
    ///   - points: Array of point prompts with coordinates and labels
    /// - Returns: Segmentation result with mask and confidence
    /// - Throws: EdgeTAMError if inference fails
    func predict(pixelBuffer: CVPixelBuffer, points: [PointPrompt]) throws -> PyTorchInferenceResult {
        guard isLoaded else {
            throw EdgeTAMError.invalidState("Model not loaded")
        }
        
        guard !points.isEmpty else {
            throw EdgeTAMError.invalidPrompt("At least one point prompt is required")
        }
        
        // Convert points to arrays - use autoreleasepool for memory safety
        let coordinates: [NSValue] = autoreleasepool {
            points.map { point in
                let cgPoint = point.modelCoordinates
                print("[TorchModule] Converting point: (\(cgPoint.x), \(cgPoint.y))")
                return NSValue(cgPoint: cgPoint)
            }
        }
        
        let labels: [NSNumber] = autoreleasepool {
            points.map { NSNumber(value: $0.isPositive ? 1.0 : 0.0) }
        }
        
        print("[TorchModule] Calling predict with \(coordinates.count) coordinates")
        
        // Perform inference
        do {
            let result = try module.predict(
                with: pixelBuffer,
                pointCoordinates: coordinates,
                pointLabels: labels
            )
            
            // Ensure we have a valid mask buffer
            guard let maskBuffer = result.maskBuffer else {
                throw EdgeTAMError.inferenceFailure("No mask buffer returned from inference")
            }
            
            // Convert to Swift result
            // Swift's ARC will automatically manage the CVPixelBuffer lifecycle
            return PyTorchInferenceResult(
                maskBuffer: maskBuffer,
                confidence: result.confidence,
                inferenceTime: result.inferenceTime
            )
        } catch {
            print("[TorchModule] Inference failed: \(error.localizedDescription)")
            throw EdgeTAMError.inferenceFailure(error.localizedDescription)
        }
    }
}

// MARK: - PyTorchInferenceResult

/// Result of PyTorch model inference
struct PyTorchInferenceResult {
    /// Segmentation mask as pixel buffer (grayscale, 0-255)
    let maskBuffer: CVPixelBuffer
    
    /// Confidence score (0.0 - 1.0)
    let confidence: Float
    
    /// Inference time in seconds
    let inferenceTime: TimeInterval
    
    /// Convert to SegmentationResult for compatibility with existing code
    func toSegmentationResult(objectId: UUID = UUID(), timestamp: CMTime = .zero) -> SegmentationResult {
        // Calculate bounding box from mask
        let boundingBox = calculateBoundingBox(from: maskBuffer)
        
        // Create segmentation mask
        let mask = SegmentationMask(
            objectId: objectId,
            maskBuffer: maskBuffer,
            confidence: confidence,
            boundingBox: boundingBox,
            area: Float(boundingBox.width * boundingBox.height),
            centroid: CGPoint(x: boundingBox.midX, y: boundingBox.midY),
            timestamp: timestamp
        )
        
        // Create metadata
        let metadata = InferenceMetadata(
            modelVersion: "EdgeTAM-PyTorch-1.0",
            inputResolution: CGSize(width: 1024, height: 1024),
            outputResolution: CGSize(
                width: CVPixelBufferGetWidth(maskBuffer),
                height: CVPixelBufferGetHeight(maskBuffer)
            ),
            processingDevice: "PyTorch Mobile (GPU)",
            memoryUsed: 0, // Will be updated by caller
            computeUnitsUsed: .all
        )
        
        return SegmentationResult(
            masks: [mask],
            inferenceTime: inferenceTime,
            confidence: confidence,
            metadata: metadata,
            timestamp: timestamp
        )
    }
    
    /// Calculate bounding box from mask pixel buffer
    private func calculateBoundingBox(from maskBuffer: CVPixelBuffer) -> CGRect {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        
        let threshold: UInt8 = 128 // 50% threshold
        
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                if row[x] > threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // Normalize to [0, 1]
        let normalizedMinX = CGFloat(minX) / CGFloat(width)
        let normalizedMinY = CGFloat(minY) / CGFloat(height)
        let normalizedMaxX = CGFloat(maxX) / CGFloat(width)
        let normalizedMaxY = CGFloat(maxY) / CGFloat(height)
        
        return CGRect(
            x: normalizedMinX,
            y: normalizedMinY,
            width: normalizedMaxX - normalizedMinX,
            height: normalizedMaxY - normalizedMinY
        )
    }
}
