import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import os.log
import UIKit

/// Implementation of video export functionality with segmentation mask overlay
final class ExportManager: NSObject, ExportManagerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Delegate for export events
    weak var delegate: ExportManagerDelegate?
    
    /// Privacy manager for temporary file handling
    private let privacyManager: PrivacyManagerProtocol?
    
    /// Current export progress
    private(set) var currentProgress: ExportProgress?
    
    /// Whether an export is currently in progress
    private(set) var isExporting: Bool = false
    
    /// Logger for export operations
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "ExportManager")
    
    /// Export session for video processing
    private var exportSession: AVAssetExportSession?
    
    /// Asset writer for custom video processing
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    /// Export cancellation flag
    private var isCancelled: Bool = false
    
    /// Temporary files created during export
    private var temporaryFiles: Set<URL> = []
    
    /// Core Image context for mask rendering
    private lazy var ciContext: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ]
        return CIContext(options: options)
    }()
    
    // MARK: - Initialization
    
    init(privacyManager: PrivacyManagerProtocol? = nil) {
        self.privacyManager = privacyManager
        super.init()
        logger.info("ExportManager initialized with privacy manager: \(privacyManager != nil)")
    }
    
    override init() {
        self.privacyManager = nil
        super.init()
        logger.info("ExportManager initialized without privacy manager")
    }
    
    deinit {
        cleanup()
        logger.info("ExportManager deinitialized")
    }
    
    // MARK: - ExportManagerProtocol Methods
    
    func exportVideo(frames: [ProcessedFrame], configuration: ExportConfiguration) async throws -> ExportResult {
        guard !isExporting else {
            throw EdgeTAMError.invalidState("Export already in progress")
        }
        
        logger.info("Starting video export with \(frames.count) frames")
        
        // Validate configuration
        try validateConfiguration(configuration)
        
        // Validate frames
        guard !frames.isEmpty else {
            throw EdgeTAMError.exportFailed("No frames provided for export")
        }
        
        isExporting = true
        isCancelled = false
        currentProgress = ExportProgress(
            progress: 0.0,
            currentFrame: 0,
            totalFrames: frames.count,
            estimatedTimeRemaining: estimateExportTime(frameCount: frames.count, configuration: configuration),
            exportedDuration: 0.0,
            totalDuration: calculateTotalDuration(frames: frames)
        )
        
        let startTime = Date()
        
        do {
            let result = try await performExport(frames: frames, configuration: configuration)
            
            let exportDuration = Date().timeIntervalSince(startTime)
            let finalResult = ExportResult(
                success: result.success,
                outputURL: result.outputURL,
                error: result.error,
                exportDuration: exportDuration,
                outputFileSize: getFileSize(at: result.outputURL),
                processedFrames: frames.count
            )
            
            isExporting = false
            currentProgress = nil
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.exportManager(self, didCompleteExport: finalResult)
            }
            
            logger.info("Export completed successfully in \(exportDuration) seconds")
            return finalResult
            
        } catch {
            isExporting = false
            currentProgress = nil
            
            let edgeTAMError = EdgeTAMError.from(error)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.exportManager(self, didFailWithError: edgeTAMError)
            }
            
            logger.error("Export failed: \(edgeTAMError.localizedDescription)")
            throw edgeTAMError
        }
    }
    
    func cancelExport() {
        guard isExporting else { return }
        
        logger.info("Cancelling export")
        isCancelled = true
        
        exportSession?.cancelExport()
        assetWriter?.cancelWriting()
        
        cleanup()
        
        isExporting = false
        currentProgress = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.exportManagerDidCancelExport(self)
        }
    }
    
    func estimateExportTime(frameCount: Int, configuration: ExportConfiguration) -> TimeInterval {
        // Rough estimation based on frame count and quality
        let baseTimePerFrame: TimeInterval = 0.1 // 100ms per frame base time
        let qualityMultiplier: Double
        
        switch configuration.videoQuality {
        case .low:
            qualityMultiplier = 0.5
        case .medium:
            qualityMultiplier = 1.0
        case .high:
            qualityMultiplier = 1.5
        case .original:
            qualityMultiplier = 2.0
        }
        
        return Double(frameCount) * baseTimePerFrame * qualityMultiplier
    }
    
    func validateConfiguration(_ configuration: ExportConfiguration) throws {
        // Check output URL
        let outputDirectory = configuration.outputURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: outputDirectory.path) else {
            throw EdgeTAMError.exportFailed("Output directory is not writable")
        }
        
        // Check file extension
        let pathExtension = configuration.outputURL.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(pathExtension) else {
            throw EdgeTAMError.exportFailed("Unsupported output format: \(pathExtension)")
        }
        
        // Check frame rate if compression settings are provided
        if let compressionSettings = configuration.compressionSettings {
            guard compressionSettings.frameRate > 0 && compressionSettings.frameRate <= 120 else {
                throw EdgeTAMError.exportFailed("Invalid frame rate: \(compressionSettings.frameRate)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performExport(frames: [ProcessedFrame], configuration: ExportConfiguration) async throws -> ExportResult {
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: configuration.outputURL.path) {
            try FileManager.default.removeItem(at: configuration.outputURL)
        }
        
        // Set up asset writer
        try setupAssetWriter(configuration: configuration, frames: frames)
        
        guard let assetWriter = assetWriter,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            throw EdgeTAMError.exportFailed("Failed to setup asset writer")
        }
        
        // Start writing
        guard assetWriter.startWriting() else {
            throw EdgeTAMError.exportFailed("Failed to start writing: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        // Process frames
        try await processFrames(frames: frames, 
                              videoInput: videoInput, 
                              pixelBufferAdaptor: pixelBufferAdaptor,
                              configuration: configuration)
        
        // Finish writing
        videoInput.markAsFinished()
        
        await assetWriter.finishWriting()
        
        guard assetWriter.status == .completed else {
            let error = assetWriter.error ?? EdgeTAMError.exportFailed("Export failed with unknown error")
            throw EdgeTAMError.from(error)
        }
        
        return ExportResult(
            success: true,
            outputURL: configuration.outputURL,
            error: nil,
            exportDuration: 0, // Will be calculated by caller
            outputFileSize: getFileSize(at: configuration.outputURL),
            processedFrames: frames.count
        )
    }
    
    private func setupAssetWriter(configuration: ExportConfiguration, frames: [ProcessedFrame]) throws {
        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: configuration.outputURL, fileType: .mp4)
        
        guard let assetWriter = assetWriter else {
            throw EdgeTAMError.exportFailed("Failed to create asset writer")
        }
        
        // Determine video dimensions from first frame
        let firstFrame = frames.first!
        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(firstFrame.pixelBuffer),
            height: CVPixelBufferGetHeight(firstFrame.pixelBuffer)
        )
        
        // Video output settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(frameSize.width),
            AVVideoHeightKey: Int(frameSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculateBitRate(for: frameSize, quality: configuration.videoQuality),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
            ]
        ]
        
        // Create video input
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = false
        
        // Create pixel buffer adaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(frameSize.width),
            kCVPixelBufferHeightKey as String: Int(frameSize.height)
        ]
        
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        // Add input to writer
        guard let videoInput = videoInput, assetWriter.canAdd(videoInput) else {
            throw EdgeTAMError.exportFailed("Cannot add video input to asset writer")
        }
        
        assetWriter.add(videoInput)
    }
    
    private func processFrames(frames: [ProcessedFrame], 
                             videoInput: AVAssetWriterInput,
                             pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
                             configuration: ExportConfiguration) async throws {
        
        // Use frame rate from compression settings or default to 30 fps
        let frameRate = configuration.compressionSettings?.frameRate ?? 30
        let frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        var presentationTime = CMTime.zero
        
        for (index, frame) in frames.enumerated() {
            // Check for cancellation
            if isCancelled {
                throw EdgeTAMError.exportCancelled
            }
            
            // Wait for input to be ready
            while !videoInput.isReadyForMoreMediaData {
                if isCancelled {
                    throw EdgeTAMError.exportCancelled
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Create output pixel buffer with masks applied
            guard let outputPixelBuffer = try await createOutputPixelBuffer(
                from: frame,
                adaptor: pixelBufferAdaptor
            ) else {
                throw EdgeTAMError.exportFailed("Failed to create output pixel buffer for frame \(index)")
            }
            
            // Append pixel buffer
            guard pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) else {
                throw EdgeTAMError.exportFailed("Failed to append pixel buffer for frame \(index)")
            }
            
            presentationTime = CMTimeAdd(presentationTime, frameDuration)
            
            // Update progress
            let progress = Float(index + 1) / Float(frames.count)
            let estimatedTimeRemaining = estimateExportTime(frameCount: frames.count - index - 1, configuration: configuration)
            
            currentProgress = ExportProgress(
                progress: progress,
                currentFrame: index + 1,
                totalFrames: frames.count,
                estimatedTimeRemaining: estimatedTimeRemaining,
                exportedDuration: CMTimeGetSeconds(presentationTime),
                totalDuration: calculateTotalDuration(frames: frames)
            )
            
            // Notify delegate on main queue
            if let progress = currentProgress {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.exportManager(self, didUpdateProgress: progress)
                }
            }
        }
    }
    
    private func createOutputPixelBuffer(from frame: ProcessedFrame, 
                                       adaptor: AVAssetWriterInputPixelBufferAdaptor) async throws -> CVPixelBuffer? {
        
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw EdgeTAMError.exportFailed("No pixel buffer pool available")
        }
        
        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &outputPixelBuffer)
        
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            throw EdgeTAMError.exportFailed("Failed to create output pixel buffer")
        }
        
        // Convert input pixel buffer to CIImage
        let inputImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        
        // Apply segmentation masks if available
        let finalImage: CIImage
        if !frame.segmentationMasks.isEmpty {
            finalImage = try applySegmentationMasks(to: inputImage, masks: frame.segmentationMasks)
        } else {
            finalImage = inputImage
        }
        
        // Render to output pixel buffer
        ciContext.render(finalImage, to: outputBuffer)
        
        return outputBuffer
    }
    
    private func applySegmentationMasks(to image: CIImage, masks: [SegmentationMask]) throws -> CIImage {
        var compositeImage = image
        
        for (index, mask) in masks.enumerated() {
            // Create mask image from pixel buffer
            let maskImage = CIImage(cvPixelBuffer: mask.maskBuffer)
            
            // Create colored overlay
            let color = getColorForMask(index: index)
            let colorImage = CIImage(color: CIColor(color: color))
                .cropped(to: image.extent)
            
            // Apply mask to color
            let maskedColor = colorImage.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: maskImage
            ])
            
            // Blend with composite image
            compositeImage = maskedColor.composited(over: compositeImage)
        }
        
        return compositeImage
    }
    
    private func getColorForMask(index: Int) -> UIColor {
        let colors: [UIColor] = [
            .systemRed.withAlphaComponent(0.6),
            .systemBlue.withAlphaComponent(0.6),
            .systemGreen.withAlphaComponent(0.6),
            .systemYellow.withAlphaComponent(0.6),
            .systemPurple.withAlphaComponent(0.6),
            .systemOrange.withAlphaComponent(0.6)
        ]
        return colors[index % colors.count]
    }
    
    private func calculateBitRate(for size: CGSize, quality: VideoQuality) -> Int {
        let pixelCount = size.width * size.height
        let baseBitRate = Int(pixelCount * 0.1) // Base bit rate
        
        switch quality {
        case .low:
            return baseBitRate / 2
        case .medium:
            return baseBitRate
        case .high:
            return baseBitRate * 2
        case .original:
            return baseBitRate * 3
        }
    }
    
    private func calculateTotalDuration(frames: [ProcessedFrame]) -> TimeInterval {
        guard !frames.isEmpty else { return 0 }
        
        // Assume 30 FPS for duration calculation
        return Double(frames.count) / 30.0
    }
    
    private func getFileSize(at url: URL?) -> Int64 {
        guard let url = url else { return 0 }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            logger.error("Failed to get file size: \(error.localizedDescription)")
            return 0
        }
    }
    
    private func cleanup() {
        exportSession = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
    }
    
    // MARK: - Privacy-Aware Temporary File Management
    
    /// Creates a temporary file URL for export processing
    private func createTemporaryFileURL(withExtension ext: String) -> URL {
        if let privacyManager = privacyManager {
            return privacyManager.createTemporaryFileURL(withExtension: ext)
        } else {
            // Fallback to system temporary directory
            let fileName = UUID().uuidString + "." + ext
            return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }
    
    /// Tracks a temporary file for automatic cleanup
    private func trackTemporaryFile(_ url: URL) {
        temporaryFiles.insert(url)
        privacyManager?.trackTemporaryFile(url)
        logger.debug("Tracking temporary file: \(url.lastPathComponent)")
    }
    
    /// Cleans up temporary files created during export
    private func cleanupTemporaryFiles() async {
        logger.info("Cleaning up \(self.temporaryFiles.count) temporary files from export")
        
        for fileURL in self.temporaryFiles {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.debug("Removed temporary file: \(fileURL.lastPathComponent)")
                }
            } catch {
                logger.error("Failed to remove temporary file \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        temporaryFiles.removeAll()
        
        // Also trigger privacy manager cleanup if available
        if let privacyManager = privacyManager {
            try? await privacyManager.cleanupTemporaryFiles()
        }
    }
}