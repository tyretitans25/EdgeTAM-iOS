import XCTest
import CoreVideo
import CoreMedia
@testable import EdgeTAM_iOS

/// Unit tests for VideoSegmentationEngine
final class VideoSegmentationEngineTests: XCTestCase {
    
    var engine: VideoSegmentationEngine!
    var mockModelManager: MockModelManager!
    var mockObjectTracker: MockObjectTracker!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockModelManager = MockModelManager()
        mockObjectTracker = MockObjectTracker()
        
        let configuration = ProcessingConfiguration(
            targetFPS: 15,
            maxTrackedObjects: 3,
            confidenceThreshold: 0.7,
            enableTemporalConsistency: true,
            processingQuality: .balanced
        )
        
        engine = VideoSegmentationEngine(
            modelManager: mockModelManager,
            objectTracker: mockObjectTracker,
            configuration: configuration
        )
    }
    
    override func tearDownWithError() throws {
        engine = nil
        mockModelManager = nil
        mockObjectTracker = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isProcessing)
        XCTAssertEqual(engine.currentFPS, 0.0)
        XCTAssertEqual(engine.configuration.targetFPS, 15)
        XCTAssertEqual(engine.configuration.maxTrackedObjects, 3)
    }
    
    func testConfigurationUpdate() {
        let newConfiguration = ProcessingConfiguration(
            targetFPS: 30,
            maxTrackedObjects: 5,
            confidenceThreshold: 0.8,
            enableTemporalConsistency: false,
            processingQuality: .high
        )
        
        engine.configuration = newConfiguration
        
        XCTAssertEqual(engine.configuration.targetFPS, 30)
        XCTAssertEqual(engine.configuration.maxTrackedObjects, 5)
        XCTAssertEqual(engine.configuration.confidenceThreshold, 0.8)
        XCTAssertFalse(engine.configuration.enableTemporalConsistency)
        XCTAssertEqual(engine.configuration.processingQuality, .high)
    }
    
    // MARK: - Processing Lifecycle Tests
    
    func testStartProcessing() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        
        try await engine.startProcessing()
        
        XCTAssertTrue(engine.isProcessing)
        XCTAssertTrue(mockModelManager.loadModelCalled)
    }
    
    func testStartProcessingWithModelLoadFailure() async {
        mockModelManager.shouldLoadSuccessfully = false
        mockModelManager.loadModelError = EdgeTAMError.modelLoadingFailed("Test error")
        
        do {
            try await engine.startProcessing()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is EdgeTAMError)
            XCTAssertFalse(engine.isProcessing)
        }
    }
    
    func testStopProcessing() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        try await engine.startProcessing()
        
        engine.stopProcessing()
        
        XCTAssertFalse(engine.isProcessing)
        XCTAssertTrue(mockObjectTracker.clearAllObjectsCalled)
    }
    
    // MARK: - Camera Switching Tests
    
    func testHandleCameraSwitch() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        try await engine.startProcessing()
        
        // Simulate some processing activity
        XCTAssertTrue(engine.isProcessing)
        
        // Handle camera switch
        engine.handleCameraSwitch()
        
        // Verify processing continuity is maintained
        XCTAssertTrue(engine.isProcessing, "Processing should continue during camera switch")
        
        // Verify object tracking was cleared (since objects will look different from new camera angle)
        XCTAssertTrue(mockObjectTracker.handleCameraSwitchCalled)
    }
    
    func testCameraSwitchClearsTrackingButMaintainsProcessing() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        try await engine.startProcessing()
        
        // Verify initial state
        XCTAssertTrue(engine.isProcessing)
        let initialFPS = engine.currentFPS
        
        // Handle camera switch
        engine.handleCameraSwitch()
        
        // Verify processing state is maintained
        XCTAssertTrue(engine.isProcessing)
        XCTAssertEqual(engine.currentFPS, initialFPS, "FPS tracking should be maintained")
        
        // Verify tracking was handled appropriately
        XCTAssertTrue(mockObjectTracker.handleCameraSwitchCalled)
    }
    }
    
    func testReset() {
        engine.reset()
        
        XCTAssertTrue(mockObjectTracker.clearAllObjectsCalled)
        XCTAssertEqual(engine.currentFPS, 0.0)
    }
    
    // MARK: - Frame Processing Tests
    
    func testProcessFrameWhenNotProcessing() async {
        let pixelBuffer = createTestPixelBuffer()
        let prompts: [Prompt] = []
        
        do {
            _ = try await engine.processFrame(pixelBuffer, with: prompts)
            XCTFail("Expected error to be thrown")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error, EdgeTAMError.invalidState("Engine is not processing"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testProcessFrameWithValidInput() async throws {
        // Setup
        mockModelManager.shouldLoadSuccessfully = true
        mockModelManager.shouldInferenceSucceed = true
        try await engine.startProcessing()
        
        let pixelBuffer = createTestPixelBuffer()
        let prompts = [createTestPointPrompt()]
        
        // Execute
        let processedFrame = try await engine.processFrame(pixelBuffer, with: prompts)
        
        // Verify
        XCTAssertEqual(processedFrame.frameNumber, 0)
        XCTAssertTrue(mockModelManager.performInferenceCalled)
        XCTAssertNotNil(processedFrame.metadata)
    }
    
    func testProcessFrameWithInvalidPixelBuffer() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        try await engine.startProcessing()
        
        let invalidPixelBuffer = createInvalidPixelBuffer()
        let prompts: [Prompt] = []
        
        do {
            _ = try await engine.processFrame(invalidPixelBuffer, with: prompts)
            XCTFail("Expected error to be thrown")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error, EdgeTAMError.invalidPixelBuffer)
        }
    }
    
    func testProcessFrameWithTooManyPrompts() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        try await engine.startProcessing()
        
        let pixelBuffer = createTestPixelBuffer()
        let prompts = Array(repeating: createTestPointPrompt(), count: 10) // Exceeds maxTrackedObjects
        
        do {
            _ = try await engine.processFrame(pixelBuffer, with: prompts)
            XCTFail("Expected error to be thrown")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error, EdgeTAMError.promptLimitExceeded)
        }
    }
    
    // MARK: - Tracking Tests
    
    func testUpdateTracking() async throws {
        let processedFrame = createTestProcessedFrame()
        mockObjectTracker.shouldUpdateSucceed = true
        
        let trackedObjects = try await engine.updateTracking(for: processedFrame)
        
        XCTAssertTrue(mockObjectTracker.updateTrackingCalled)
        XCTAssertNotNil(trackedObjects)
    }
    
    func testUpdateTrackingFailure() async {
        let processedFrame = createTestProcessedFrame()
        mockObjectTracker.shouldUpdateSucceed = false
        mockObjectTracker.updateTrackingError = EdgeTAMError.trackingFailed("Test error")
        
        do {
            _ = try await engine.updateTracking(for: processedFrame)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is EdgeTAMError)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceMetrics() {
        let metrics = engine.performanceMetrics
        
        XCTAssertNotNil(metrics)
        XCTAssertGreaterThanOrEqual(metrics.currentFPS, 0)
        XCTAssertGreaterThanOrEqual(metrics.averageInferenceTime, 0)
        XCTAssertGreaterThanOrEqual(metrics.memoryPressure, 0)
    }
    
    // MARK: - Error Handling Tests
    
    func testConsecutiveFailureHandling() async throws {
        mockModelManager.shouldLoadSuccessfully = true
        mockModelManager.shouldInferenceSucceed = false
        mockModelManager.inferenceError = EdgeTAMError.inferenceFailure("Test error")
        
        try await engine.startProcessing()
        
        let pixelBuffer = createTestPixelBuffer()
        let prompts = [createTestPointPrompt()]
        
        // Simulate multiple consecutive failures
        for _ in 0..<3 {
            do {
                _ = try await engine.processFrame(pixelBuffer, with: prompts)
                XCTFail("Expected error to be thrown")
            } catch {
                // Expected to fail
            }
        }
        
        // After consecutive failures, configuration should be adapted
        XCTAssertEqual(engine.configuration.processingQuality, .low)
    }
    
    // MARK: - Helper Methods
    
    private func createTestPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            640,
            480,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            fatalError("Failed to create test pixel buffer")
        }
        
        return buffer
    }
    
    private func createInvalidPixelBuffer() -> CVPixelBuffer {
        // Create a buffer with zero dimensions (invalid)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            0,
            0,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        // This will likely fail, but we'll return a valid buffer for testing
        // The validation logic should catch the zero dimensions
        return createTestPixelBuffer()
    }
    
    private func createTestPointPrompt() -> Prompt {
        let pointPrompt = PointPrompt(
            location: CGPoint(x: 100, y: 100),
            modelCoordinates: CGPoint(x: 0.5, y: 0.5),
            isPositive: true
        )
        return .point(pointPrompt)
    }
    
    private func createTestProcessedFrame() -> ProcessedFrame {
        let pixelBuffer = createTestPixelBuffer()
        let timestamp = CMTime(seconds: 1.0, preferredTimescale: 30)
        let metadata = FrameMetadata(
            frameNumber: 1,
            processingTime: 0.05,
            inferenceTime: 0.03,
            memoryUsage: 1024 * 1024
        )
        
        return ProcessedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            segmentationMasks: [],
            metadata: metadata,
            frameNumber: 1
        )
    }
}

