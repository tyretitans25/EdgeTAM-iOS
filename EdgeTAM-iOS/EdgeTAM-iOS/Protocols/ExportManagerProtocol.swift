import Foundation
import AVFoundation
import CoreVideo

/// Export progress information
struct ExportProgress: Sendable {
    let progress: Float // 0.0 to 1.0
    let currentFrame: Int
    let totalFrames: Int
    let estimatedTimeRemaining: TimeInterval
    let exportedDuration: TimeInterval
    let totalDuration: TimeInterval
}

/// Export result information
struct ExportResult: Sendable {
    let success: Bool
    let outputURL: URL?
    let error: EdgeTAMError?
    let exportDuration: TimeInterval
    let outputFileSize: Int64
    let processedFrames: Int
}

/// Protocol for video export functionality
protocol ExportManagerProtocol: AnyObject {
    /// Delegate for export progress and completion
    var delegate: ExportManagerDelegate? { get set }
    
    /// Current export progress (nil if not exporting)
    var currentProgress: ExportProgress? { get }
    
    /// Whether an export is currently in progress
    var isExporting: Bool { get }
    
    /// Start exporting video with applied segmentation masks
    func exportVideo(frames: [ProcessedFrame], 
                    configuration: ExportConfiguration) async throws -> ExportResult
    
    /// Cancel current export operation
    func cancelExport()
    
    /// Get estimated export time for given frames and configuration
    func estimateExportTime(frameCount: Int, configuration: ExportConfiguration) -> TimeInterval
    
    /// Validate export configuration
    func validateConfiguration(_ configuration: ExportConfiguration) throws
}

/// Delegate for export manager events
protocol ExportManagerDelegate: AnyObject {
    /// Called when export progress is updated
    func exportManager(_ manager: ExportManagerProtocol, didUpdateProgress progress: ExportProgress)
    
    /// Called when export completes successfully
    func exportManager(_ manager: ExportManagerProtocol, didCompleteExport result: ExportResult)
    
    /// Called when export fails
    func exportManager(_ manager: ExportManagerProtocol, didFailWithError error: EdgeTAMError)
    
    /// Called when export is cancelled
    func exportManagerDidCancelExport(_ manager: ExportManagerProtocol)
}