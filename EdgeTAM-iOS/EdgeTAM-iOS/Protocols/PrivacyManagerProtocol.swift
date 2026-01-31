import Foundation
import AVFoundation
import Photos
import UIKit

/// Protocol defining privacy protection and data management functionality
protocol PrivacyManagerProtocol: AnyObject, Sendable {
    
    // MARK: - Data Cleanup
    
    /// Automatically cleans up temporary files and cached data
    func cleanupTemporaryFiles() async throws
    
    /// Clears sensitive data from memory when app is backgrounded
    func clearSensitiveDataFromMemory() async
    
    /// Removes all processed frames and cached data
    func clearProcessedData() async
    
    // MARK: - Background/Foreground Handling
    
    /// Handles app transition to background state
    func handleAppDidEnterBackground() async
    
    /// Handles app transition to foreground state
    func handleAppWillEnterForeground() async
    
    /// Pauses video processing and clears sensitive data
    func pauseProcessingAndClearData() async
    
    /// Resumes video processing after foreground transition
    func resumeProcessing() async throws
    
    // MARK: - Permission Management
    
    /// Requests camera permission with clear explanation
    func requestCameraPermission() async -> Bool
    
    /// Requests photo library permission with clear explanation
    func requestPhotoLibraryPermission() async -> PHAuthorizationStatus
    
    /// Checks current camera permission status
    var cameraPermissionStatus: AVAuthorizationStatus { get }
    
    /// Checks current photo library permission status
    var photoLibraryPermissionStatus: PHAuthorizationStatus { get }
    
    // MARK: - On-Device Processing Guarantees
    
    /// Ensures all processing remains on-device
    var isOnDeviceProcessingEnabled: Bool { get }
    
    /// Validates that no data is sent to external servers
    func validateOnDeviceProcessing() -> Bool
    
    /// Returns privacy compliance status
    var privacyComplianceStatus: PrivacyComplianceStatus { get }
    
    // MARK: - Temporary File Management
    
    /// Returns the temporary directory for video processing
    var temporaryDirectory: URL { get }
    
    /// Creates a temporary file URL for processing
    func createTemporaryFileURL(withExtension ext: String) -> URL
    
    /// Tracks temporary files for automatic cleanup
    func trackTemporaryFile(_ url: URL)
    
    /// Gets the size of temporary files in bytes
    func getTemporaryFilesSize() async -> UInt64
    
    // MARK: - Privacy Settings
    
    /// Privacy configuration settings
    var privacySettings: PrivacySettings { get set }
    
    /// Updates privacy settings
    func updatePrivacySettings(_ settings: PrivacySettings) async
}

// MARK: - Supporting Types

/// Privacy compliance status information
struct PrivacyComplianceStatus: Sendable {
    let isOnDeviceProcessingActive: Bool
    let hasTemporaryFiles: Bool
    let lastCleanupTime: Date?
    let memoryContainsSensitiveData: Bool
    let networkActivityDetected: Bool
    
    var isCompliant: Bool {
        return isOnDeviceProcessingActive && 
               !networkActivityDetected
    }
}

/// Privacy configuration settings
struct PrivacySettings: Sendable {
    let automaticCleanupEnabled: Bool
    let cleanupIntervalMinutes: Int
    let clearDataOnBackground: Bool
    let maxTemporaryFileSize: UInt64
    let enablePrivacyLogging: Bool
    
    init(automaticCleanupEnabled: Bool = true,
         cleanupIntervalMinutes: Int = 30,
         clearDataOnBackground: Bool = true,
         maxTemporaryFileSize: UInt64 = 100 * 1024 * 1024, // 100MB
         enablePrivacyLogging: Bool = false) {
        self.automaticCleanupEnabled = automaticCleanupEnabled
        self.cleanupIntervalMinutes = cleanupIntervalMinutes
        self.clearDataOnBackground = clearDataOnBackground
        self.maxTemporaryFileSize = maxTemporaryFileSize
        self.enablePrivacyLogging = enablePrivacyLogging
    }
}

/// Privacy-related errors
enum PrivacyError: LocalizedError {
    case cleanupFailed(String)
    case permissionDenied(String)
    case temporaryFileCreationFailed
    case onDeviceProcessingViolation
    case networkActivityDetected
    
    var errorDescription: String? {
        switch self {
        case .cleanupFailed(let reason):
            return "Failed to cleanup temporary files: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied for \(permission)"
        case .temporaryFileCreationFailed:
            return "Failed to create temporary file"
        case .onDeviceProcessingViolation:
            return "On-device processing requirement violated"
        case .networkActivityDetected:
            return "Unexpected network activity detected during processing"
        }
    }
}

/// Delegate protocol for privacy manager events
protocol PrivacyManagerDelegate: AnyObject, Sendable {
    /// Called when automatic cleanup is performed
    func privacyManagerDidPerformCleanup(_ manager: PrivacyManagerProtocol, filesRemoved: Int, bytesFreed: UInt64)
    
    /// Called when app enters background and data is cleared
    func privacyManagerDidClearSensitiveData(_ manager: PrivacyManagerProtocol)
    
    /// Called when permission status changes
    func privacyManager(_ manager: PrivacyManagerProtocol, didUpdatePermissionStatus status: String)
    
    /// Called when privacy compliance issue is detected
    func privacyManager(_ manager: PrivacyManagerProtocol, didDetectComplianceIssue issue: String)
}