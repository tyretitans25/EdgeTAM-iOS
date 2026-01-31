import XCTest
import CoreML
import CoreVideo
@testable import EdgeTAM_iOS

final class ModelManagerTests: XCTestCase {
    
    var modelManager: ModelManager!
    var mockDelegate: MockModelManagerDelegate!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create model manager with test configuration
        let configuration = ModelConfiguration(
            modelName: "TestModel",
            inputSize: CGSize(width: 512, height: 512),
            batchSize: 1,
            useNeuralEngine: false, // Use CPU for testing
            computeUnits: .cpuOnly
        )
        
        modelManager = ModelManager(configuration: configuration)
        mockDelegate = MockModelManagerDelegate()
        modelManager.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        modelManager.unloadModel()
        modelManager = nil
        mockDelegate = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testModelManagerInitialization() {
        XCTAssertNotNil(modelManager)
        XCTAssertFalse(modelManager.isModelLoaded)
        XCTAssertEqual(modelManager.inferenceTime, 0)
        XCTAssertEqual(modelManager.memoryUsage, 100 * 1024 * 1024) // Base memory usage
        XCTAssertEqual(modelManager.configuration.modelName, "TestModel")
    }
    
    func testConfigurationUpdate() {
        let newConfiguration = ModelConfiguration(
            modelName: "NewTestModel",
            computeUnits: .cpuAndGPU
        )
        
        modelManager.configuration = newConfiguration
        
        XCTAssertEqual(modelManager.configuration.modelName, "NewTestModel")
        XCTAssertEqual(modelManager.configuration.computeUnits, .cpuAndGPU)
    }
    
    // MARK: - Model Loading Tests
    
    func testModelLoadingWithoutModelFile() async {
        // Test loading when model file doesn't exist
        do {
            try await modelManager.loadModel()
            XCTFail("Expected model loading to fail when model file doesn't exist")
        } catch let error as EdgeTAMError {
            switch error {
            case .modelNotFound(let modelName):
                XCTAssertEqual(modelName, "TestModel")
            default:
                XCTFail("Expected modelNotFound error, got \(error)")
            }
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
        
        XCTAssertFalse(modelManager.isModelLoaded)
    }
    
    func testUnloadModel() {
        // Test unloading model
        modelManager.unloadModel()
        
        XCTAssertFalse(modelManager.isModelLoaded)
        XCTAssertEqual(modelManager.inferenceTime, 0)
        XCTAssertEqual(modelManager.memoryUsage, 100 * 1024 * 1024) // Base memory usage
    }
    
    // MARK: - Inference Tests
    
    func testInferenceWithoutLoadedModel() async {
        // Create test pixel buffer
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Create test prompts
        let prompts = [createTestPointPrompt()]
        
        // Test inference without loaded model
        do {
            _ = try await modelManager.performInference(on: pixelBuffer, with: prompts)
            XCTFail("Expected inference to fail when model is not loaded")
        } catch let error as EdgeTAMError {
            switch error {
            case .invalidState(let message):
                XCTAssertEqual(message, "Model not loaded")
            default:
                XCTFail("Expected invalidState error, got \(error)")
            }
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
    }
    
    func testInferenceInputValidation() async {
        // Test with empty prompts
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Force model to appear loaded for validation testing
        let testModelManager = TestableModelManager()
        
        do {
            _ = try await testModelManager.performInference(on: pixelBuffer, with: [])
            XCTFail("Expected inference to fail with empty prompts")
        } catch let error as EdgeTAMError {
            switch error {
            case .invalidPrompt(let message):
                XCTAssertEqual(message, "At least one prompt is required")
            default:
                XCTFail("Expected invalidPrompt error, got \(error)")
            }
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
    }
    
    func testInferenceWithTooManyPrompts() async {
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Create 6 prompts (exceeds limit of 5)
        let prompts = (0..<6).map { _ in createTestPointPrompt() }
        
        let testModelManager = TestableModelManager()
        
        do {
            _ = try await testModelManager.performInference(on: pixelBuffer, with: prompts)
            XCTFail("Expected inference to fail with too many prompts")
        } catch let error as EdgeTAMError {
            switch error {
            case .promptLimitExceeded:
                break // Expected error
            default:
                XCTFail("Expected promptLimitExceeded error, got \(error)")
            }
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
    }
    
    func testInferenceWithInvalidPromptCoordinates() async {
        guard let pixelBuffer = createTestPixelBuffer() else {
            XCTFail("Failed to create test pixel buffer")
            return
        }
        
        // Create prompt with invalid coordinates (outside 0-1 range)
        let invalidPrompt = Prompt.point(PointPrompt(
            location: CGPoint(x: 100, y: 100),
            modelCoordinates: CGPoint(x: 2.0, y: 2.0), // Invalid: outside 0-1 range
            isPositive: true
        ))
        
        let testModelManager = TestableModelManager()
        
        do {
            _ = try await testModelManager.performInference(on: pixelBuffer, with: [invalidPrompt])
            XCTFail("Expected inference to fail with invalid prompt coordinates")
        } catch let error as EdgeTAMError {
            switch error {
            case .invalidPrompt(let message):
                XCTAssertTrue(message.contains("normalized"))
            default:
                XCTFail("Expected invalidPrompt error, got \(error)")
            }
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryUsageTracking() {
        let initialMemoryUsage = modelManager.memoryUsage
        XCTAssertEqual(initialMemoryUsage, 100 * 1024 * 1024) // Base memory usage
        
        // Memory usage should remain the same when model is not loaded
        XCTAssertEqual(modelManager.memoryUsage, initialMemoryUsage)
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateAssignment() {
        XCTAssertNotNil(modelManager.delegate)
        XCTAssertTrue(modelManager.delegate === mockDelegate)
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
    
    private func createTestPointPrompt() -> Prompt {
        return Prompt.point(PointPrompt(
            location: CGPoint(x: 320, y: 240),
            modelCoordinates: CGPoint(x: 0.5, y: 0.5),
            isPositive: true
        ))
    }
    
    private func createTestBoxPrompt() -> Prompt {
        return Prompt.box(BoxPrompt(
            rect: CGRect(x: 100, y: 100, width: 200, height: 200),
            modelCoordinates: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        ))
    }
}

// MARK: - Mock Delegate

class MockModelManagerDelegate: ModelManagerDelegate {
    var didLoadModelCalled = false
    var didUnloadModelCalled = false
    var didCompleteInferenceCalled = false
    var didFailWithErrorCalled = false
    var lastError: EdgeTAMError?
    var lastResult: SegmentationResult?
    
    func modelManagerDidLoadModel(_ manager: ModelManagerProtocol) {
        didLoadModelCalled = true
    }
    
    func modelManagerDidUnloadModel(_ manager: ModelManagerProtocol) {
        didUnloadModelCalled = true
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didCompleteInference result: SegmentationResult) {
        didCompleteInferenceCalled = true
        lastResult = result
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didFailWithError error: EdgeTAMError) {
        didFailWithErrorCalled = true
        lastError = error
    }
}

// MARK: - Testable ModelManager

class TestableModelManager: ModelManager {
    override var isModelLoaded: Bool {
        return true // Always return true for testing validation logic
    }
    
    override func performInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> SegmentationResult {
        // Only perform validation, don't actually run inference
        try validateInferenceInput(pixelBuffer: pixelBuffer, prompts: prompts)
        
        // Return mock result
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
            inferenceTime: 0.05,
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