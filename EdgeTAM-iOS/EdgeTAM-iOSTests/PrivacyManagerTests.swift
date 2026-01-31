import XCTest
import AVFoundation
import Photos
@testable import EdgeTAM_iOS

/// Unit tests for PrivacyManager functionality
@MainActor
final class PrivacyManagerTests: XCTestCase {
    
    var privacyManager: PrivacyManager!
    var mockDelegate: MockPrivacyManagerDelegate!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let settings = PrivacySettings(
            automaticCleanupEnabled: false, // Disable for controlled testing
            cleanupIntervalMinutes: 1,
            clearDataOnBackground: true,
            maxTemporaryFileSize: 1024 * 1024, // 1MB for testing
            enablePrivacyLogging: true
        )
        
        privacyManager = PrivacyManager(privacySettings: settings)
        mockDelegate = MockPrivacyManagerDelegate()
        privacyManager.delegate = mockDelegate
    }
    
    override func tearDown() async throws {
        // Clean up any temporary files created during tests
        try? await privacyManager.cleanupTemporaryFiles()
        privacyManager = nil
        mockDelegate = nil
        try await super.tearDown()
    }
    
    // MARK: - Temporary File Management Tests
    
    func testCreateTemporaryFileURL() {
        // Given
        let fileExtension = "mp4"
        
        // When
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: fileExtension)
        
        // Then
        XCTAssertTrue(tempURL.pathExtension == fileExtension)
        XCTAssertTrue(tempURL.path.contains("EdgeTAM"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.deletingLastPathComponent().path))
    }
    
    func testTrackTemporaryFile() {
        // Given
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "txt")
        
        // When
        privacyManager.trackTemporaryFile(tempURL)
        
        // Then
        // File should be tracked (we can't directly access the private set, but cleanup should handle it)
        XCTAssertNoThrow(privacyManager.trackTemporaryFile(tempURL))
    }
    
    func testCleanupTemporaryFiles() async throws {
        // Given
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "txt")
        let testData = "Test data".data(using: .utf8)!
        try testData.write(to: tempURL)
        privacyManager.trackTemporaryFile(tempURL)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // When
        try await privacyManager.cleanupTemporaryFiles()
        
        // Then
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
        XCTAssertEqual(mockDelegate.cleanupCallCount, 1)
        XCTAssertTrue(mockDelegate.lastFilesRemoved > 0)
    }
    
    func testGetTemporaryFilesSize() async throws {
        // Given
        let tempURL1 = privacyManager.createTemporaryFileURL(withExtension: "txt")
        let tempURL2 = privacyManager.createTemporaryFileURL(withExtension: "txt")
        
        let testData1 = "Test data 1".data(using: .utf8)!
        let testData2 = "Test data 2 with more content".data(using: .utf8)!
        
        try testData1.write(to: tempURL1)
        try testData2.write(to: tempURL2)
        
        // When
        let totalSize = await privacyManager.getTemporaryFilesSize()
        
        // Then
        let expectedSize = UInt64(testData1.count + testData2.count)
        XCTAssertEqual(totalSize, expectedSize)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempURL1)
        try? FileManager.default.removeItem(at: tempURL2)
    }
    
    // MARK: - Background/Foreground Handling Tests
    
    func testHandleAppDidEnterBackground() async {
        // Given
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "txt")
        try "test".write(to: tempURL, atomically: true, encoding: .utf8)
        privacyManager.trackTemporaryFile(tempURL)
        
        // When
        await privacyManager.handleAppDidEnterBackground()
        
        // Then
        XCTAssertEqual(mockDelegate.clearSensitiveDataCallCount, 1)
        XCTAssertEqual(mockDelegate.cleanupCallCount, 1)
    }
    
    func testPauseProcessingAndClearData() async {
        // When
        await privacyManager.pauseProcessingAndClearData()
        
        // Then
        XCTAssertEqual(mockDelegate.clearSensitiveDataCallCount, 1)
    }
    
    func testResumeProcessing() async throws {
        // Given - pause first
        await privacyManager.pauseProcessingAndClearData()
        
        // When
        try await privacyManager.resumeProcessing()
        
        // Then - should not throw since on-device processing is always valid
        XCTAssertNoThrow(try await privacyManager.resumeProcessing())
    }
    
    // MARK: - On-Device Processing Tests
    
    func testIsOnDeviceProcessingEnabled() {
        // When/Then
        XCTAssertTrue(privacyManager.isOnDeviceProcessingEnabled)
    }
    
    func testValidateOnDeviceProcessing() {
        // When
        let isValid = privacyManager.validateOnDeviceProcessing()
        
        // Then
        XCTAssertTrue(isValid)
    }
    
    func testPrivacyComplianceStatus() {
        // When
        let status = privacyManager.privacyComplianceStatus
        
        // Then
        XCTAssertTrue(status.isOnDeviceProcessingActive)
        XCTAssertFalse(status.networkActivityDetected)
        XCTAssertTrue(status.isCompliant)
    }
    
    // MARK: - Privacy Settings Tests
    
    func testUpdatePrivacySettings() async {
        // Given
        let newSettings = PrivacySettings(
            automaticCleanupEnabled: true,
            cleanupIntervalMinutes: 5,
            clearDataOnBackground: false,
            maxTemporaryFileSize: 2 * 1024 * 1024,
            enablePrivacyLogging: false
        )
        
        // When
        await privacyManager.updatePrivacySettings(newSettings)
        
        // Then
        XCTAssertEqual(privacyManager.privacySettings.cleanupIntervalMinutes, 5)
        XCTAssertFalse(privacyManager.privacySettings.clearDataOnBackground)
    }
    
    // MARK: - Memory Management Tests
    
    func testClearSensitiveDataFromMemory() async {
        // Given
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "txt")
        privacyManager.trackTemporaryFile(tempURL)
        
        // When
        await privacyManager.clearSensitiveDataFromMemory()
        
        // Then
        XCTAssertEqual(mockDelegate.clearSensitiveDataCallCount, 1)
    }
    
    func testClearProcessedData() async {
        // Given
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "txt")
        try "test".write(to: tempURL, atomically: true, encoding: .utf8)
        privacyManager.trackTemporaryFile(tempURL)
        
        // When
        await privacyManager.clearProcessedData()
        
        // Then
        XCTAssertEqual(mockDelegate.clearSensitiveDataCallCount, 1)
        XCTAssertEqual(mockDelegate.cleanupCallCount, 1)
    }
    
    // MARK: - Permission Tests
    
    func testCameraPermissionStatus() {
        // When
        let status = privacyManager.cameraPermissionStatus
        
        // Then
        // Status should be one of the valid AVAuthorizationStatus values
        XCTAssertTrue([.authorized, .denied, .notDetermined, .restricted].contains(status))
    }
    
    func testPhotoLibraryPermissionStatus() {
        // When
        let status = privacyManager.photoLibraryPermissionStatus
        
        // Then
        // Status should be one of the valid PHAuthorizationStatus values
        XCTAssertTrue([.authorized, .denied, .notDetermined, .restricted, .limited].contains(status))
    }
    
    // MARK: - Error Handling Tests
    
    func testCleanupFailureHandling() async {
        // Given - create a file in a read-only location (this will fail on cleanup)
        let readOnlyURL = URL(fileURLWithPath: "/System/test.txt") // This will fail
        privacyManager.trackTemporaryFile(readOnlyURL)
        
        // When/Then - should not throw even if individual file cleanup fails
        await XCTAssertNoThrowAsync(try await privacyManager.cleanupTemporaryFiles())
    }
}

