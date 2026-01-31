import XCTest
import AVFoundation
@testable import EdgeTAM_iOS

/// Unit tests for CameraManager implementation
final class CameraManagerTests: XCTestCase {
    
    var cameraManager: CameraManager!
    
    override func setUp() {
        super.setUp()
        cameraManager = CameraManager()
    }
    
    override func tearDown() {
        cameraManager?.stopSession()
        cameraManager = nil
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testCameraManagerInitialization() {
        // Test that CameraManager initializes correctly
        XCTAssertNotNil(cameraManager)
        XCTAssertFalse(cameraManager.isRunning)
        XCTAssertEqual(cameraManager.currentPosition, .back)
    }
    
    func testCameraManagerProtocolConformance() {
        // Test that CameraManager conforms to CameraManagerProtocol
        XCTAssertTrue(cameraManager is CameraManagerProtocol)
    }
    
    func testSessionNotRunningInitially() {
        // Test that session is not running initially
        XCTAssertFalse(cameraManager.isRunning)
        XCTAssertNil(cameraManager.currentDevice)
    }
    
    func testStopSessionWhenNotRunning() {
        // Test that stopping a session that's not running doesn't crash
        XCTAssertNoThrow(cameraManager.stopSession())
        XCTAssertFalse(cameraManager.isRunning)
    }
    
    // MARK: - Permission Tests
    
    func testCameraPermissionDeniedError() async {
        // This test would require mocking AVCaptureDevice.authorizationStatus
        // For now, we'll test the error handling structure
        
        // Test that the error type exists and has proper description
        let error = EdgeTAMError.cameraPermissionDenied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Camera access is required"))
        XCTAssertTrue(error.isRecoverable)
    }
    
    func testCameraInitializationFailedError() {
        let testReason = "Test failure reason"
        let error = EdgeTAMError.cameraInitializationFailed(testReason)
        
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(testReason))
        XCTAssertTrue(error.isRecoverable)
    }
    
    // MARK: - Configuration Tests
    
    func testVideoOutputConfiguration() {
        // Test that video output delegate can be set without crashing
        let mockDelegate = MockVideoOutputDelegate()
        XCTAssertNoThrow(cameraManager.setVideoOutput(delegate: mockDelegate))
    }
    
    // MARK: - Camera Switching Tests
    
    func testCameraSwitchingWithContinuity() async {
        // Test that camera switching maintains session continuity
        let mockDelegate = MockCameraManagerDelegate()
        cameraManager.delegate = mockDelegate
        
        // Start session first
        do {
            try await cameraManager.startSession()
            XCTAssertTrue(cameraManager.isRunning)
            XCTAssertTrue(mockDelegate.sessionStartedCalled)
        } catch {
            XCTFail("Failed to start camera session: \(error)")
            return
        }
        
        // Test camera switching
        do {
            let initialPosition = cameraManager.currentPosition
            try await cameraManager.switchCamera()
            
            // Verify camera switched
            XCTAssertNotEqual(cameraManager.currentPosition, initialPosition)
            XCTAssertTrue(mockDelegate.cameraSwitchedCalled)
            
            // Verify session is still running (continuity maintained)
            XCTAssertTrue(cameraManager.isRunning)
            
        } catch {
            XCTFail("Camera switching failed: \(error)")
        }
    }
    
    func testCameraSwitchingErrorHandling() async {
        // Test error handling when camera switching fails
        let mockDelegate = MockCameraManagerDelegate()
        cameraManager.delegate = mockDelegate
        
        // Try to switch camera without starting session
        do {
            try await cameraManager.switchCamera()
            XCTFail("Expected camera switching to fail when session is not running")
        } catch let error as EdgeTAMError {
            XCTAssertEqual(error.category, .camera)
            XCTAssertTrue(error.localizedDescription.contains("not running"))
        } catch {
            XCTFail("Expected EdgeTAMError but got: \(error)")
        }
    }
    
    func testCameraSwitchingDelegateCallbacks() async {
        // Test that delegate callbacks are called in correct order
        let mockDelegate = MockCameraManagerDelegate()
        cameraManager.delegate = mockDelegate
        
        do {
            try await cameraManager.startSession()
            try await cameraManager.switchCamera()
            
            // Verify delegate callbacks were called
            XCTAssertTrue(mockDelegate.sessionStartedCalled)
            XCTAssertTrue(mockDelegate.cameraSwitchedCalled)
            XCTAssertNil(mockDelegate.errorReceived)
            
        } catch {
            XCTFail("Camera operations failed: \(error)")
        }
    }

    // MARK: - Error Handling Tests
    
    func testErrorCategories() {
        let cameraErrors: [EdgeTAMError] = [
            .cameraPermissionDenied,
            .cameraInitializationFailed("test"),
            .cameraDeviceNotAvailable,
            .cameraSwitchingFailed("test"),
            .cameraSessionInterrupted
        ]
        
        for error in cameraErrors {
            XCTAssertEqual(error.category, .camera)
        }
    }
    
    func testRecoverableErrors() {
        let recoverableErrors: [EdgeTAMError] = [
            .cameraPermissionDenied,
            .cameraDeviceNotAvailable,
            .memoryPressure,
            .thermalThrottling
        ]
        
        for error in recoverableErrors {
            XCTAssertTrue(error.isRecoverable, "Error \(error) should be recoverable")
        }
    }
    
    func testNonRecoverableErrors() {
        let nonRecoverableErrors: [EdgeTAMError] = [
            .unsupportedDevice,
            .unsupportedIOSVersion,
            .modelNotFound("test")
        ]
        
        for error in nonRecoverableErrors {
            XCTAssertFalse(error.isRecoverable, "Error \(error) should not be recoverable")
        }
    }
}

// MARK: - Mock Classes

class MockVideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var receivedFrames: [CMSampleBuffer] = []
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didOutput sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        receivedFrames.append(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didDrop sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        // Handle dropped frames
    }
}

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