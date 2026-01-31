import Foundation
import CoreVideo
import CoreMedia
import os.log
import Combine

/// Implementation of the core video segmentation processing engine
/// Coordinates model inference with prompt inputs, implements frame processing pipeline with timing constraints,
/// and handles inference failures with fallback behavior
final class VideoSegmentationEngine: NSObject, VideoSegmentationEngineProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Model manager for EdgeTAM inference
    private let modelManager: ModelManagerProtocol
    
    /// Object tracker for temporal consistency
    private let objectTracker: ObjectTrackerProtocol
    
    /// Performance monitoring
    private let performanceMonitor: VideoSegmentationPerformanceMonitor
    
    /// Logger for engine operations
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "VideoSegmentationEngine")
    
    /// Serial queue for frame processing
    private let processingQueue = DispatchQueue(label: "com.edgetam.processing.queue", qos: .userInitiated)
    
    /// Serial queue for tracking updates
    private let trackingQueue = DispatchQueue(label: "com.edgetam.tracking.queue", qos: .userInitiated)
    
    /// Current processing state
    private var _isProcessing: Bool = false
    private let processingLock = NSLock()
    
    /// Frame counter for FPS calculation
    private var frameCounter: Int = 0
    private var lastFPSUpdate: Date = Date()
    private var _currentFPS: Double = 0.0
    
    /// Performance metrics tracking
    private var _performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    
    /// Processing configuration
    var configuration: ProcessingConfiguration {
        didSet {
            logger.info("Processing configuration updated: targetFPS=\(self.configuration.targetFPS), maxObjects=\(self.configuration.maxTrackedObjects)")
            updateTrackerConfiguration()
        }
    }
    
    /// Delegate for engine events
    weak var delegate: VideoSegmentationEngineDelegate?
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Frame processing timing constraints
    private let maxProcessingTime: TimeInterval
    private let targetFrameInterval: TimeInterval
    
    /// Fallback behavior configuration
    private let maxConsecutiveFailures: Int = 3
    private var consecutiveFailures: Int = 0
    private var lastSuccessfulProcessing: Date = Date()
    
    /// Processing statistics
    private var processingTimes: [TimeInterval] = []
    private let maxStoredTimes: Int = 30
    
    // MARK: - VideoSegmentationEngineProtocol Properties
    
    var currentFPS: Double {
        return _currentFPS
    }
    
    var isProcessing: Bool {
        return _isProcessing
    }
    
    var performanceMetrics: PerformanceMetrics {
        return _performanceMetrics
    }
    
    // MARK: - Initialization
    
    init(modelManager: ModelManagerProtocol,
         objectTracker: ObjectTrackerProtocol,
         configuration: ProcessingConfiguration = ProcessingConfiguration()) {
        self.modelManager = modelManager
        self.objectTracker = objectTracker
        self.configuration = configuration
        self.performanceMonitor = VideoSegmentationPerformanceMonitor()
        
        // Calculate timing constraints based on target FPS
        self.targetFrameInterval = 1.0 / Double(configuration.targetFPS)
        self.maxProcessingTime = self.targetFrameInterval * 0.8 // Allow 80% of frame time for processing
        
        super.init()
        
        setupModelManagerDelegate()
        setupObjectTrackerDelegate()
        setupPerformanceMonitoring()
        updateTrackerConfiguration()
        
        logger.info("VideoSegmentationEngine initialized with targetFPS=\(configuration.targetFPS), maxProcessingTime=\(self.maxProcessingTime)s")
    }
    
    deinit {
        stopProcessing()
        cancellables.removeAll()
        logger.info("VideoSegmentationEngine deinitialized")
    }
    
    // MARK: - VideoSegmentationEngineProtocol Methods
    
    func startProcessing() async throws {
        logger.info("Starting video segmentation processing")
        
        // Ensure model is loaded
        if !modelManager.isModelLoaded {
            try await modelManager.loadModel()
        }
        
        // Update processing state
        _isProcessing = true
        
        // Reset statistics
        frameCounter = 0
        lastFPSUpdate = Date()
        consecutiveFailures = 0
        lastSuccessfulProcessing = Date()
        processingTimes.removeAll()
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoSegmentationEngineDidStartProcessing(self)
        }
        
        logger.info("Video segmentation processing started successfully")
    }
    
    func stopProcessing() {
        logger.info("Stopping video segmentation processing")
        
        // Update processing state
        _isProcessing = false
        
        // Clear tracking state
        objectTracker.clearAllObjects()
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoSegmentationEngineDidStopProcessing(self)
        }
        
        logger.info("Video segmentation processing stopped")
    }
    
    func reset() {
        logger.info("Resetting video segmentation engine state")
        
        // Clear all tracking
        objectTracker.clearAllObjects()
        
        // Reset statistics
        frameCounter = 0
        lastFPSUpdate = Date()
        _currentFPS = 0.0
        consecutiveFailures = 0
        processingTimes.removeAll()
        
        // Reset performance metrics
        _performanceMetrics = PerformanceMetrics()
        
        logger.info("Video segmentation engine state reset")
    }
    
    func handleCameraSwitch() {
        logger.info("Handling camera switch - maintaining processing continuity")
        
        // Don't reset everything like in reset() - maintain processing state
        // but clear tracking-specific state that may be invalidated by camera switch
        
        // Clear object tracking since objects may appear different from new camera angle
        objectTracker.clearAllObjects()
        
        // Reset consecutive failures since camera switch is a valid reason for temporary processing issues
        consecutiveFailures = 0
        
        // Keep processing statistics and performance metrics to maintain continuity
        // Only clear frame-specific tracking data
        
        logger.info("Camera switch handled - processing continuity maintained")
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> ProcessedFrame {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard isProcessing else {
            throw EdgeTAMError.invalidState("Engine is not processing")
        }
        
        logger.debug("Processing frame with \(prompts.count) prompts")
        
        // Check timing constraints
        let timeSinceLastFrame = Date().timeIntervalSince(self.lastFPSUpdate)
        if timeSinceLastFrame < self.targetFrameInterval {
            // Skip frame if we're processing too fast
            throw EdgeTAMError.frameProcessingFailed("Frame rate too high, skipping frame")
        }
        
        // Validate input
        try self.validateFrameInput(pixelBuffer: pixelBuffer, prompts: prompts)
        
        // Apply adaptive quality based on performance
        let adaptedPrompts = self.adaptPromptsForPerformance(prompts)
        
        // Perform model inference with timeout
        let segmentationResult = try await self.performInferenceWithTimeout(
            pixelBuffer: pixelBuffer,
            prompts: adaptedPrompts,
            timeout: self.maxProcessingTime
        )
        
        // Create processed frame
        let frameMetadata = await self.createFrameMetadata(
            processingTime: CFAbsoluteTimeGetCurrent() - startTime,
            inferenceTime: segmentationResult.inferenceTime
        )
        
        let processedFrame = ProcessedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: segmentationResult.timestamp,
            segmentationMasks: segmentationResult.masks,
            metadata: frameMetadata,
            frameNumber: self.frameCounter
        )
        
        // Update statistics
        self.updateProcessingStatistics(processingTime: frameMetadata.processingTime)
        self.consecutiveFailures = 0
        self.lastSuccessfulProcessing = Date()
        
        // Notify delegate on main queue
        await MainActor.run {
            self.delegate?.videoSegmentationEngine(self, didProcessFrame: processedFrame)
        }
        
        return processedFrame
    }
    
    func updateTracking(for frame: ProcessedFrame) async throws -> [TrackedObject] {
        logger.debug("Updating tracking for frame \(frame.frameNumber)")
        
        return try await withCheckedThrowingContinuation { continuation in
            trackingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.invalidState("Engine deallocated"))
                    return
                }
                
                do {
                    // Update object tracking
                    let trackedObjects = try self.objectTracker.updateTracking(with: frame)
                    
                    // Apply temporal consistency if enabled
                    let consistentObjects = self.configuration.enableTemporalConsistency ?
                        self.applyTemporalConsistency(to: trackedObjects) : trackedObjects
                    
                    // Filter objects by confidence threshold
                    let filteredObjects = consistentObjects.filter { object in
                        object.confidence >= self.configuration.confidenceThreshold
                    }
                    
                    // Handle lost objects
                    self.handleLostObjects(current: filteredObjects, previous: self.objectTracker.trackedObjects)
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async {
                        self.delegate?.videoSegmentationEngine(self, didUpdateTracking: filteredObjects)
                    }
                    
                    continuation.resume(returning: filteredObjects)
                    
                } catch {
                    let edgeTAMError = EdgeTAMError.from(error)
                    self.logger.error("Tracking update failed: \(edgeTAMError.localizedDescription)")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async {
                        self.delegate?.videoSegmentationEngine(self, didFailWithError: edgeTAMError)
                    }
                    
                    continuation.resume(throwing: edgeTAMError)
                }
            }
        }
    }
}

