import Foundation
import CoreML
import CoreVideo
import CoreMedia
import os.log

/// PyTorch Mobile-based implementation of ModelManager
/// Replaces CoreML implementation to work around CoreMLTools limitations
final class PyTorchModelManager: NSObject, ModelManagerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The PyTorch model module
    private var torchModule: PyTorchModule?
    
    /// Serial queue for model operations
    private let modelQueue = DispatchQueue(label: "com.edgetam.pytorch.model.queue", qos: .userInitiated)
    
    /// Serial queue for inference operations
    private let inferenceQueue = DispatchQueue(label: "com.edgetam.pytorch.inference.queue", qos: .userInitiated)
    
    /// Logger for model operations
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "PyTorchModelManager")
    
    /// Current memory usage tracking
    private var _memoryUsage: UInt64 = 0
    
    /// Last inference time tracking
    private var _inferenceTime: TimeInterval = 0
    
    /// Model configuration
    var configuration: ModelConfiguration {
        didSet {
            if isModelLoaded {
                logger.info("Model configuration changed, will reload model on next inference")
                unloadModel()
            }
        }
    }
    
    /// Delegate for model manager events
    weak var delegate: ModelManagerDelegate?
    
    // MARK: - ModelManagerProtocol Properties
    
    var isModelLoaded: Bool {
        return torchModule?.isLoaded ?? false
    }
    
    var inferenceTime: TimeInterval {
        return _inferenceTime
    }
    
    var memoryUsage: UInt64 {
        return _memoryUsage
    }
    
    // MARK: - Initialization
    
    init(configuration: ModelConfiguration = ModelConfiguration()) {
        self.configuration = configuration
        super.init()
        
        // Set up memory monitoring
        setupMemoryMonitoring()
        
        logger.info("PyTorchModelManager initialized with configuration: \(configuration.modelName)")
    }
    
    deinit {
        unloadModel()
        logger.info("PyTorchModelManager deinitialized")
    }
    
    // MARK: - ModelManagerProtocol Methods
    
    func loadModel() async throws {
        logger.info("Loading EdgeTAM PyTorch model: \(self.configuration.modelName)")
        
        return try await withCheckedThrowingContinuation { continuation in
            modelQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.invalidState("ModelManager deallocated"))
                    return
                }
                
                do {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    // Get model path from bundle
                    let modelPath = try self.getModelPath()
                    
                    // Create PyTorch module
                    guard let module = PyTorchModule(modelPath: modelPath) else {
                        throw EdgeTAMError.modelLoadingFailed("Failed to initialize PyTorch module")
                    }
                    
                    // Load the model
                    try module.loadModel()
                    
                    // Store the loaded module
                    self.torchModule = module
                    
                    // Update memory usage
                    self.updateMemoryUsage()
                    
                    let loadTime = CFAbsoluteTimeGetCurrent() - startTime
                    self.logger.info("PyTorch model loaded successfully in \(loadTime, privacy: .public)s")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManagerDidLoadModel(self)
                    }
                    
                    continuation.resume()
                    
                } catch {
                    let edgeTAMError = EdgeTAMError.from(error)
                    self.logger.error("Failed to load PyTorch model: \(edgeTAMError.localizedDescription)")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManager(self, didFailWithError: edgeTAMError)
                    }
                    
                    continuation.resume(throwing: edgeTAMError)
                }
            }
        }
    }
    
    func performInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> SegmentationResult {
        guard isModelLoaded, let module = torchModule else {
            throw EdgeTAMError.invalidState("Model not loaded")
        }
        
        logger.debug("Performing PyTorch inference with \(prompts.count) prompts")
        
        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.invalidState("ModelManager deallocated"))
                    return
                }
                
                let startTime = CFAbsoluteTimeGetCurrent()
                
                do {
                    // Validate input
                    try self.validateInferenceInput(pixelBuffer: pixelBuffer, prompts: prompts)
                    
                    // Convert prompts to point prompts
                    let pointPrompts = try self.convertToPointPrompts(prompts, frameSize: CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    ))
                    
                    // Preprocess pixel buffer if needed
                    let processedBuffer = try self.preprocessPixelBuffer(pixelBuffer)
                    
                    // Perform inference using PyTorch
                    let torchResult = try module.predict(pixelBuffer: processedBuffer, points: pointPrompts)
                    
                    // Convert to SegmentationResult
                    var result = torchResult.toSegmentationResult(timestamp: CMTime.zero)
                    
                    // Update inference time
                    let totalInferenceTime = CFAbsoluteTimeGetCurrent() - startTime
                    self._inferenceTime = totalInferenceTime
                    
                    // Update memory usage
                    self._memoryUsage = module.memoryUsage
                    
                    self.logger.debug("PyTorch inference completed in \(totalInferenceTime, privacy: .public)s")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManager(self, didCompleteInference: result)
                    }
                    
                    continuation.resume(returning: result)
                    
                } catch {
                    let edgeTAMError = EdgeTAMError.from(error)
                    self.logger.error("PyTorch inference failed: \(edgeTAMError.localizedDescription)")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManager(self, didFailWithError: edgeTAMError)
                    }
                    
                    continuation.resume(throwing: edgeTAMError)
                }
            }
        }
    }
    
    func unloadModel() {
        modelQueue.sync {
            logger.info("Unloading PyTorch model")
            
            torchModule?.unloadModel()
            torchModule = nil
            _memoryUsage = 0
            _inferenceTime = 0
            
            // Notify delegate on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.modelManagerDidUnloadModel(self)
            }
            
            logger.info("PyTorch model unloaded successfully")
        }
    }
}