// MARK: - Mock Delegate

class MockPrivacyManagerDelegate: PrivacyManagerDelegate {
    var cleanupCallCount = 0
    var clearSensitiveDataCallCount = 0
    var permissionUpdateCallCount = 0
    var complianceIssueCallCount = 0
    
    var lastFilesRemoved = 0
    var lastBytesFreed: UInt64 = 0
    var lastPermissionStatus = ""
    var lastComplianceIssue = ""
    
    func privacyManagerDidPerformCleanup(_ manager: PrivacyManagerProtocol, filesRemoved: Int, bytesFreed: UInt64) {
        cleanupCallCount += 1
        lastFilesRemoved = filesRemoved
        lastBytesFreed = bytesFreed
    }
    
    func privacyManagerDidClearSensitiveData(_ manager: PrivacyManagerProtocol) {
        clearSensitiveDataCallCount += 1
    }
    
    func privacyManager(_ manager: PrivacyManagerProtocol, didUpdatePermissionStatus status: String) {
        permissionUpdateCallCount += 1
        lastPermissionStatus = status
    }
    
    func privacyManager(_ manager: PrivacyManagerProtocol, didDetectComplianceIssue issue: String) {
        complianceIssueCallCount += 1
        lastComplianceIssue = issue
    }
}

// MARK: - Test Helpers

extension XCTest {
    func XCTAssertNoThrowAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Expression threw error: \(error)", file: file, line: line)
        }
    }
}