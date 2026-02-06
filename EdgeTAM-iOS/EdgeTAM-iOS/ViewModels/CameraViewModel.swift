import SwiftUI
import AVFoundation
import Combine
import os.log

/// View model for camera view, managing camera operations and video processing
@MainActor
final class CameraViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isProcessing = false
    @Published var currentFPS: Double = 0.0
    @Published var trackedObjects: [TrackedObject] = []
    @Published var currentError: EdgeTAMError?
    @Published var showMasks = true
    @Published var maskOpacity: Double = 0.6
    @Published var hasProcessedFrames = false
    @Published var isSwitchingCamera = false
    @Published var isCameraReady = false
    
    // MARK: - Properties
    
    /// Camera capture session - will be set from CameraManager
    var captureSession: AVCaptureSession {
        return (cameraManager as? CameraManager)?.getCaptureSession() ?? AVCaptureSession()
    }
    
    /// Dependencies
    private var cameraManager: CameraManagerProtocol?
    private var videoSegmentationEngine: VideoSegmentationEngineProtocol?
    private var promptHandler: PromptHandlerProtocol?
    private var performanceMonitor: PerformanceMonitorProtocol?
    private var privacyManager: PrivacyManagerProtocol?
    
    /// Video pipeline coordinator
    private var pipelineCoordinator: VideoPipelineCoordinator?
    
    /// Logger
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "CameraViewModel")
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Current prompts
    private var currentPrompts: [Prompt] = []
    
    /// Processed frames for export
    private var processedFrames: [ProcessedFrame] = []
    private let maxStoredFrames = 300 // Store up to 10 seconds at 30fps
    
    // MARK: - Initialization
    
    init() {
        logger.info("CameraViewModel initialized")
        setupPrivacyNotifications()
    }
    
    deinit {
        // Cancellables and observers will be cleaned up automatically
        logger.info("CameraViewModel deinitialized")
    }
    
    // MARK: - Public Methods
    
    func setupDependencies(_ container: DependencyContainer) {
        do {
            cameraManager = try container.resolve(CameraManagerProtocol.self)
            videoSegmentationEngine = try container.resolve(VideoSegmentationEngineProtocol.self)
            promptHandler = try container.resolve(PromptHandlerProtocol.self)
            performanceMonitor = try container.resolve(PerformanceMonitorProtocol.self)
            privacyManager = try container.resolve(PrivacyManagerProtocol.self)
            
            setupDelegates()
            setupBindings()
            setupVideoPipeline()
            
            logger.info("Dependencies configured with all services integrated")
        } catch {
            logger.error("Failed to resolve dependencies: \(error.localizedDescription)")
            currentError = EdgeTAMError.from(error)
        }
    }
    
    func requestCameraPermission(completion: @escaping @Sendable (Bool) -> Void) {
        // Permission handling is built into startSession, so we'll check current status
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    func startCamera() {
        Task {
            do {
                logger.info("Starting camera session...")
                try await cameraManager?.startSession()
                logger.info("Camera started successfully - session should be running")
                
                // Verify session is running
                if let manager = cameraManager as? CameraManager {
                    let session = manager.getCaptureSession()
                    logger.info("Camera session running: \(session.isRunning)")
                    logger.info("Camera session inputs: \(session.inputs.count)")
                    logger.info("Camera session outputs: \(session.outputs.count)")
                    
                    // Mark camera as ready
                    isCameraReady = session.isRunning
                }
            } catch {
                currentError = EdgeTAMError.from(error)
                logger.error("Failed to start camera: \(error.localizedDescription)")
            }
        }
    }
    
    func stopCamera() {
        cameraManager?.stopSession()
        logger.info("Camera stopped")
    }
    
    func switchCamera() {
        Task {
            do {
                try await cameraManager?.switchCamera()
                logger.info("Camera switched successfully")
            } catch {
                currentError = EdgeTAMError.from(error)
                logger.error("Failed to switch camera: \(error.localizedDescription)")
            }
        }
    }
    
    func startProcessing() {
        Task {
            do {
                try await videoSegmentationEngine?.startProcessing()
                performanceMonitor?.startMonitoring()
                
                // Enable frame processing in pipeline coordinator
                pipelineCoordinator?.setProcessingEnabled(true)
                
                isProcessing = true
                currentError = nil
                logger.info("Processing started")
            } catch {
                currentError = EdgeTAMError.from(error)
                logger.error("Failed to start processing: \(error.localizedDescription)")
            }
        }
    }
    
    func stopProcessing() {
        // Disable frame processing in pipeline coordinator
        pipelineCoordinator?.setProcessingEnabled(false)
        
        videoSegmentationEngine?.stopProcessing()
        performanceMonitor?.stopMonitoring()
        isProcessing = false
        logger.info("Processing stopped")
    }
    
    func addPrompt(_ prompt: Prompt) {
        currentPrompts.append(prompt)
        
        Task {
            switch prompt {
            case .point(let pointPrompt):
                promptHandler?.addPointPrompt(at: pointPrompt.location, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            case .box(let boxPrompt):
                promptHandler?.addBoxPrompt(with: boxPrompt.rect, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            case .mask(let maskPrompt):
                promptHandler?.addMaskPrompt(with: maskPrompt.maskBuffer)
            }
            logger.debug("Prompt added successfully")
        }
    }
    
    func clearAllPrompts() {
        currentPrompts.removeAll()
        promptHandler?.clearPrompts()
        logger.info("All prompts cleared")
    }
    
    func getProcessedFrames() -> [ProcessedFrame] {
        return processedFrames
    }
    
    // MARK: - Private Methods
    
    private func setupDelegates() {
        cameraManager?.delegate = self
        videoSegmentationEngine?.delegate = self
        promptHandler?.delegate = self
        performanceMonitor?.delegate = self
    }
    
    private func setupVideoPipeline() {
        guard let engine = videoSegmentationEngine,
              let handler = promptHandler else {
            logger.error("Cannot setup video pipeline: missing dependencies")
            return
        }
        
        // Create pipeline coordinator
        pipelineCoordinator = VideoPipelineCoordinator(
            videoSegmentationEngine: engine,
            promptHandler: handler
        )
        
        // Connect camera output to pipeline coordinator
        if let coordinator = pipelineCoordinator {
            cameraManager?.setVideoOutput(delegate: coordinator)
            logger.info("Video pipeline connected: Camera -> Coordinator -> SegmentationEngine")
        }
    }
    
    private func setupBindings() {
        // Bind performance monitor FPS to published property
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func updatePerformanceMetrics() {
        if let monitor = performanceMonitor {
            currentFPS = monitor.currentFPS
        }
        
        _ = videoSegmentationEngine
        // Update other metrics from engine if needed
    }
    
    private func storeProcessedFrame(_ frame: ProcessedFrame) {
        processedFrames.append(frame)
        
        // Keep only recent frames
        if processedFrames.count > maxStoredFrames {
            processedFrames.removeFirst()
        }
        
        hasProcessedFrames = !processedFrames.isEmpty
    }
    
    // MARK: - Privacy Management
    
    private func setupPrivacyNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrivacyPauseProcessing),
            name: .privacyManagerDidPauseProcessing,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrivacyResumeProcessing),
            name: .privacyManagerDidResumeProcessing,
            object: nil
        )
    }
    
    @objc private func handlePrivacyPauseProcessing() {
        logger.info("Privacy manager requested processing pause")
        stopProcessing()
        
        // Clear processed frames from memory for privacy
        processedFrames.removeAll()
        hasProcessedFrames = false
        
        // Clear tracked objects
        trackedObjects.removeAll()
    }
    
    @objc private func handlePrivacyResumeProcessing() {
        logger.info("Privacy manager requested processing resume")
        // Processing will be resumed when user explicitly starts it again
        // This ensures user consent for resuming video processing
    }
    
    /// Requests camera permission using privacy-aware flow
    func requestCameraPermissionWithPrivacy() async -> Bool {
        guard let privacyManager = privacyManager else {
            logger.warning("Privacy manager not available, falling back to basic permission request")
            return await withCheckedContinuation { continuation in
                requestCameraPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        
        return await privacyManager.requestCameraPermission()
    }
}

// MARK: - CameraManagerDelegate

extension CameraViewModel: CameraManagerDelegate {
    nonisolated func cameraManagerDidStartSession(_ manager: CameraManagerProtocol) {
        Task { @MainActor in
            logger.info("Camera manager started session")
        }
    }
    
    nonisolated func cameraManagerDidStopSession(_ manager: CameraManagerProtocol) {
        Task { @MainActor in
            logger.info("Camera manager stopped session")
        }
    }
    
    nonisolated func cameraManagerWillSwitchCamera(_ manager: CameraManagerProtocol) {
        Task { @MainActor in
            logger.info("Camera manager will switch camera - preparing for continuity")
            isSwitchingCamera = true
            // Don't stop processing, just prepare for camera switch
        }
    }
    
    nonisolated func cameraManagerDidSwitchCamera(_ manager: CameraManagerProtocol) {
        Task { @MainActor in
            logger.info("Camera manager switched camera - maintaining processing continuity")
            
            // Handle camera switch in video processing components
            // This maintains processing continuity while clearing camera-specific state
            videoSegmentationEngine?.handleCameraSwitch()
            
            // Clear current prompts since they were for the previous camera view
            clearAllPrompts()
            
            // Update UI state
            isSwitchingCamera = false
        }
    }
    
    nonisolated func cameraManager(_ manager: CameraManagerProtocol, didFailWithError error: EdgeTAMError) {
        Task { @MainActor in
            currentError = error
            logger.error("Camera manager error: \(error.localizedDescription)")
        }
    }
}

// MARK: - VideoSegmentationEngineDelegate

extension CameraViewModel: VideoSegmentationEngineDelegate {
    nonisolated func videoSegmentationEngineDidStartProcessing(_ engine: VideoSegmentationEngineProtocol) {
        Task { @MainActor in
            logger.info("Video segmentation engine started processing")
        }
    }
    
    nonisolated func videoSegmentationEngineDidStopProcessing(_ engine: VideoSegmentationEngineProtocol) {
        Task { @MainActor in
            logger.info("Video segmentation engine stopped processing")
        }
    }
    
    nonisolated func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, didProcessFrame frame: ProcessedFrame) {
        Task { @MainActor in
            storeProcessedFrame(frame)
            performanceMonitor?.recordFrame()
        }
    }
    
    nonisolated func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, didUpdateTracking objects: [TrackedObject]) {
        Task { @MainActor in
            trackedObjects = objects
        }
    }
    
    nonisolated func videoSegmentationEngine(_ engine: VideoSegmentationEngineProtocol, didFailWithError error: EdgeTAMError) {
        Task { @MainActor in
            currentError = error
            logger.error("Video segmentation engine error: \(error.localizedDescription)")
        }
    }
}

