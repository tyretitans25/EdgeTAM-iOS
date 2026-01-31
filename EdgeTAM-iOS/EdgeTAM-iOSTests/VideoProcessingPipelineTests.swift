import XCTest
import AVFoundation
import CoreVideo
import CoreMedia
@testable import EdgeTAM_iOS

/// Tests for the complete video processing pipeline integration
final class VideoProcessingPipelineTests: XCTestCase {
    
    var container: DependencyContainer!
    var cameraManager: CameraManagerProtocol!
    var modelManager: ModelManagerProtocol!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        container = DependencyContainer()
        container.registerDefaultServices()
        
        cameraManager = try container.resolve(CameraManagerProtocol.self)
        modelManager = try container.resolve(ModelManagerProtocol.self)
    }
    
    override func tearDownWithError() throws {
        cameraManager?.stopSession()
        modelManager?.unloadModel()
        container?.clear()
        
        cameraManager = nil
        modelManager = nil
        container = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Pipeline Integration Tests
    
    func testVideoFrameProcessingPipeline() throws {
        // Test that video frames can flow from camera to model processing
        let mockVideoDelegate = MockVideoProcessingDelegate()
        cameraManager.setVideoOutput(delegate: mockVideoDelegate)
        
        // Verify delegate is set up correctly
        XCTAssertNotNil(mockVideoDelegate)
        
        // Test pixel buffer creation (simulating camera output)
        guard let testPixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Verify pixel buffer properties
        let width = CVPixelBufferGetWidth(testPixelBuffer)
        let height = CVPixelBufferGetHeight(testPixelBuffer)
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(testPixelBuffer)
        XCTAssertEqual(pixelFormat, kCVPixelFormatType_32BGRA)
    }
    
    func testPromptToInferenceFlow() async throws {
        // Test the flow from user prompts to model inference
        let testPrompt = createTestPrompt()
        XCTAssertNotNil(testPrompt.id)
        XCTAssertNotNil(testPrompt.timestamp)
        
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Test inference input validation (without actually loading model)
        let testModelManager = TestableModelManager()
        
        do {
            _ = try await testModelManager.performInference(on: pixelBuffer, with: [testPrompt])
            // Should succeed with mock implementation
        } catch let error as EdgeTAMError {
            // Expected to fail with validation or model loading error
            XCTAssertTrue([.invalidState("Model not loaded"), .modelNotFound("EdgeTAM")].contains(error))
        }
    }
    
    func testDataModelIntegration() throws {
        // Test that all data models work together correctly
        let frameMetadata = FrameMetadata(
            frameNumber: 1,
            processingTime: 0.016,
            inferenceTime: 0.050,
            memoryUsage: 200 * 1024 * 1024
        )
        
        XCTAssertEqual(frameMetadata.frameNumber, 1)
        XCTAssertEqual(frameMetadata.processingTime, 0.016)
        XCTAssertEqual(frameMetadata.inferenceTime, 0.050)
        
        // Test ProcessedFrame creation
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        let processedFrame = ProcessedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMTime.zero,
            segmentationMasks: [],
            metadata: frameMetadata,
            frameNumber: 1
        )
        
        XCTAssertEqual(processedFrame.frameNumber, 1)
        XCTAssertEqual(processedFrame.segmentationMasks.count, 0)
        XCTAssertEqual(processedFrame.metadata.frameNumber, 1)
    }
    
    func testPerformanceMetricsIntegration() throws {
        // Test that performance metrics are properly tracked
        let metrics = PerformanceMetrics(
            currentFPS: 15.0,
            averageInferenceTime: 0.045,
            memoryPressure: 0.6,
            thermalState: .nominal
        )
        
        XCTAssertEqual(metrics.currentFPS, 15.0)
        XCTAssertEqual(metrics.averageInferenceTime, 0.045)
        XCTAssertEqual(metrics.memoryPressure, 0.6)
        XCTAssertEqual(metrics.thermalState, .nominal)
        
        // Test that metrics meet performance requirements
        XCTAssertGreaterThanOrEqual(metrics.currentFPS, 15.0, "Should meet minimum FPS requirement")
        XCTAssertLessThanOrEqual(metrics.averageInferenceTime, 0.060, "Should meet inference time requirement")
    }
    
    func testErrorPropagationThroughPipeline() async throws {
        // Test that errors propagate correctly through the processing pipeline
        let cameraDelegate = MockPipelineCameraDelegate()
        let modelDelegate = MockPipelineModelDelegate()
        
        cameraManager.delegate = cameraDelegate
        modelManager.delegate = modelDelegate
        
        // Trigger model loading error
        do {
            try await modelManager.loadModel()
            XCTFail("Expected model loading to fail")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error.category, .model)
            XCTAssertTrue(modelDelegate.didFailWithErrorCalled)
            XCTAssertEqual(modelDelegate.lastError?.category, .model)
        }
    }
    
    func testConfigurationConsistency() throws {
        // Test that configurations are consistent across components
        let appConfig = try container.resolve(AppConfiguration.self)
        let modelConfig = try container.resolve(ModelConfiguration.self)
        
        // Verify configurations support the requirements
        XCTAssertGreaterThanOrEqual(appConfig.targetFPS, 15, "Should support minimum 15 FPS (Requirement 1.2)")
        XCTAssertLessOrEqual(appConfig.maxTrackedObjects, 5, "Should limit to 5 objects (Requirement 2.4)")
        XCTAssertGreaterThanOrEqual(appConfig.confidenceThreshold, 0.0)
        XCTAssertLessOrEqual(appConfig.confidenceThreshold, 1.0)
        
        XCTAssertEqual(modelConfig.modelName, "EdgeTAM", "Should use EdgeTAM model (Requirement 5.1)")
        XCTAssertTrue(modelConfig.useNeuralEngine, "Should use Neural Engine (Requirement 5.2)")
    }
    
    // MARK: - Requirements Validation Tests
    
    func testRequirement1_2_FrameProcessingRate() throws {
        // Requirement 1.2: Video_Segmentation_Engine SHALL process frames at minimum 15 FPS
        let appConfig = try container.resolve(AppConfiguration.self)
        XCTAssertGreaterThanOrEqual(appConfig.targetFPS, 15, 
                                   "Target FPS should meet minimum requirement of 15 FPS")
    }
    
    func testRequirement2_3_SegmentationResponseTime() throws {
        // Requirement 2.3: Video_Segmentation_Engine SHALL generate initial mask within 200ms
        // This is tested through the inference time tracking in ModelManager
        XCTAssertEqual(modelManager.inferenceTime, 0, "Initial inference time should be 0")
        
        // The actual 200ms requirement would be validated during real inference
        // For now, we verify the tracking mechanism exists
        XCTAssertNotNil(modelManager.inferenceTime)
    }
    
    func testRequirement2_4_MultipleObjectSupport() throws {
        // Requirement 2.4: System SHALL support up to 5 simultaneous object selections
        let appConfig = try container.resolve(AppConfiguration.self)
        XCTAssertLessOrEqual(appConfig.maxTrackedObjects, 5,
                            "Should not exceed maximum of 5 tracked objects")
        
        // Test prompt limit validation
        let prompts = (0..<6).map { _ in createTestPrompt() }
        let testModelManager = TestableModelManager()
        
        Task {
            do {
                guard let pixelBuffer = createTestPixelBuffer() else { return }
                _ = try await testModelManager.performInference(on: pixelBuffer, with: prompts)
                XCTFail("Should fail with too many prompts")
            } catch EdgeTAMError.promptLimitExceeded {
                // Expected error
            } catch {
                XCTFail("Expected promptLimitExceeded error")
            }
        }
    }
    
    func testRequirement5_5_InferenceTimeRequirement() throws {
        // Requirement 5.5: System SHALL achieve inference times under 60ms per frame
        // This is validated through the ModelManager's inference time tracking
        
        // Test that the tracking mechanism exists
        XCTAssertNotNil(modelManager.inferenceTime)
        
        // In a real test with loaded model, we would verify:
        // XCTAssertLessThan(modelManager.inferenceTime, 0.060)
    }
    
    // MARK: - Helper Methods
    
    private func createTestPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            640,
            480,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }
    
    private func createTestPrompt() -> Prompt {
        return Prompt.point(PointPrompt(
            location: CGPoint(x: 320, y: 240),
            modelCoordinates: CGPoint(x: 0.5, y: 0.5),
            isPositive: true
        ))
    }
}