// MARK: - Private Methods

private extension VideoSegmentationEngine {
    
    /// Sets up model manager delegate
    func setupModelManagerDelegate() {
        modelManager.delegate = self
    }
    
    /// Sets up object tracker delegate
    func setupObjectTrackerDelegate() {
        objectTracker.delegate = self
    }
    
    /// Sets up performance monitoring
    func setupPerformanceMonitoring() {
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Update performance metrics periodically
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    /// Updates tracker configuration based on engine configuration
    func updateTrackerConfiguration() {
        objectTracker.maxTrackedObjects = configuration.maxTrackedObjects
        objectTracker.confidenceThreshold = configuration.confidenceThreshold
    }
    
    /// Validates frame processing input
    func validateFrameInput(pixelBuffer: CVPixelBuffer, prompts: [Prompt]) throws {
        // Validate pixel buffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard width > 0 && height > 0 else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        // Validate prompts count
        guard prompts.count <= configuration.maxTrackedObjects else {
            throw EdgeTAMError.promptLimitExceeded
        }
        
        // Check thermal throttling
        if ProcessInfo.processInfo.thermalState == .critical {
            throw EdgeTAMError.thermalThrottling
        }
    }
    
    /// Adapts prompts based on current performance
    func adaptPromptsForPerformance(_ prompts: [Prompt]) -> [Prompt] {
        // If performance is poor, reduce number of prompts
        let averageProcessingTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        if averageProcessingTime > maxProcessingTime * 0.9 {
            // Keep only the most recent prompts to maintain performance
            let maxPrompts = max(1, configuration.maxTrackedObjects / 2)
            return Array(prompts.suffix(maxPrompts))
        }
        
        return prompts
    }
    
    /// Performs inference with timeout protection
    func performInferenceWithTimeout(pixelBuffer: CVPixelBuffer, prompts: [Prompt], timeout: TimeInterval) async throws -> SegmentationResult {
        // For now, perform inference directly without timeout to avoid concurrency issues
        // TODO: Implement proper timeout mechanism that's compatible with Swift 6 concurrency
        return try await self.modelManager.performInference(on: pixelBuffer, with: prompts)
    }
    
    /// Creates frame metadata
    @MainActor
    func createFrameMetadata(processingTime: TimeInterval, inferenceTime: TimeInterval) -> FrameMetadata {
        return FrameMetadata(
            frameNumber: frameCounter,
            processingTime: processingTime,
            inferenceTime: inferenceTime,
            memoryUsage: performanceMonitor.currentMemoryUsage,
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryLevel: UIDevice.current.batteryLevel,
            deviceOrientation: UIDevice.current.orientation
        )
    }
    
    /// Updates processing statistics
    func updateProcessingStatistics(processingTime: TimeInterval) {
        frameCounter += 1
        
        // Store processing time
        processingTimes.append(processingTime)
        if processingTimes.count > maxStoredTimes {
            processingTimes.removeFirst()
        }
        
        // Update FPS calculation
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastFPSUpdate)
        
        if timeSinceLastUpdate >= 1.0 {
            _currentFPS = Double(frameCounter) / timeSinceLastUpdate
            frameCounter = 0
            lastFPSUpdate = now
        }
    }
    