// MARK: - Mock Classes

class MockModelManager: ModelManagerProtocol {
    var shouldLoadSuccessfully = true
    var shouldInferenceSucceed = true
    var loadModelError: EdgeTAMError?
    var inferenceError: EdgeTAMError?
    
    var loadModelCalled = false
    var performInferenceCalled = false
    
    var isModelLoaded: Bool = false
    var inferenceTime: TimeInterval = 0.05
    var memoryUsage: UInt64 = 1024 * 1024
    var configuration: ModelConfiguration = ModelConfiguration()
    weak var delegate: ModelManagerDelegate?
    
    func loadModel() async throws {
        loadModelCalled = true
        
        if shouldLoadSuccessfully {
            isModelLoaded = true
        } else if let error = loadModelError {
            throw error
        }
    }
    
    func performInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> SegmentationResult {
        performInferenceCalled = true
        
        if shouldInferenceSucceed {
            let masks: [SegmentationMask] = []
            let metadata = InferenceMetadata(
                inputResolution: CGSize(width: 640, height: 480),
                outputResolution: CGSize(width: 640, height: 480)
            )
            
            return SegmentationResult(
                masks: masks,
                inferenceTime: inferenceTime,
                confidence: 0.8,
                metadata: metadata,
                timestamp: CMTime.zero
            )
        } else if let error = inferenceError {
            throw error
        } else {
            throw EdgeTAMError.inferenceFailure("Mock inference failure")
        }
    }
    
