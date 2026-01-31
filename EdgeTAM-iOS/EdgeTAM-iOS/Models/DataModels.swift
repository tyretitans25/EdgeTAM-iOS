import Foundation
import CoreVideo
import CoreMedia
import CoreGraphics
import UIKit

// MARK: - Core Data Structures

/// Represents a processed video frame with segmentation results
struct ProcessedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let segmentationMasks: [SegmentationMask]
    let metadata: FrameMetadata
    let frameNumber: Int
    
    init(pixelBuffer: CVPixelBuffer,
         timestamp: CMTime,
         segmentationMasks: [SegmentationMask] = [],
         metadata: FrameMetadata,
         frameNumber: Int) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.segmentationMasks = segmentationMasks
        self.metadata = metadata
        self.frameNumber = frameNumber
    }
}

/// Represents a segmentation mask for a specific object
struct SegmentationMask: @unchecked Sendable {
    let objectId: UUID
    let maskBuffer: CVPixelBuffer
    let confidence: Float
    let boundingBox: CGRect
    let area: Float
    let centroid: CGPoint
    let timestamp: CMTime
    
    init(objectId: UUID,
         maskBuffer: CVPixelBuffer,
         confidence: Float,
         boundingBox: CGRect,
         area: Float = 0,
         centroid: CGPoint = .zero,
         timestamp: CMTime) {
        self.objectId = objectId
        self.maskBuffer = maskBuffer
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.area = area
        self.centroid = centroid
        self.timestamp = timestamp
    }
}

/// Represents a tracked object across multiple frames
struct TrackedObject: Sendable {
    let id: UUID
    let masks: [SegmentationMask] // Historical masks for temporal consistency
    let trajectory: [CGPoint]
    let confidence: Float
    let isActive: Bool
    let lastSeen: CMTime
    let createdAt: CMTime
    let objectClass: String?
    
    init(id: UUID,
         masks: [SegmentationMask] = [],
         trajectory: [CGPoint] = [],
         confidence: Float,
         isActive: Bool = true,
         lastSeen: CMTime,
         createdAt: CMTime,
         objectClass: String? = nil) {
        self.id = id
        self.masks = masks
        self.trajectory = trajectory
        self.confidence = confidence
        self.isActive = isActive
        self.lastSeen = lastSeen
        self.createdAt = createdAt
        self.objectClass = objectClass
    }
    
    /// Returns the most recent mask for this object
    var currentMask: SegmentationMask? {
        return masks.last
    }
    
    /// Returns the current position based on the latest mask
    var currentPosition: CGPoint {
        return currentMask?.centroid ?? .zero
    }
}

/// Represents a segmented object before tracking is initialized
struct SegmentedObject: Sendable {
    let id: UUID
    let mask: SegmentationMask
    let prompt: Prompt
    let initialFrame: ProcessedFrame
    
    init(id: UUID = UUID(),
         mask: SegmentationMask,
         prompt: Prompt,
         initialFrame: ProcessedFrame) {
        self.id = id
        self.mask = mask
        self.prompt = prompt
        self.initialFrame = initialFrame
    }
}

/// Metadata associated with a processed frame
struct FrameMetadata: Sendable {
    let frameNumber: Int
    let processingTime: TimeInterval
    let inferenceTime: TimeInterval
    let memoryUsage: UInt64
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float
    let deviceOrientation: UIDeviceOrientation
    
    init(frameNumber: Int,
         processingTime: TimeInterval,
         inferenceTime: TimeInterval,
         memoryUsage: UInt64,
         thermalState: ProcessInfo.ThermalState = .nominal,
         batteryLevel: Float = 1.0,
         deviceOrientation: UIDeviceOrientation = .portrait) {
        self.frameNumber = frameNumber
        self.processingTime = processingTime
        self.inferenceTime = inferenceTime
        self.memoryUsage = memoryUsage
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.deviceOrientation = deviceOrientation
    }
}

/// System performance metrics
struct PerformanceMetrics: Sendable {
    let currentFPS: Double
    let averageInferenceTime: TimeInterval
    let memoryPressure: Float
    let thermalState: ProcessInfo.ThermalState
    let cpuUsage: Float
    let gpuUsage: Float
    let batteryDrain: Float
    let timestamp: Date
    