// MARK: - Private Methods

private extension PyTorchModelManager {
    
    /// Gets the model file path from the app bundle
    func getModelPath() throws -> String {
        // Try to find the TorchScript model in the app bundle
        // Look for .pt file
        let modelName = configuration.modelName.replacingOccurrences(of: ".pt", with: "")
        
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "pt") else {
            logger.error("PyTorch model '\(modelName).pt' not found in app bundle")
            logger.info("To use this app, you need to:")
            logger.info("1. Export EdgeTAM PyTorch model to TorchScript format")
            logger.info("2. Add the edgetam_mobile.pt file to the Xcode project")
            logger.info("3. Ensure the model is added to the EdgeTAM-iOS target")
            logger.info("See PYTORCH_MOBILE_SETUP_GUIDE.md for detailed instructions")
            throw EdgeTAMError.modelNotFound(modelName)
        }
        
        logger.info("Found PyTorch model at: \(modelURL.path)")
        return modelURL.path
    }
    
    /// Validates inference input parameters
    func validateInferenceInput(pixelBuffer: CVPixelBuffer, prompts: [Prompt]) throws {
        // Validate pixel buffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard width > 0 && height > 0 else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        // Validate prompts
        guard !prompts.isEmpty else {
            throw EdgeTAMError.invalidPrompt("At least one prompt is required")
        }
        
        guard prompts.count <= 5 else {
            throw EdgeTAMError.promptLimitExceeded
        }
    }
    
    /// Converts generic prompts to point prompts for PyTorch model
    func convertToPointPrompts(_ prompts: [Prompt], frameSize: CGSize) throws -> [PointPrompt] {
        var pointPrompts: [PointPrompt] = []
        
        for prompt in prompts {
            switch prompt {
            case .point(let pointPrompt):
                pointPrompts.append(pointPrompt)
                
            case .box(let boxPrompt):
                // Convert box to corner points
                let rect = boxPrompt.modelCoordinates
                let topLeft = PointPrompt(
                    location: CGPoint(x: rect.minX * frameSize.width, y: rect.minY * frameSize.height),
                    modelCoordinates: CGPoint(x: rect.minX, y: rect.minY),
                    isPositive: true
                )
                let bottomRight = PointPrompt(
                    location: CGPoint(x: rect.maxX * frameSize.width, y: rect.maxY * frameSize.height),
                    modelCoordinates: CGPoint(x: rect.maxX, y: rect.maxY),
                    isPositive: true
                )
                pointPrompts.append(contentsOf: [topLeft, bottomRight])
                
            case .mask:
                // Mask prompts not supported in PyTorch Mobile version
                logger.warning("Mask prompts not supported in PyTorch Mobile, skipping")
            }
        }
        
        guard !pointPrompts.isEmpty else {
            throw EdgeTAMError.invalidPrompt("No valid point prompts after conversion")
        }
        
        return pointPrompts
    }
    
    /// Preprocesses pixel buffer for model input
    func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        // Check if resizing is needed
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let targetSize = configuration.inputSize
        
        // If already correct size, return as-is
        if width == Int(targetSize.width) && height == Int(targetSize.height) {
            return pixelBuffer
        }
        
        // TODO: Implement resizing if needed
        // For now, assume input is already correct size
        logger.warning("Input size mismatch: \(width)x\(height) vs \(Int(targetSize.width))x\(Int(targetSize.height))")
        return pixelBuffer
    }
    
    /// Sets up memory monitoring
    func setupMemoryMonitoring() {
        // Monitor memory pressure notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    /// Handles memory warning notifications
    func handleMemoryWarning() {
        logger.warning("Memory warning received")
        
        // Notify delegate about memory pressure
        self.delegate?.modelManager(self, didFailWithError: .memoryPressure)
        
        // Consider unloading model if memory pressure is severe
        if ProcessInfo.processInfo.thermalState == .critical {
            logger.warning("Critical thermal state detected, unloading model")
            unloadModel()
        }
    }
    
    /// Updates current memory usage estimate
    func updateMemoryUsage() {
        if let module = torchModule {
            _memoryUsage = module.memoryUsage
        } else {
            _memoryUsage = 0
        }
    }
}

// MARK: - Required Imports
import UIKit
