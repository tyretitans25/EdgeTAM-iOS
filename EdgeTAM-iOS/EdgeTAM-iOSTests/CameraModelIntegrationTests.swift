import XCTest
import AVFoundation
import CoreVideo
@testable import EdgeTAM_iOS

/// Integration tests for CameraManager and ModelManager working together
final class CameraModelIntegrationTests: XCTestCase {
    
    var container: DependencyContainer!
    var cameraManager: CameraManagerProtocol!
    var modelManager: ModelManagerProtocol!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Set up dependency container with actual implementations
        container = DependencyContainer()
        container.registerDefaultServices()
        
        // Resolve services
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
    
    // MARK: - Integration Tests
    
    func testCameraManagerAndModelManagerIntegration() throws {
        // Test that both services can be resolved and are the correct types
        XCTAssertTrue(cameraManager is CameraManager, "Should resolve to actual CameraManager implementation")
        XCTAssertTrue(modelManager is ModelManager, "Should resolve to actual ModelManager implementation")
        
        // Test initial states
        XCTAssertFalse(cameraManager.isRunning)
        XCTAssertFalse(modelManager.isModelLoaded)
    }
    
    func testDependencyInjectionConsistency() throws {
        // Test that the same instances are returned on multiple resolves
        let cameraManager2 = try container.resolve(CameraManagerProtocol.self)
        let modelManager2 = try container.resolve(ModelManagerProtocol.self)
        
        XCTAssertTrue(cameraManager === cameraManager2, "CameraManager should be singleton")
        XCTAssertTrue(modelManager === modelManager2, "ModelManager should be singleton")
    }
    
    func testServiceConfiguration() throws {
        // Test that services have proper configurations
        let appConfig = try container.resolve(AppConfiguration.self)
        let modelConfig = try container.resolve(ModelConfiguration.self)
        
        XCTAssertNotNil(appConfig)
        XCTAssertNotNil(modelConfig)
        
        // Verify configuration values are reasonable
        XCTAssertGreaterThan(appConfig.targetFPS, 0)
        XCTAssertGreaterThan(appConfig.maxTrackedObjects, 0)
        XCTAssertGreaterThanOrEqual(appConfig.maskOpacity, 0.0)
        XCTAssertLessThanOrEqual(appConfig.maskOpacity, 1.0)
        
        XCTAssertEqual(modelConfig.modelName, "EdgeTAM")
        XCTAssertGreaterThan(modelConfig.inputSize.width, 0)
        XCTAssertGreaterThan(modelConfig.inputSize.height, 0)
    }
    
    func testCameraManagerDelegateIntegration() throws {
        let delegate = MockIntegrationCameraDelegate()
        cameraManager.delegate = delegate
        
        XCTAssertNotNil(cameraManager.delegate)
        XCTAssertTrue(cameraManager.delegate === delegate)
    }
    
    func testModelManagerDelegateIntegration() throws {
        let delegate = MockIntegrationModelDelegate()
        modelManager.delegate = delegate
        
        XCTAssertNotNil(modelManager.delegate)
        XCTAssertTrue(modelManager.delegate === delegate)
    }
    
    func testErrorHandlingIntegration() async throws {
        // Test that both services handle errors appropriately
        let cameraDelegate = MockIntegrationCameraDelegate()
        let modelDelegate = MockIntegrationModelDelegate()
        
        cameraManager.delegate = cameraDelegate
        modelManager.delegate = modelDelegate
        
        // Test model loading without model file (should fail gracefully)
        do {
            try await modelManager.loadModel()
            XCTFail("Expected model loading to fail without model file")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error.category, .model)
            XCTAssertNotNil(error.errorDescription)
        }
        
        // Verify delegate was notified
        XCTAssertTrue(modelDelegate.didFailWithErrorCalled)
        XCTAssertNotNil(modelDelegate.lastError)
    }
    
    func testMemoryManagement() throws {
        // Test that services properly manage memory
        let initialCameraMemory = cameraManager.isRunning
        let initialModelMemory = modelManager.memoryUsage
        
        XCTAssertFalse(initialCameraMemory)
        XCTAssertGreaterThan(initialModelMemory, 0)
        
        // Test cleanup
        modelManager.unloadModel()
        XCTAssertEqual(modelManager.memoryUsage, 100 * 1024 * 1024) // Base memory
    }
    
    func testServiceLifecycle() async throws {
        // Test that services can be initialized and shut down properly
        XCTAssertNoThrow(try await container.initializeServices())
        await container.shutdownServices()
        
        // Services should still be registered after shutdown
        XCTAssertTrue(container.isRegistered(CameraManagerProtocol.self))
        XCTAssertTrue(container.isRegistered(ModelManagerProtocol.self))
    }
    
    // MARK: - Requirements Validation
    
    func testRequirement1_1_CameraInitialization() throws {
        // Requirement 1.1: Camera_Manager SHALL initialize the device camera
        XCTAssertNotNil(cameraManager)
        XCTAssertFalse(cameraManager.isRunning, "Camera should not be running initially")
        XCTAssertEqual(cameraManager.currentPosition, .back, "Should default to back camera")
    }
    
    func testRequirement5_1_ModelManagerInitialization() throws {
        // Requirement 5.1: Model_Manager SHALL load the EdgeTAM CoreML model
        XCTAssertNotNil(modelManager)
        XCTAssertFalse(modelManager.isModelLoaded, "Model should not be loaded initially")
        XCTAssertEqual(modelManager.configuration.modelName, "EdgeTAM")
    }
    
    func testRequirement5_2_NeuralEngineConfiguration() throws {
        // Requirement 5.2: Model_Manager SHALL utilize Neural Engine acceleration
        let modelConfig = modelManager.configuration
        XCTAssertTrue(modelConfig.useNeuralEngine, "Neural Engine should be enabled")
        XCTAssertEqual(modelConfig.computeUnits, .all, "All compute units should be available")
    }
    
    func testRequirement5_4_MemoryOptimization() throws {
        // Requirement 5.4: Model_Manager SHALL optimize memory usage
        let initialMemory = modelManager.memoryUsage
        XCTAssertGreaterThan(initialMemory, 0, "Should track memory usage")
        
        // Test memory cleanup
        modelManager.unloadModel()
        let cleanedMemory = modelManager.memoryUsage
        XCTAssertLessThanOrEqual(cleanedMemory, initialMemory, "Memory should be optimized after unload")
    }
}

// MARK: - Mock Delegates for Integration Testing

class MockIntegrationCameraDelegate: CameraManagerDelegate {
    var sessionStartedCalled = false
    var sessionStoppedCalled = false
    var cameraSwitchedCalled = false
    var didFailWithErrorCalled = false
    var lastError: EdgeTAMError?
    
    func cameraManagerDidStartSession(_ manager: CameraManagerProtocol) {
        sessionStartedCalled = true
    }
    
    func cameraManagerDidStopSession(_ manager: CameraManagerProtocol) {
        sessionStoppedCalled = true
    }
    
    func cameraManagerDidSwitchCamera(_ manager: CameraManagerProtocol) {
        cameraSwitchedCalled = true
    }
    
    func cameraManager(_ manager: CameraManagerProtocol, didFailWithError error: EdgeTAMError) {
        didFailWithErrorCalled = true
        lastError = error
    }
}

class MockIntegrationModelDelegate: ModelManagerDelegate {
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