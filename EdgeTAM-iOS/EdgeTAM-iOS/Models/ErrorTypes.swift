import Foundation

/// Comprehensive error types for the EdgeTAM iOS application
enum EdgeTAMError: LocalizedError, Equatable {
    // MARK: - Camera Errors
    case cameraPermissionDenied
    case cameraInitializationFailed(String)
    case cameraDeviceNotAvailable
    case cameraSwitchingFailed(String)
    case cameraSessionInterrupted
    
    // MARK: - Model Errors
    case modelLoadingFailed(String)
    case modelNotFound(String)
    case modelIncompatible(String)
    case inferenceTimeout
    case inferenceFailure(String)
    case modelMemoryExhausted
    
    // MARK: - Processing Errors
    case frameProcessingFailed(String)
    case invalidPixelBuffer
    case segmentationFailed(String)
    case trackingFailed(String)
    case renderingFailed(String)
    
    // MARK: - Resource Errors
    case memoryPressure
    case thermalThrottling
    case batteryLow
    case diskSpaceFull
    case networkUnavailable
    
    // MARK: - Export Errors
    case exportFailed(String)
    case exportCancelled
    case exportPermissionDenied
    case exportInvalidConfiguration
    case exportInsufficientSpace
    
    // MARK: - Prompt Errors
    case invalidPrompt(String)
    case promptLimitExceeded
    case promptValidationFailed(PromptValidationError)
    
    // MARK: - Configuration Errors
    case invalidConfiguration(String)
    case unsupportedDevice
    case unsupportedIOSVersion
    case missingFramework(String)
    
    // MARK: - Generic Errors
    case unknown(String)
    case operationCancelled
    case timeout
    case invalidState(String)
    
