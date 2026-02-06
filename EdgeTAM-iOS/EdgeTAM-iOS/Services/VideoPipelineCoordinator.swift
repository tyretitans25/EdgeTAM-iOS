//
//  VideoPipelineCoordinator.swift
//  EdgeTAM-iOS
//
//  Coordinates the video processing pipeline by connecting camera frames
//  to the segmentation engine and rendering masks on screen
//

import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import os.log

/// Coordinates the flow of video frames from camera through segmentation to rendering
final class VideoPipelineCoordinator: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    nonisolated(unsafe) private let videoSegmentationEngine: VideoSegmentationEngineProtocol
    nonisolated(unsafe) private let promptHandler: PromptHandlerProtocol
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "VideoPipelineCoordinator")
    
    /// Frame processing queue
    private let processingQueue = DispatchQueue(label: "com.edgetam.pipeline.processing", qos: .userInitiated)
    
    /// Frame throttling
    private var lastProcessedFrameTime: CFAbsoluteTime = 0
    private let targetFrameInterval: CFAbsoluteTime = 1.0 / 30.0 // 30 FPS
    
    /// Processing state - using atomic operations for thread safety
    private let isProcessingEnabled = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    private let isCurrentlyProcessing = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
    
    /// Frame counter for debugging
    private var frameCounter: Int = 0
    
    // MARK: - Initialization
    
    init(videoSegmentationEngine: VideoSegmentationEngineProtocol,
         promptHandler: PromptHandlerProtocol) {
        self.videoSegmentationEngine = videoSegmentationEngine
        self.promptHandler = promptHandler
        
        // Initialize atomic flags
        self.isProcessingEnabled.initialize(to: false)
        self.isCurrentlyProcessing.initialize(to: false)
        
        super.init()
        
        logger.info("VideoPipelineCoordinator initialized")
    }
    
    deinit {
        // Clean up atomic flags
        isProcessingEnabled.deallocate()
        isCurrentlyProcessing.deallocate()
    }
    
    // MARK: - Public Methods
    
    /// Enable or disable frame processing
    func setProcessingEnabled(_ enabled: Bool) {
        isProcessingEnabled.pointee = enabled
        logger.info("Frame processing \(enabled ? "enabled" : "disabled")")
    }
    
    /// Check if processing is enabled
    func isProcessing() -> Bool {
        return isProcessingEnabled.pointee
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoPipelineCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Check if processing is enabled
        let shouldProcess = isProcessingEnabled.pointee
        let alreadyProcessing = isCurrentlyProcessing.pointee
        
        guard shouldProcess else {
            return
        }
        
        // CRITICAL: Skip frame if we're still processing the previous one
        // This prevents queue buildup and concurrent inference calls
        guard !alreadyProcessing else {
            if frameCounter % 30 == 0 {
                logger.debug("Skipping frame - previous frame still processing")
            }
            return
        }
        
        // Throttle frame rate
        let currentTime = CFAbsoluteTimeGetCurrent()
        let timeSinceLastFrame = currentTime - lastProcessedFrameTime
        
        guard timeSinceLastFrame >= targetFrameInterval else {
            // Skip this frame to maintain target FPS
            return
        }
        
        lastProcessedFrameTime = currentTime
        frameCounter += 1
        
        // Extract pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.error("Failed to get pixel buffer from sample buffer")
            return
        }
        
        // Mark as processing
        isCurrentlyProcessing.pointee = true
        
        // Log every 30 frames (once per second at 30fps)
        if frameCounter % 30 == 0 {
            logger.debug("Processing frame \(self.frameCounter)")
        }
        
        // Process frame asynchronously
        Task {
            await processFrame(pixelBuffer)
            
            // Mark as done processing
            isCurrentlyProcessing.pointee = false
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                      didDrop sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        logger.warning("Dropped frame")
    }
    
    // MARK: - Private Methods
    
    nonisolated private func processFrame(_ pixelBuffer: CVPixelBuffer) async {
        do {
            // Get current prompts from prompt handler
            let prompts = promptHandler.activePrompts
            
            // Skip processing if no prompts
            guard !prompts.isEmpty else {
                return
            }
            
            // Process frame through segmentation engine
            let processedFrame = try await videoSegmentationEngine.processFrame(pixelBuffer, with: prompts)
            
            // Update tracking
            let trackedObjects = try await videoSegmentationEngine.updateTracking(for: processedFrame)
            
            // Log success every 30 frames
            if frameCounter % 30 == 0 {
                logger.debug("Successfully processed frame with \(trackedObjects.count) tracked objects")
            }
            
        } catch {
            // Only log errors occasionally to avoid spam
            if frameCounter % 30 == 0 {
                logger.error("Frame processing failed: \(error.localizedDescription)")
            }
        }
    }
}