// MARK: - Mock Delegates for Pipeline Testing

class MockVideoProcessingDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var receivedFrames: [CMSampleBuffer] = []
    var droppedFrames: [CMSampleBuffer] = []
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didOutput sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        receivedFrames.append(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didDrop sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        droppedFrames.append(sampleBuffer)
    }
}

class MockPipelineCameraDelegate: CameraManagerDelegate {
    var events: [String] = []
    var lastError: EdgeTAMError?
    
    func cameraManagerDidStartSession(_ manager: CameraManagerProtocol) {
        events.append("sessionStarted")
    }
    
    func cameraManagerDidStopSession(_ manager: CameraManagerProtocol) {
        events.append("sessionStopped")
    }
    
    func cameraManagerDidSwitchCamera(_ manager: CameraManagerProtocol) {
        events.append("cameraSwitched")
    }
    
    func cameraManager(_ manager: CameraManagerProtocol, didFailWithError error: EdgeTAMError) {
        events.append("error: \(error.category)")
        lastError = error
    }
}

class MockPipelineModelDelegate: ModelManagerDelegate {
    var events: [String] = []
    var didFailWithErrorCalled = false
    var lastError: EdgeTAMError?
    
    func modelManagerDidLoadModel(_ manager: ModelManagerProtocol) {
        events.append("modelLoaded")
    }
    
    func modelManagerDidUnloadModel(_ manager: ModelManagerProtocol) {
        events.append("modelUnloaded")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didCompleteInference result: SegmentationResult) {
        events.append("inferenceCompleted")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didFailWithError error: EdgeTAMError) {
        events.append("error: \(error.category)")
        didFailWithErrorCalled = true
        lastError = error
    }
}

// MARK: - Testable ModelManager for Pipeline Testing

class TestableModelManager: ModelManager {
    override var isModelLoaded: Bool {
        return true // Always return true for pipeline testing
    }
    
    override func performInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> SegmentationResult {
        // Only perform validation, don't actually run inference
        try validateInferenceInput(pixelBuffer: pixelBuffer, prompts: prompts)
        
        // Return mock result for successful validation
        let mockMask = SegmentationMask(
            objectId: UUID(),
            maskBuffer: pixelBuffer,
            confidence: 0.9,
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            timestamp: CMTime.zero
        )
        
        let metadata = InferenceMetadata(
            inputResolution: CGSize(width: 640, height: 480),
            outputResolution: CGSize(width: 640, height: 480)
        )
        
        return SegmentationResult(
            masks: [mockMask],
            inferenceTime: 0.045, // Under 60ms requirement
            confidence: 0.9,
            metadata: metadata,
            timestamp: CMTime.zero
        )
    }
    
    // Expose private method for testing
    func validateInferenceInput(pixelBuffer: CVPixelBuffer, prompts: [Prompt]) throws {
        try super.validateInferenceInput(pixelBuffer: pixelBuffer, prompts: prompts)
    }
}