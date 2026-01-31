import Foundation
import AVFoundation
import Photos
import UIKit

/// Helper class for managing permissions with privacy-aware explanations
@MainActor
final class PermissionHelper: @unchecked Sendable {
    
    private let privacyManager: PrivacyManagerProtocol
    
    init(privacyManager: PrivacyManagerProtocol) {
        self.privacyManager = privacyManager
    }
    
    // MARK: - Camera Permission
    
    /// Requests camera permission with privacy-aware explanation
    func requestCameraPermissionWithExplanation() async -> Bool {
        let currentStatus = privacyManager.cameraPermissionStatus
        
        switch currentStatus {
        case .authorized:
            return true
            
        case .notDetermined:
            // Show explanation before requesting permission
            let shouldProceed = await showCameraPermissionExplanation()
            guard shouldProceed else { return false }
            
            return await privacyManager.requestCameraPermission()
            
        case .denied, .restricted:
            // Show settings guidance
            await showCameraPermissionDeniedAlert()
            return false
            
        @unknown default:
            return false
        }
    }
    
    /// Shows camera permission explanation dialog
    private func showCameraPermissionExplanation() async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Camera Access Required",
                message: PrivacyManager.cameraPermissionExplanation,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            presentAlert(alert)
        }
    }
    
    /// Shows camera permission denied alert with settings guidance
    private func showCameraPermissionDeniedAlert() async {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Camera Access Denied",
                message: "EdgeTAM needs camera access for video processing. All processing happens on your device for privacy.\n\n" + PrivacyManager.cameraPermissionExplanation,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
                continuation.resume()
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume()
            })
            
            presentAlert(alert)
        }
    }
    
    // MARK: - Photo Library Permission
    
    /// Requests photo library permission with privacy-aware explanation
    func requestPhotoLibraryPermissionWithExplanation() async -> PHAuthorizationStatus {
        let currentStatus = privacyManager.photoLibraryPermissionStatus
        
        switch currentStatus {
        case .authorized, .limited:
            return currentStatus
            
        case .notDetermined:
            // Show explanation before requesting permission
            let shouldProceed = await showPhotoLibraryPermissionExplanation()
            guard shouldProceed else { return currentStatus }
            
            return await privacyManager.requestPhotoLibraryPermission()
            
        case .denied, .restricted:
            // Show settings guidance
            await showPhotoLibraryPermissionDeniedAlert()
            return currentStatus
            
        @unknown default:
            return currentStatus
        }
    }
    
    /// Shows photo library permission explanation dialog
    private func showPhotoLibraryPermissionExplanation() async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Photo Library Access",
                message: PrivacyManager.photoLibraryPermissionExplanation,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            
            presentAlert(alert)
        }
    }
    
    /// Shows photo library permission denied alert with settings guidance
    private func showPhotoLibraryPermissionDeniedAlert() async {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Photo Library Access Denied",
                message: "EdgeTAM needs photo library access to save your processed videos.\n\n" + PrivacyManager.photoLibraryPermissionExplanation,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
                continuation.resume()
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume()
            })
            
            presentAlert(alert)
        }
    }
    
    // MARK: - Privacy Status Check
    
    /// Checks if all required permissions are granted
    func checkAllPermissions() -> PermissionStatus {
        let cameraStatus = privacyManager.cameraPermissionStatus
        let photoStatus = privacyManager.photoLibraryPermissionStatus
        
        let cameraGranted = cameraStatus == .authorized
        let photoGranted = photoStatus == .authorized || photoStatus == .limited
        
        return PermissionStatus(
            cameraGranted: cameraGranted,
            photoLibraryGranted: photoGranted,
            allRequiredGranted: cameraGranted // Photo library is optional for basic functionality
        )
    }
    
    /// Shows privacy compliance status
    func showPrivacyComplianceStatus() async {
        let status = privacyManager.privacyComplianceStatus
        
        let message = """
        Privacy Compliance Status:
        
        ✓ On-device processing: \(status.isOnDeviceProcessingActive ? "Active" : "Inactive")
        \(status.hasTemporaryFiles ? "⚠" : "✓") Temporary files: \(status.hasTemporaryFiles ? "Present" : "None")
        \(status.lastCleanupTime != nil ? "✓" : "⚠") Last cleanup: \(status.lastCleanupTime?.formatted() ?? "Never")
        \(status.networkActivityDetected ? "⚠" : "✓") Network activity: \(status.networkActivityDetected ? "Detected" : "None")
        
        Overall: \(status.isCompliant ? "✓ Compliant" : "⚠ Issues detected")
        """
        
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Privacy Status",
                message: message,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            
            presentAlert(alert)
        }
    }
    
    // MARK: - Helper Methods
    
    private func presentAlert(_ alert: UIAlertController) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        // Find the topmost view controller
        var topViewController = rootViewController
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        topViewController.present(alert, animated: true)
    }
}

// MARK: - Supporting Types

/// Permission status information
struct PermissionStatus: Sendable {
    let cameraGranted: Bool
    let photoLibraryGranted: Bool
    let allRequiredGranted: Bool
    
    var hasAllOptionalPermissions: Bool {
        return cameraGranted && photoLibraryGranted
    }
}