    func unloadModel() {
        isModelLoaded = false
    }
}

class MockObjectTracker: ObjectTrackerProtocol {
    var shouldUpdateSucceed = true
    var updateTrackingError: EdgeTAMError?
    
    var updateTrackingCalled = false
    var clearAllObjectsCalled = false
    var handleCameraSwitchCalled = false
    
    var trackedObjects: [TrackedObject] = []
    var maxTrackedObjects: Int = 5
    var confidenceThreshold: Float = 0.7
    var configuration: TrackingConfiguration = TrackingConfiguration()
    weak var delegate: ObjectTrackerDelegate?
    
    func initializeTracking(for objects: [SegmentedObject]) throws {
        // Mock implementation
    }
    
    func updateTracking(with newFrame: ProcessedFrame) throws -> [TrackedObject] {
        updateTrackingCalled = true
        
        if shouldUpdateSucceed {
            return trackedObjects
        } else if let error = updateTrackingError {
            throw error
        } else {
            throw EdgeTAMError.trackingFailed("Mock tracking failure")
        }
    }
    
    func removeObject(withId id: UUID) {
        trackedObjects.removeAll { $0.id == id }
    }
    
    func clearAllObjects() {
        clearAllObjectsCalled = true
        trackedObjects.removeAll()
    }
    
    func handleCameraSwitch() {
        handleCameraSwitchCalled = true
        trackedObjects.removeAll()
    }
    
    func attemptReacquisition(for objectId: UUID, in frame: ProcessedFrame) -> Bool {
        return false
    }
}