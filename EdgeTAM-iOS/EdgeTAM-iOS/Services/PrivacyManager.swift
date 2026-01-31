import Foundation
import AVFoundation
import Photos
import UIKit
import OSLog

/// Privacy manager implementation that handles data protection and cleanup
final class PrivacyManager: NSObject, PrivacyManagerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "PrivacyManager")
    private let fileManager = FileManager.default
    private let notificationCenter = NotificationCenter.default
    
    /// Delegate for privacy manager events
    weak var delegate: PrivacyManagerDelegate?
    
    /// Privacy configuration settings
    var privacySettings: PrivacySettings {
        didSet {
            Task {
                await updatePrivacySettings(privacySettings)
            }
        }
    }
    
    /// Tracked temporary files for cleanup
    private var trackedTemporaryFiles: Set<URL> = []
    
    /// Timer for automatic cleanup
    private var cleanupTimer: Timer?
    
    /// Flag indicating if processing is currently paused
    private var isProcessingPaused: Bool = false
    
    /// Last cleanup timestamp
    private var lastCleanupTime: Date?
    
    /// Network activity monitor (placeholder for actual implementation)
    private var networkActivityDetected: Bool = false
    
    // MARK: - Initialization
    
    init(privacySettings: PrivacySettings = PrivacySettings()) {
        self.privacySettings = privacySettings
        super.init()
        
        setupNotificationObservers()
        setupAutomaticCleanup()
        
        logger.info("PrivacyManager initialized with settings: \(String(describing: privacySettings))")
    }
    
    deinit {
        cleanupTimer?.invalidate()
        notificationCenter.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupNotificationObservers() {
        // App lifecycle notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Memory warning notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    private func setupAutomaticCleanup() {
        guard privacySettings.automaticCleanupEnabled else { return }
        
        let interval = TimeInterval(privacySettings.cleanupIntervalMinutes * 60)
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.cleanupTemporaryFiles()
            }
        }
    }
    
    // MARK: - Data Cleanup
    
    func cleanupTemporaryFiles() async throws {
        logger.info("Starting automatic cleanup of temporary files")
        
        let tempDir = temporaryDirectory
        var filesRemoved = 0
        var bytesFreed: UInt64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey], options: [])
            
            for fileURL in contents {
                // Check if file is in our tracked files or is old enough to clean
                var shouldRemove = trackedTemporaryFiles.contains(fileURL)
                if !shouldRemove {
                    shouldRemove = await isFileOldEnoughToClean(fileURL)
                }
                
                if shouldRemove {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                        let fileSize = attributes[.size] as? UInt64 ?? 0
                        
                        try fileManager.removeItem(at: fileURL)
                        trackedTemporaryFiles.remove(fileURL)
                        
                        filesRemoved += 1
                        bytesFreed += fileSize
                        
                        logger.debug("Removed temporary file: \(fileURL.lastPathComponent), size: \(fileSize) bytes")
                    } catch {
                        logger.error("Failed to remove temporary file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            
            lastCleanupTime = Date()
            
            if filesRemoved > 0 {
                logger.info("Cleanup completed: removed \(filesRemoved) files, freed \(bytesFreed) bytes")
                delegate?.privacyManagerDidPerformCleanup(self, filesRemoved: filesRemoved, bytesFreed: bytesFreed)
            }
            
        } catch {
            logger.error("Failed to cleanup temporary files: \(error.localizedDescription)")
            throw PrivacyError.cleanupFailed(error.localizedDescription)
        }
    }
    
    func clearSensitiveDataFromMemory() async {
        logger.info("Clearing sensitive data from memory")
        
        // Clear tracked temporary files set
        trackedTemporaryFiles.removeAll()
        
        // Force garbage collection (this is a hint to the system)
        autoreleasepool {
            // Any objects created here will be released
        }
        
        delegate?.privacyManagerDidClearSensitiveData(self)
        logger.info("Sensitive data cleared from memory")
    }
    
    func clearProcessedData() async {
        logger.info("Clearing all processed data")
        
        // Clear temporary files
        try? await cleanupTemporaryFiles()
        
        // Clear memory
        await clearSensitiveDataFromMemory()
        
        logger.info("All processed data cleared")
    }
    
    // MARK: - Background/Foreground Handling
    
    func handleAppDidEnterBackground() async {
        logger.info("App entered background - initiating privacy protection")
        
        if privacySettings.clearDataOnBackground {
            await pauseProcessingAndClearData()
        }
        
        // Perform immediate cleanup
        try? await cleanupTemporaryFiles()
        
        logger.info("Background privacy protection completed")
    }
    
    func handleAppWillEnterForeground() async {
        logger.info("App entering foreground - resuming operations")
        
        if isProcessingPaused {
            try? await resumeProcessing()
        }
        
        logger.info("Foreground operations resumed")
    }
    
    func pauseProcessingAndClearData() async {
        logger.info("Pausing processing and clearing sensitive data")
        
        isProcessingPaused = true
        
        // Clear sensitive data from memory
        await clearSensitiveDataFromMemory()
        
        // Post notification to other components to pause processing
        notificationCenter.post(name: .privacyManagerDidPauseProcessing, object: self)
        
        logger.info("Processing paused and data cleared")
    }
    
    func resumeProcessing() async throws {
        logger.info("Resuming processing after foreground transition")
        
        // Validate on-device processing before resuming
        guard validateOnDeviceProcessing() else {
            throw PrivacyError.onDeviceProcessingViolation
        }
        
        isProcessingPaused = false
        
        // Post notification to other components to resume processing
        notificationCenter.post(name: .privacyManagerDidResumeProcessing, object: self)
        
        logger.info("Processing resumed successfully")
    }
    
    // MARK: - Permission Management
    
    func requestCameraPermission() async -> Bool {
        logger.info("Requesting camera permission")
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            logger.info("Camera permission already granted")
            return true
            
        case .notDetermined:
            logger.info("Camera permission not determined, requesting...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            
            if granted {
                logger.info("Camera permission granted")
                delegate?.privacyManager(self, didUpdatePermissionStatus: "Camera permission granted")
            } else {
                logger.warning("Camera permission denied by user")
                delegate?.privacyManager(self, didUpdatePermissionStatus: "Camera permission denied")
            }
            
            return granted
            
        case .denied, .restricted:
            logger.warning("Camera permission denied or restricted")
            delegate?.privacyManager(self, didUpdatePermissionStatus: "Camera permission denied or restricted")
            return false
            
        @unknown default:
            logger.error("Unknown camera permission status")
            return false
        }
    }
    
    func requestPhotoLibraryPermission() async -> PHAuthorizationStatus {
        logger.info("Requesting photo library permission")
        
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            logger.info("Photo library permission already granted")
            return status
            
        case .notDetermined:
            logger.info("Photo library permission not determined, requesting...")
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            
            switch newStatus {
            case .authorized, .limited:
                logger.info("Photo library permission granted")
                delegate?.privacyManager(self, didUpdatePermissionStatus: "Photo library permission granted")
            case .denied, .restricted:
                logger.warning("Photo library permission denied")
                delegate?.privacyManager(self, didUpdatePermissionStatus: "Photo library permission denied")
            default:
                break
            }
            
            return newStatus
            
        case .denied, .restricted:
            logger.warning("Photo library permission denied or restricted")
            delegate?.privacyManager(self, didUpdatePermissionStatus: "Photo library permission denied or restricted")
            return status
            
        @unknown default:
            logger.error("Unknown photo library permission status")
            return status
        }
    }
    
    var cameraPermissionStatus: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    var photoLibraryPermissionStatus: PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }
    
    // MARK: - On-Device Processing Guarantees
    
    var isOnDeviceProcessingEnabled: Bool {
        // Always true for EdgeTAM - all processing is on-device
        return true
    }
    
    func validateOnDeviceProcessing() -> Bool {
        // Check for any network activity during processing
        if networkActivityDetected {
            logger.error("Network activity detected during processing - privacy violation")
            delegate?.privacyManager(self, didDetectComplianceIssue: "Network activity detected during processing")
            return false
        }
        
        // Validate that CoreML is using on-device compute units
        // This would be implemented with actual model configuration checks
        
        logger.info("On-device processing validation passed")
        return true
    }
    
    var privacyComplianceStatus: PrivacyComplianceStatus {
        return PrivacyComplianceStatus(
            isOnDeviceProcessingActive: isOnDeviceProcessingEnabled,
            hasTemporaryFiles: !trackedTemporaryFiles.isEmpty,
            lastCleanupTime: lastCleanupTime,
            memoryContainsSensitiveData: !trackedTemporaryFiles.isEmpty,
            networkActivityDetected: networkActivityDetected
        )
    }
    
    // MARK: - Temporary File Management
    
    var temporaryDirectory: URL {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("EdgeTAM", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return tempDir
    }
    
    func createTemporaryFileURL(withExtension ext: String) -> URL {
        let fileName = UUID().uuidString + "." + ext
        return temporaryDirectory.appendingPathComponent(fileName)
    }
    
    func trackTemporaryFile(_ url: URL) {
        trackedTemporaryFiles.insert(url)
        logger.debug("Tracking temporary file: \(url.lastPathComponent)")
        
        // Check if we're approaching the size limit
        Task {
            let currentSize = await getTemporaryFilesSize()
            if currentSize > self.privacySettings.maxTemporaryFileSize {
                logger.warning("Temporary files size (\(currentSize) bytes) exceeds limit (\(self.privacySettings.maxTemporaryFileSize) bytes)")
                try? await cleanupTemporaryFiles()
            }
        }
    }
    
    func getTemporaryFilesSize() async -> UInt64 {
        var totalSize: UInt64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [])
            
            for fileURL in contents {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                totalSize += fileSize
            }
        } catch {
            logger.error("Failed to calculate temporary files size: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    // MARK: - Privacy Settings
    
    func updatePrivacySettings(_ settings: PrivacySettings) async {
        logger.info("Updating privacy settings")
        
        // Update automatic cleanup timer if interval changed
        if settings.cleanupIntervalMinutes != privacySettings.cleanupIntervalMinutes {
            cleanupTimer?.invalidate()
            setupAutomaticCleanup()
        }
        
        // Perform immediate cleanup if automatic cleanup was enabled
        if settings.automaticCleanupEnabled && !privacySettings.automaticCleanupEnabled {
            try? await cleanupTemporaryFiles()
        }
        
        logger.info("Privacy settings updated successfully")
    }
    
    // MARK: - Private Helpers
    
    private func isFileOldEnoughToClean(_ fileURL: URL) async -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                let ageInMinutes = Date().timeIntervalSince(creationDate) / 60
                return ageInMinutes > Double(privacySettings.cleanupIntervalMinutes)
            }
        } catch {
            logger.error("Failed to get file attributes for \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        
        return false
    }
    
    // MARK: - Notification Handlers
    
    @objc private func appDidEnterBackground() {
        Task {
            await handleAppDidEnterBackground()
        }
    }
    
    @objc private func appWillEnterForeground() {
        Task {
            await handleAppWillEnterForeground()
        }
    }
    
    @objc private func appWillTerminate() {
        Task {
            await clearProcessedData()
        }
    }
    
    @objc private func didReceiveMemoryWarning() {
        Task {
            try? await cleanupTemporaryFiles()
            await clearSensitiveDataFromMemory()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let privacyManagerDidPauseProcessing = Notification.Name("PrivacyManagerDidPauseProcessing")
    static let privacyManagerDidResumeProcessing = Notification.Name("PrivacyManagerDidResumeProcessing")
}

// MARK: - Permission Helper Extensions

extension PrivacyManager {
    
    /// Returns user-friendly explanation for camera permission
    static var cameraPermissionExplanation: String {
        return """
        EdgeTAM needs camera access to capture video for real-time object tracking and segmentation. 
        All video processing happens on your device - no data is sent to external servers.
        
        To enable camera access:
        1. Go to Settings > Privacy & Security > Camera
        2. Find EdgeTAM in the list
        3. Toggle the switch to enable camera access
        """
    }
    
    /// Returns user-friendly explanation for photo library permission
    static var photoLibraryPermissionExplanation: String {
        return """
        EdgeTAM needs photo library access to save your processed videos with object tracking overlays.
        Only videos you explicitly choose to export will be saved to your photo library.
        
        To enable photo library access:
        1. Go to Settings > Privacy & Security > Photos
        2. Find EdgeTAM in the list
        3. Select "Add Photos Only" or "All Photos"
        """
    }
}