    var errorDescription: String? {
        switch self {
        // Camera Errors
        case .cameraPermissionDenied:
            return "Camera access is required for video processing. Please enable camera permissions in Settings."
        case .cameraInitializationFailed(let reason):
            return "Failed to initialize camera: \(reason)"
        case .cameraDeviceNotAvailable:
            return "Camera device is not available. Please check if another app is using the camera."
        case .cameraSwitchingFailed(let reason):
            return "Failed to switch camera: \(reason)"
        case .cameraSessionInterrupted:
            return "Camera session was interrupted. Please try again."
            
        // Model Errors
        case .modelLoadingFailed(let reason):
            return "Failed to load EdgeTAM model: \(reason)"
        case .modelNotFound(let modelName):
            return "EdgeTAM model '\(modelName)' not found in app bundle"
        case .modelIncompatible(let reason):
            return "EdgeTAM model is incompatible with this device: \(reason)"
        case .inferenceTimeout:
            return "Model inference timed out. Please try again."
        case .inferenceFailure(let reason):
            return "Model inference failed: \(reason)"
        case .modelMemoryExhausted:
            return "Insufficient memory to run EdgeTAM model. Please close other apps and try again."
            
        // Processing Errors
        case .frameProcessingFailed(let reason):
            return "Frame processing failed: \(reason)"
        case .invalidPixelBuffer:
            return "Invalid video frame format. Please check camera settings."
        case .segmentationFailed(let reason):
            return "Video segmentation failed: \(reason)"
        case .trackingFailed(let reason):
            return "Object tracking failed: \(reason)"
        case .renderingFailed(let reason):
            return "Mask rendering failed: \(reason)"
            
        // Resource Errors
        case .memoryPressure:
            return "Low memory detected. Processing quality has been reduced to maintain performance."
        case .thermalThrottling:
            return "Device is overheating. Processing has been throttled to prevent damage."
        case .batteryLow:
            return "Battery level is low. Some features may be disabled to conserve power."
        case .diskSpaceFull:
            return "Insufficient storage space. Please free up space and try again."
        case .networkUnavailable:
            return "Network connection is not available."
            
        // Export Errors
        case .exportFailed(let reason):
            return "Video export failed: \(reason)"
        case .exportCancelled:
            return "Video export was cancelled by user."
        case .exportPermissionDenied:
            return "Permission to save to photo library is required. Please enable in Settings."
        case .exportInvalidConfiguration:
            return "Invalid export configuration. Please check export settings."
        case .exportInsufficientSpace:
            return "Insufficient storage space for video export."
            
        // Prompt Errors
        case .invalidPrompt(let reason):
            return "Invalid prompt: \(reason)"
        case .promptLimitExceeded:
            return "Maximum number of prompts exceeded. Please remove some prompts and try again."
        case .promptValidationFailed(let validationError):
            return validationError.errorDescription ?? "Prompt validation failed"
            
        // Configuration Errors
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .unsupportedDevice:
            return "This device is not supported. EdgeTAM requires iPhone 15 Pro Max or newer."
        case .unsupportedIOSVersion:
            return "This iOS version is not supported. Please update to iOS 17.0 or later."
        case .missingFramework(let framework):
            return "Required framework '\(framework)' is not available on this device."
            
        // Generic Errors
        case .unknown(let reason):
            return "An unknown error occurred: \(reason)"
        case .operationCancelled:
            return "Operation was cancelled."
        case .timeout:
            return "Operation timed out. Please try again."
        case .invalidState(let reason):
            return "Invalid application state: \(reason)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera permissions are required for video capture and processing."
        case .modelLoadingFailed:
            return "The EdgeTAM CoreML model could not be loaded into memory."
        case .memoryPressure:
            return "The device is running low on available memory."
        case .thermalThrottling:
            return "The device is overheating and needs to cool down."
        case .exportFailed:
            return "The video export process encountered an error."
        default:
            return nil
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Go to Settings > Privacy & Security > Camera and enable access for EdgeTAM."
        case .cameraDeviceNotAvailable:
            return "Close other camera apps and try again."
        case .modelLoadingFailed, .modelMemoryExhausted:
            return "Close other apps to free up memory, then restart EdgeTAM."
        case .memoryPressure:
            return "Close other apps to free up memory. Processing will resume automatically."
        case .thermalThrottling:
            return "Let your device cool down for a few minutes before continuing."
        case .batteryLow:
            return "Connect your device to a charger to enable full functionality."
        case .diskSpaceFull, .exportInsufficientSpace:
            return "Delete some files or photos to free up storage space."
        case .exportPermissionDenied:
            return "Go to Settings > Privacy & Security > Photos and enable access for EdgeTAM."
        case .promptLimitExceeded:
            return "Remove some existing prompts before adding new ones."
        case .unsupportedDevice:
            return "EdgeTAM requires a device with Neural Engine support."
        case .unsupportedIOSVersion:
            return "Update your device to iOS 17.0 or later."
        default:
            return "Please try the operation again."
        }
    }
    
    /// Returns true if this error is recoverable through user action
    var isRecoverable: Bool {
        switch self {
        case .cameraPermissionDenied, .exportPermissionDenied, .diskSpaceFull, 
             .exportInsufficientSpace, .batteryLow, .promptLimitExceeded,
             .cameraDeviceNotAvailable, .memoryPressure, .thermalThrottling:
            return true
        case .unsupportedDevice, .unsupportedIOSVersion, .modelNotFound:
            return false
        default:
            return true
        }
    }
    
    /// Returns true if this error should trigger automatic retry
    var shouldRetry: Bool {
        switch self {
        case .inferenceTimeout, .frameProcessingFailed, .networkUnavailable,
             .cameraSessionInterrupted, .timeout:
            return true
        case .cameraPermissionDenied, .unsupportedDevice, .modelNotFound,
             .exportPermissionDenied:
            return false
        default:
            return false
        }
    }
    