    init(currentFPS: Double = 0,
         averageInferenceTime: TimeInterval = 0,
         memoryPressure: Float = 0,
         thermalState: ProcessInfo.ThermalState = .nominal,
         cpuUsage: Float = 0,
         gpuUsage: Float = 0,
         batteryDrain: Float = 0,
         timestamp: Date = Date()) {
        self.currentFPS = currentFPS
        self.averageInferenceTime = averageInferenceTime
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.batteryDrain = batteryDrain
        self.timestamp = timestamp
    }
}

// MARK: - Prompt Types

/// Represents different types of user interaction prompts
enum Prompt: Sendable {
    case point(PointPrompt)
    case box(BoxPrompt)
    case mask(MaskPrompt)
    
    var id: UUID {
        switch self {
        case .point(let prompt): return prompt.id
        case .box(let prompt): return prompt.id
        case .mask(let prompt): return prompt.id
        }
    }
    
    var timestamp: Date {
        switch self {
        case .point(let prompt): return prompt.timestamp
        case .box(let prompt): return prompt.timestamp
        case .mask(let prompt): return prompt.timestamp
        }
    }
}

/// Point prompt for tap-based object selection
struct PointPrompt: Sendable {
    let id: UUID
    let location: CGPoint
    let modelCoordinates: CGPoint
    let timestamp: Date
    let isPositive: Bool // true for foreground, false for background
    
    init(id: UUID = UUID(),
         location: CGPoint,
         modelCoordinates: CGPoint,
         timestamp: Date = Date(),
         isPositive: Bool = true) {
        self.id = id
        self.location = location
        self.modelCoordinates = modelCoordinates
        self.timestamp = timestamp
        self.isPositive = isPositive
    }
}

/// Box prompt for bounding box-based object selection
struct BoxPrompt: Sendable {
    let id: UUID
    let rect: CGRect
    let modelCoordinates: CGRect
    let timestamp: Date
    
    init(id: UUID = UUID(),
         rect: CGRect,
         modelCoordinates: CGRect,
         timestamp: Date = Date()) {
        self.id = id
        self.rect = rect
        self.modelCoordinates = modelCoordinates
        self.timestamp = timestamp
    }
}

/// Mask prompt using a previous segmentation as input
struct MaskPrompt: @unchecked Sendable {
    let id: UUID
    let maskBuffer: CVPixelBuffer
    let timestamp: Date
    let sourceObjectId: UUID?
    
    init(id: UUID = UUID(),
         maskBuffer: CVPixelBuffer,
         timestamp: Date = Date(),
         sourceObjectId: UUID? = nil) {
        self.id = id
        self.maskBuffer = maskBuffer
        self.timestamp = timestamp
        self.sourceObjectId = sourceObjectId
    }
}

// MARK: - Configuration Models

/// Application-wide configuration settings
struct AppConfiguration: Sendable {
    let maxTrackedObjects: Int
    let targetFPS: Int
    let maskOpacity: Float
    let confidenceThreshold: Float
    let memoryWarningThreshold: Float
    let thermalThrottlingThreshold: ProcessInfo.ThermalState
    let batteryOptimizationEnabled: Bool
    
    init(maxTrackedObjects: Int = 5,
         targetFPS: Int = 15,
         maskOpacity: Float = 0.6,
         confidenceThreshold: Float = 0.7,
         memoryWarningThreshold: Float = 0.8,
         thermalThrottlingThreshold: ProcessInfo.ThermalState = .serious,
         batteryOptimizationEnabled: Bool = true) {
        self.maxTrackedObjects = maxTrackedObjects
        self.targetFPS = targetFPS
        self.maskOpacity = maskOpacity
        self.confidenceThreshold = confidenceThreshold
        self.memoryWarningThreshold = memoryWarningThreshold
        self.thermalThrottlingThreshold = thermalThrottlingThreshold
        self.batteryOptimizationEnabled = batteryOptimizationEnabled
    }
}

