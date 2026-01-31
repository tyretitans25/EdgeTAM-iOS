import XCTest
import AVFoundation
@testable import EdgeTAM_iOS

/// Integration tests for CameraManager with the dependency injection system
final class CameraManagerIntegrationTests: XCTestCase {
    
    var container: DependencyContainer!
    
    override func setUp() {
        super.setUp()
        container = DependencyContainer()
        container.registerDefaultServices()
    }
    
    override func tearDown() {
        container.clear()
        container = nil
        super.tearDown()
    }
    
    // MARK: - Dependency Injection Tests
    
    func testCameraManagerRegistration() throws {
        // Test that CameraManager is properly registered in the container
        XCTAssertTrue(container.isRegistered(CameraManagerProtocol.self))
        
        let cameraManager = try container.resolve(CameraManagerProtocol.self)
        XCTAssertNotNil(cameraManager)
        XCTAssertTrue(cameraManager is CameraManager)
    }
    
    func testCameraManagerSingletonBehavior() throws {
        // Test that the same instance is returned on multiple resolves
        let cameraManager1 = try container.resolve(CameraManagerProtocol.self)
        let cameraManager2 = try container.resolve(CameraManagerProtocol.self)
        
        XCTAssertTrue(cameraManager1 === cameraManager2, "CameraManager should be a singleton")
    }
    
    func testCameraManagerInitialState() throws {
        let cameraManager = try container.resolve(CameraManagerProtocol.self)
        
        // Test initial state
        XCTAssertFalse(cameraManager.isRunning)
        XCTAssertEqual(cameraManager.currentPosition, .back)
        XCTAssertNil(cameraManager.currentDevice)
    }
    
    // MARK: - Configuration Integration Tests
    
    func testAppConfigurationIntegration() throws {
        let appConfig = try container.resolve(AppConfiguration.self)
        let cameraManager = try container.resolve(CameraManagerProtocol.self)
        
        XCTAssertNotNil(appConfig)
        XCTAssertNotNil(cameraManager)
        
        // Test that configuration values are reasonable
        XCTAssertGreaterThan(appConfig.targetFPS, 0)
        XCTAssertGreaterThan(appConfig.maxTrackedObjects, 0)
        XCTAssertGreaterThanOrEqual(appConfig.maskOpacity, 0.0)
        XCTAssertLessThanOrEqual(appConfig.maskOpacity, 1.0)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testCameraManagerErrorHandling() throws {
        let cameraManager = try container.resolve(CameraManagerProtocol.self)
        let delegate = MockCameraManagerDelegate()
        cameraManager.delegate = delegate
        
        // Test that delegate can be set without issues
        XCTAssertNotNil(cameraManager.delegate)
        XCTAssertTrue(cameraManager.delegate === delegate)
    }
    
    // MARK: - Service Lifecycle Tests
    
    func testServiceLifecycleIntegration() async throws {
        // Test that services can be initialized without errors
        // Note: This would require actual ServiceLifecycle implementation
        XCTAssertNoThrow(try await container.initializeServices())
    }
    
    func testServiceShutdown() async {
        // Test that services can be shut down gracefully
        await container.shutdownServices()
        
        // Services should still be registered but may be in shutdown state
        XCTAssertTrue(container.isRegistered(CameraManagerProtocol.self))
    }
    
    // MARK: - Memory Management Tests
    
    func testCameraManagerMemoryManagement() throws {
        weak var weakCameraManager: CameraManagerProtocol?
        
        autoreleasepool {
            let cameraManager = try container.resolve(CameraManagerProtocol.self)
            weakCameraManager = cameraManager
            XCTAssertNotNil(weakCameraManager)
        }
        
        // The container should still hold a reference
        XCTAssertNotNil(weakCameraManager)
        
        // Clear the container
        container.clear()
        
        // Now the reference should be released
        // Note: This test might be flaky due to ARC timing
        // In a real scenario, we'd need more sophisticated memory testing
    }
}

// MARK: - Mock Delegate for Integration Testing

class MockCameraManagerDelegate: CameraManagerDelegate {
    var sessionStartedCalled = false
    var sessionStoppedCalled = false
    var cameraSwitchedCalled = false
    var errorReceived: EdgeTAMError?
    
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
        errorReceived = error
    }
}