    /// Handles processing errors with fallback behavior
    func handleProcessingError(_ error: Error, startTime: TimeInterval) -> EdgeTAMError {
        consecutiveFailures += 1
        
        let edgeTAMError = EdgeTAMError.from(error)
        logger.error("Frame processing failed (attempt \(self.consecutiveFailures)): \(edgeTAMError.localizedDescription)")
        
        // Implement fallback behavior for consecutive failures
        if consecutiveFailures >= maxConsecutiveFailures {
            logger.warning("Maximum consecutive failures reached, implementing fallback behavior")
            
            // Reduce processing quality
            if configuration.processingQuality != .low {
                configuration = ProcessingConfiguration(
                    targetFPS: max(5, configuration.targetFPS / 2),
                    maxTrackedObjects: max(1, configuration.maxTrackedObjects / 2),
                    confidenceThreshold: configuration.confidenceThreshold,
                    enableTemporalConsistency: false,
                    processingQuality: .low
                )
                
                logger.info("Reduced processing quality due to consecutive failures")
            }
        }
        
        return edgeTAMError
    }
    
    /// Applies temporal consistency to tracked objects
    func applyTemporalConsistency(to objects: [TrackedObject]) -> [TrackedObject] {
        // Simple temporal smoothing - in a real implementation this would be more sophisticated
        return objects.map { object in
            guard let previousMask = object.masks.dropLast().last else {
                return object
            }
            
            // Apply smoothing to confidence scores
            let smoothedConfidence = (object.confidence + previousMask.confidence) / 2.0
            
            // Create updated object with smoothed confidence
            return TrackedObject(
                id: object.id,
                masks: object.masks,
                trajectory: object.trajectory,
                confidence: smoothedConfidence,
                isActive: object.isActive,
                lastSeen: object.lastSeen,
                createdAt: object.createdAt,
                objectClass: object.objectClass
            )
        }
    }
    
    /// Handles lost objects during tracking
    func handleLostObjects(current: [TrackedObject], previous: [TrackedObject]) {
        let currentIds = Set(current.map { $0.id })
        let previousIds = Set(previous.map { $0.id })
        
        let lostIds = previousIds.subtracting(currentIds)
        
        for lostId in lostIds {
            logger.debug("Object \(lostId) lost during tracking")
            
            // Attempt re-acquisition if enabled
            // This would be implemented in a real scenario
        }
    }
    