/// CoreML model configuration
struct ModelConfiguration: Sendable {
    let modelName: String
    let inputSize: CGSize
    let batchSize: Int
    let useNeuralEngine: Bool
    let computeUnits: MLComputeUnits
    let memoryLimit: UInt64?
    
    init(modelName: String = "EdgeTAM",
         inputSize: CGSize = CGSize(width: 1024, height: 1024),
         batchSize: Int = 1,
         useNeuralEngine: Bool = true,
         computeUnits: MLComputeUnits = .all,
         memoryLimit: UInt64? = nil) {
        self.modelName = modelName
        self.inputSize = inputSize
        self.batchSize = batchSize
        self.useNeuralEngine = useNeuralEngine
        self.computeUnits = computeUnits
        self.memoryLimit = memoryLimit
    }
}

// MARK: - Result Types

/// Result of model inference operation
struct SegmentationResult: Sendable {
    let masks: [SegmentationMask]
    let inferenceTime: TimeInterval
    let confidence: Float
    let metadata: InferenceMetadata
    let timestamp: CMTime
    
    init(masks: [SegmentationMask],
         inferenceTime: TimeInterval,
         confidence: Float,
         metadata: InferenceMetadata,
         timestamp: CMTime) {
        self.masks = masks
        self.inferenceTime = inferenceTime
        self.confidence = confidence
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Metadata from model inference
struct InferenceMetadata: Sendable {
    let modelVersion: String
    let inputResolution: CGSize
    let outputResolution: CGSize
    let processingDevice: String
    let memoryUsed: UInt64
    let computeUnitsUsed: MLComputeUnits
    
    init(modelVersion: String = "1.0",
         inputResolution: CGSize,
         outputResolution: CGSize,
         processingDevice: String = "Neural Engine",
         memoryUsed: UInt64 = 0,
         computeUnitsUsed: MLComputeUnits = .all) {
        self.modelVersion = modelVersion
        self.inputResolution = inputResolution
        self.outputResolution = outputResolution
        self.processingDevice = processingDevice
        self.memoryUsed = memoryUsed
        self.computeUnitsUsed = computeUnitsUsed
    }
}

// MARK: - Export Types

/// Configuration for video export operations
struct ExportConfiguration: Sendable {
    let outputURL: URL
    let videoQuality: VideoQuality
    let includeOriginalAudio: Bool
    let maskOverlayMode: MaskOverlayMode
    let compressionSettings: CompressionSettings?
    
    init(outputURL: URL,
         videoQuality: VideoQuality = .high,
         includeOriginalAudio: Bool = true,
         maskOverlayMode: MaskOverlayMode = .overlay,
         compressionSettings: CompressionSettings? = nil) {
        self.outputURL = outputURL
        self.videoQuality = videoQuality
        self.includeOriginalAudio = includeOriginalAudio
        self.maskOverlayMode = maskOverlayMode
        self.compressionSettings = compressionSettings
    }
}

/// Video quality settings for export
enum VideoQuality: Sendable {
    case low
    case medium
    case high
    case original
}

/// How masks should be included in exported video
enum MaskOverlayMode: Sendable {
    case none           // Original video only
    case overlay        // Masks overlaid on original
    case masksOnly      // Only the masks
    case sideBySide     // Original and masks side by side
}

/// Video compression settings
struct CompressionSettings: Sendable {
    let codec: String
    let bitRate: Int
    let frameRate: Int
    let keyFrameInterval: Int
    
    init(codec: String = "H.264",
         bitRate: Int = 5000000,
         frameRate: Int = 30,
         keyFrameInterval: Int = 30) {
        self.codec = codec
        self.bitRate = bitRate
        self.frameRate = frameRate
        self.keyFrameInterval = keyFrameInterval
    }
}

// MARK: - Extensions

extension ProcessedFrame: Equatable {
    static func == (lhs: ProcessedFrame, rhs: ProcessedFrame) -> Bool {
        return lhs.frameNumber == rhs.frameNumber &&
               lhs.timestamp == rhs.timestamp
    }
}

extension TrackedObject: Equatable {
    static func == (lhs: TrackedObject, rhs: TrackedObject) -> Bool {
        return lhs.id == rhs.id
    }
}

extension TrackedObject: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Import for MLComputeUnits
import CoreML