    /// Returns the appropriate retry delay in seconds
    var retryDelay: TimeInterval {
        switch self {
        case .inferenceTimeout, .frameProcessingFailed:
            return 1.0
        case .networkUnavailable:
            return 5.0
        case .cameraSessionInterrupted:
            return 2.0
        case .timeout:
            return 3.0
        default:
            return 0.0
        }
    }
    
    /// Returns the error category for analytics and logging
    var category: ErrorCategory {
        switch self {
        case .cameraPermissionDenied, .cameraInitializationFailed, 
             .cameraDeviceNotAvailable, .cameraSwitchingFailed, .cameraSessionInterrupted:
            return .camera
        case .modelLoadingFailed, .modelNotFound, .modelIncompatible, 
             .inferenceTimeout, .inferenceFailure, .modelMemoryExhausted:
            return .model
        case .frameProcessingFailed, .invalidPixelBuffer, .segmentationFailed, 
             .trackingFailed, .renderingFailed:
            return .processing
        case .memoryPressure, .thermalThrottling, .batteryLow, 
             .diskSpaceFull, .networkUnavailable:
            return .resource
        case .exportFailed, .exportCancelled, .exportPermissionDenied, 
             .exportInvalidConfiguration, .exportInsufficientSpace:
            return .export
        case .invalidPrompt, .promptLimitExceeded, .promptValidationFailed:
            return .prompt
        case .invalidConfiguration, .unsupportedDevice, .unsupportedIOSVersion, 
             .missingFramework:
            return .configuration
        case .unknown, .operationCancelled, .timeout, .invalidState:
            return .generic
        }
    }
}

/// Categories for error classification
enum ErrorCategory: String, CaseIterable {
    case camera = "Camera"
    case model = "Model"
    case processing = "Processing"
    case resource = "Resource"
    case export = "Export"
    case prompt = "Prompt"
    case configuration = "Configuration"
    case generic = "Generic"
}

// MARK: - Error Extensions

extension EdgeTAMError {
    /// Creates an EdgeTAMError from a generic Error
    static func from(_ error: Error) -> EdgeTAMError {
        if let edgeTAMError = error as? EdgeTAMError {
            return edgeTAMError
        } else {
            return .unknown(error.localizedDescription)
        }
    }
    
    /// Creates a user-friendly error message with recovery suggestions
    func userFriendlyMessage() -> String {
        var message = errorDescription ?? "An error occurred"
        
        if let suggestion = recoverySuggestion {
            message += "\n\n\(suggestion)"
        }
        
        return message
    }
}

// MARK: - Error Reporting

/// Protocol for error reporting and analytics
protocol ErrorReporting {
    func reportError(_ error: EdgeTAMError, context: [String: Any]?)
    func reportNonFatalError(_ error: EdgeTAMError, context: [String: Any]?)
}

/// Context information for error reporting
struct ErrorContext {
    let timestamp: Date
    let deviceModel: String
    let iOSVersion: String
    let appVersion: String
    let memoryUsage: UInt64
    let batteryLevel: Float
    let thermalState: ProcessInfo.ThermalState
    let activeFeatures: [String]
    
    @MainActor
    init() {
        self.timestamp = Date()
        self.deviceModel = UIDevice.current.model
        self.iOSVersion = UIDevice.current.systemVersion
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.memoryUsage = 0 // Would be populated by actual memory monitoring
        self.batteryLevel = UIDevice.current.batteryLevel
        self.thermalState = ProcessInfo.processInfo.thermalState
        self.activeFeatures = [] // Would be populated with currently active features
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "timestamp": timestamp.timeIntervalSince1970,
            "deviceModel": deviceModel,
            "iOSVersion": iOSVersion,
            "appVersion": appVersion,
            "memoryUsage": memoryUsage,
            "batteryLevel": batteryLevel,
            "thermalState": thermalState.rawValue,
            "activeFeatures": activeFeatures
        ]
    }
}

// MARK: - Import UIKit for device info
import UIKit