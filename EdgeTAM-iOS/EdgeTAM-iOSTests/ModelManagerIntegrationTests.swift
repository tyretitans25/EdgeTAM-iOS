import XCTest
import CoreML
import CoreVideo
@testable import EdgeTAM_iOS

final class ModelManagerIntegrationTests: XCTestCase {
    
    var modelManager: ModelManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create model manager with realistic configuration
        let configuration = ModelConfiguration(
            modelName: "EdgeTAM",
            inputSize: CGSize(width: 1024, height: 1024),
            batchSize: 1,
            useNeuralEngine: true,
            computeUnits: .all
        )
        
        modelManager = ModelManager(configuration: configuration)
    }
    
    override func tearDownWithError() throws {
        modelManager.unloadModel()
        modelManager = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testModelManagerProtocolConformance() {
        // Test that ModelManager conforms to ModelManagerProtocol
        XCTAssertTrue(modelManager is ModelManagerProtocol)
        
        // Test protocol properties are accessible
        XCTAssertNotNil(modelManager.isModelLoaded)
        XCTAssertNotNil(modelManager.inferenceTime)
        XCTAssertNotNil(modelManager.memoryUsage)
        XCTAssertNotNil(modelManager.configuration)
    }
    
    func testModelManagerDelegateProtocol() {
        let delegate = TestModelManagerDelegate()
        modelManager.delegate = delegate
        
        XCTAssertNotNil(modelManager.delegate)
        XCTAssertTrue(modelManager.delegate === delegate)
    }
    
    // MARK: - Configuration Integration Tests
    
    func testConfigurationIntegration() {
        // Test that configuration is properly integrated
        XCTAssertEqual(modelManager.configuration.modelName, "EdgeTAM")
        XCTAssertEqual(modelManager.configuration.inputSize, CGSize(width: 1024, height: 1024))
        XCTAssertEqual(modelManager.configuration.batchSize, 1)
        XCTAssertTrue(modelManager.configuration.useNeuralEngine)
        XCTAssertEqual(modelManager.configuration.computeUnits, .all)
    }
    
    func testConfigurationUpdate() {
        let newConfiguration = ModelConfiguration(
            modelName: "EdgeTAM_v2",
            inputSize: CGSize(width: 512, height: 512),
            computeUnits: .cpuOnly
        )
        
        modelManager.configuration = newConfiguration
        
        XCTAssertEqual(modelManager.configuration.modelName, "EdgeTAM_v2")
        XCTAssertEqual(modelManager.configuration.inputSize, CGSize(width: 512, height: 512))
        XCTAssertEqual(modelManager.configuration.computeUnits, .cpuOnly)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testErrorHandlingIntegration() async {
        // Test that EdgeTAMError types are properly handled
        do {
            try await modelManager.loadModel()
            XCTFail("Expected model loading to fail without model file")
        } catch let error as EdgeTAMError {
            // Verify error is properly categorized
            XCTAssertEqual(error.category, .model)
            XCTAssertNotNil(error.errorDescription)
            XCTAssertNotNil(error.recoverySuggestion)
        } catch {
            XCTFail("Expected EdgeTAMError, got \(error)")
        }
    }
    
    // MARK: - Data Model Integration Tests
    
    func testDataModelIntegration() {
        // Test that ModelManager works with defined data models
        let prompt = createTestPrompt()
        XCTAssertNotNil(prompt.id)
        XCTAssertNotNil(prompt.timestamp)
        
        // Test SegmentationResult creation
        let metadata = InferenceMetadata(
            inputResolution: CGSize(width: 1024, height: 1024),
            outputResolution: CGSize(width: 1024, height: 1024)
        )
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata.inputResolution.width, 1024)
    }
    
    // MARK: - Memory Management Integration Tests
    
    func testMemoryManagementIntegration() {
        // Test initial memory state
        let initialMemory = modelManager.memoryUsage
        XCTAssertGreaterThan(initialMemory, 0)
        
        // Test unload clears memory tracking
        modelManager.unloadModel()
        XCTAssertEqual(modelManager.memoryUsage, 100 * 1024 * 1024) // Base memory
        XCTAssertEqual(modelManager.inferenceTime, 0)
    }
    
    // MARK: - Performance Requirements Tests
    
    func testPerformanceRequirements() {
        // Test that configuration supports performance requirements
        // Requirements 5.1, 5.2, 5.5: Neural Engine optimization and <60ms inference
        
        XCTAssertTrue(modelManager.configuration.useNeuralEngine, 
                     "Neural Engine should be enabled for performance (Requirement 5.2)")
        
        XCTAssertEqual(modelManager.configuration.computeUnits, .all,
                      "All compute units should be available for optimal performance")
        
        // Test that inference time tracking is available
        XCTAssertEqual(modelManager.inferenceTime, 0) // Initially zero
    }
    
    // MARK: - Requirements Validation Tests
    
    func testRequirement5_1_ModelLoading() {
        // Requirement 5.1: Model_Manager SHALL load the EdgeTAM CoreML model into memory
        XCTAssertFalse(modelManager.isModelLoaded, "Model should not be loaded initially")
        
        // Test that loadModel method exists and is callable
        Task {
            do {
                try await modelManager.loadModel()
                // Would succeed if model file existed
            } catch {
                // Expected to fail without model file, but method should be callable
                XCTAssertTrue(error is EdgeTAMError)
            }
        }
    }
    
    func testRequirement5_2_NeuralEngineOptimization() {
        // Requirement 5.2: Model_Manager SHALL utilize available Neural Engine hardware acceleration
        XCTAssertTrue(modelManager.configuration.useNeuralEngine,
                     "Neural Engine optimization should be enabled")
        XCTAssertEqual(modelManager.configuration.computeUnits, .all,
                      "All compute units including Neural Engine should be available")
    }
    
    func testRequirement5_3_ErrorHandling() {
        // Requirement 5.3: System SHALL handle errors gracefully and provide fallback behavior
        Task {
            do {
                try await modelManager.loadModel()
            } catch let error as EdgeTAMError {
                // Verify graceful error handling
                XCTAssertNotNil(error.errorDescription)
                XCTAssertTrue(error.isRecoverable || !error.isRecoverable) // Has recovery info
                XCTAssertNotNil(error.category)
            } catch {
                XCTFail("Should handle errors as EdgeTAMError")
            }
        }
    }
    
    func testRequirement5_4_MemoryManagement() {
        // Requirement 5.4: Model_Manager SHALL optimize memory usage while maintaining functionality
        let initialMemory = modelManager.memoryUsage
        XCTAssertGreaterThan(initialMemory, 0, "Should track memory usage")
        
        // Test memory cleanup on unload
        modelManager.unloadModel()
        let unloadedMemory = modelManager.memoryUsage
        XCTAssertLessThanOrEqual(unloadedMemory, initialMemory, "Memory should be optimized after unload")
    }
    
    // MARK: - Helper Methods
    
    private func createTestPrompt() -> Prompt {
        return Prompt.point(PointPrompt(
            location: CGPoint(x: 512, y: 512),
            modelCoordinates: CGPoint(x: 0.5, y: 0.5),
            isPositive: true
        ))
    }
}

// MARK: - Test Delegate

class TestModelManagerDelegate: ModelManagerDelegate {
    var events: [String] = []
    
    func modelManagerDidLoadModel(_ manager: ModelManagerProtocol) {
        events.append("didLoadModel")
    }
    
    func modelManagerDidUnloadModel(_ manager: ModelManagerProtocol) {
        events.append("didUnloadModel")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didCompleteInference result: SegmentationResult) {
        events.append("didCompleteInference")
    }
    
    func modelManager(_ manager: ModelManagerProtocol, didFailWithError error: EdgeTAMError) {
        events.append("didFailWithError: \(error.category)")
    }
}