// MARK: - PromptHandlerDelegate

extension CameraViewModel: PromptHandlerDelegate {
    nonisolated func promptHandler(_ handler: PromptHandlerProtocol, didAddPrompt prompt: Prompt) {
        Task { @MainActor in
            logger.debug("Prompt added successfully")
        }
    }
    
    nonisolated func promptHandler(_ handler: PromptHandlerProtocol, didRemovePrompt promptId: UUID) {
        Task { @MainActor in
            logger.debug("Prompt removed: \(promptId)")
        }
    }
    
    nonisolated func promptHandlerDidClearAllPrompts(_ handler: PromptHandlerProtocol) {
        Task { @MainActor in
            logger.info("All prompts cleared")
        }
    }
    
    nonisolated func promptHandler(_ handler: PromptHandlerProtocol, didFailValidation prompt: Prompt, reason: PromptValidationError) {
        Task { @MainActor in
            currentError = EdgeTAMError.invalidPrompt("Prompt validation failed: \(reason)")
            logger.error("Prompt validation failed: \(reason)")
        }
    }
}

// MARK: - PerformanceMonitorDelegate

extension CameraViewModel: PerformanceMonitorDelegate {
    nonisolated func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didUpdateMetrics metrics: PerformanceMetrics) {
        Task { @MainActor in
            currentFPS = metrics.currentFPS
        }
    }
    
    nonisolated func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectThermalThrottling state: ProcessInfo.ThermalState) {
        Task { @MainActor in
            if state == .critical {
                stopProcessing()
                currentError = EdgeTAMError.thermalThrottling
            }
        }
    }
    
    nonisolated func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectMemoryPressure usage: UInt64) {
        Task { @MainActor in
            // Clear some processed frames to free memory
            if processedFrames.count > 100 {
                processedFrames.removeFirst(50)
            }
            logger.warning("Memory pressure detected, cleared some frames")
        }
    }
}