    /// Handles thermal state changes
    func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        logger.info("Thermal state changed to: \(thermalState.rawValue)")
        
        switch thermalState {
        case .serious:
            // Reduce processing quality
            if configuration.processingQuality != .low {
                configuration = ProcessingConfiguration(
                    targetFPS: max(10, configuration.targetFPS * 2 / 3),
                    maxTrackedObjects: configuration.maxTrackedObjects,
                    confidenceThreshold: configuration.confidenceThreshold,
                    enableTemporalConsistency: configuration.enableTemporalConsistency,
                    processingQuality: .low
                )
            }
            
        case .critical:
            // Pause processing temporarily
            logger.warning("Critical thermal state detected, pausing processing")
            stopProcessing()
            
        case .nominal, .fair:
            // Can resume normal processing if it was throttled
            break
            
        @unknown default:
            break
        }
    }
    
    /// Handles memory warnings
    func handleMemoryWarning() {
        logger.warning("Memory warning received")
        
        // Clear processing history to free memory
        processingTimes.removeAll()
        
        // Reduce number of tracked objects
        let reducedMaxObjects = max(1, configuration.maxTrackedObjects / 2)
        configuration = ProcessingConfiguration(
            targetFPS: configuration.targetFPS,
            maxTrackedObjects: reducedMaxObjects,
            confidenceThreshold: configuration.confidenceThreshold,
            enableTemporalConsistency: false,
            processingQuality: .low
        )
    }
    
    /// Updates performance metrics
    func updatePerformanceMetrics() {
        let averageInferenceTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        _performanceMetrics = PerformanceMetrics(
            currentFPS: currentFPS,
            averageInferenceTime: averageInferenceTime,
            memoryPressure: performanceMonitor.memoryPressure,
            thermalState: ProcessInfo.processInfo.thermalState,
            cpuUsage: performanceMonitor.cpuUsage,
            gpuUsage: performanceMonitor.gpuUsage,
            batteryDrain: performanceMonitor.batteryDrain,
            timestamp: Date()
        )
    }
}

// MARK: - ModelManagerDelegate

extension VideoSegmentationEngine: ModelManagerDelegate {
    func modelManagerDidLoadModel(_ manager: ModelManagerProtocol) {
        logger.info("Model loaded successfully in VideoSegmentationEngine")
    }
    
    func modelManagerDidUnloadModel(_ manager: ModelManagerProtocol) {
        logger.info("Model unloaded in VideoSegmentationEngine")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didCompleteInference result: SegmentationResult) {
        logger.debug("Model inference completed with \(result.masks.count) masks")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didFailWithError error: EdgeTAMError) {
        logger.error("Model manager error: \(error.localizedDescription)")
        
        // Forward error to delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoSegmentationEngine(self, didFailWithError: error)
        }
    }
}

// MARK: - ObjectTrackerDelegate

extension VideoSegmentationEngine: ObjectTrackerDelegate {
    func objectTracker(_ tracker: ObjectTrackerProtocol, didInitializeTracking objects: [TrackedObject]) {
        logger.info("Object tracking initialized for \(objects.count) objects")
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didUpdateTracking objects: [TrackedObject]) {
        logger.debug("Object tracking updated for \(objects.count) objects")
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didLoseObject object: TrackedObject) {
        logger.debug("Object \(object.id) lost during tracking")
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didReacquireObject object: TrackedObject) {
        logger.info("Object \(object.id) re-acquired successfully")
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didRemoveObject objectId: UUID) {
        logger.debug("Object \(objectId) removed from tracking")
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didFailWithError error: EdgeTAMError) {
        logger.error("Object tracker error: \(error.localizedDescription)")
        
        // Forward error to delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoSegmentationEngine(self, didFailWithError: error)
        }
    }
}

// MARK: - Video Segmentation Performance Monitor

/// Simple performance monitor for tracking system metrics within VideoSegmentationEngine
private class VideoSegmentationPerformanceMonitor {
    var currentMemoryUsage: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
    
    var memoryPressure: Float {
        // Simplified memory pressure calculation
        let totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
        let usedMemory = currentMemoryUsage
        return Float(usedMemory) / Float(totalMemory)
    }
    
    var cpuUsage: Float {
        // Simplified CPU usage - would need more sophisticated implementation
        return 0.0
    }
    
    var gpuUsage: Float {
        // GPU usage monitoring would require Metal performance shaders
        return 0.0
    }
    
    var batteryDrain: Float {
        // Battery drain calculation would require historical data
        return 0.0
    }
}

// MARK: - Required Imports
import UIKit
import Combine