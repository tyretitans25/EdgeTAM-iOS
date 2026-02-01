import Foundation
import CoreML
import CoreVideo
import Vision
import os.log

/// Implementation of EdgeTAM CoreML model management and inference operations
final class ModelManager: NSObject, ModelManagerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The loaded EdgeTAM CoreML model
    private var edgeTAMModel: MLModel?
    
    /// Vision request for model inference
    private var visionRequest: VNCoreMLRequest?
    
    /// Serial queue for model operations
    private let modelQueue = DispatchQueue(label: "com.edgetam.model.queue", qos: .userInitiated)
    
    /// Serial queue for inference operations
    private let inferenceQueue = DispatchQueue(label: "com.edgetam.inference.queue", qos: .userInitiated)
    
    /// Logger for model operations
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "ModelManager")
    
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
        return edgeTAMModel != nil && visionRequest != nil
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
        
        logger.info("ModelManager initialized with configuration: \(configuration.modelName)")
    }
    
    deinit {
        unloadModel()
        logger.info("ModelManager deinitialized")
    }
    
    // MARK: - ModelManagerProtocol Methods
    
    func loadModel() async throws {
        logger.info("Loading EdgeTAM model: \(self.configuration.modelName)")
        
        return try await withCheckedThrowingContinuation { continuation in
            modelQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.invalidState("ModelManager deallocated"))
                    return
                }
                
                do {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    // Load the CoreML model
                    let model = try self.loadCoreMLModel()
                    
                    // Create Vision request
                    let request = try self.createVisionRequest(with: model)
                    
                    // Store the loaded components
                    self.edgeTAMModel = model
                    self.visionRequest = request
                    
                    // Update memory usage
                    self.updateMemoryUsage()
                    
                    let loadTime = CFAbsoluteTimeGetCurrent() - startTime
                    self.logger.info("Model loaded successfully in \(loadTime, privacy: .public)s")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManagerDidLoadModel(self)
                    }
                    
                    continuation.resume()
                    
                } catch {
                    let edgeTAMError = EdgeTAMError.from(error)
                    self.logger.error("Failed to load model: \(edgeTAMError.localizedDescription)")
                    
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
        guard isModelLoaded else {
            throw EdgeTAMError.invalidState("Model not loaded")
        }
        
        logger.debug("Performing inference with \(prompts.count) prompts")
        
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
                    
                    // Prepare input for model
                    let processedBuffer = try self.preprocessPixelBuffer(pixelBuffer)
                    
                    // Perform inference using Vision framework
                    let result = try self.performVisionInference(on: processedBuffer, with: prompts)
                    
                    // Calculate inference time
                    let inferenceTime = CFAbsoluteTimeGetCurrent() - startTime
                    self._inferenceTime = inferenceTime
                    
                    self.logger.debug("Inference completed in \(inferenceTime, privacy: .public)s")
                    
                    // Notify delegate on main queue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.modelManager(self, didCompleteInference: result)
                    }
                    
                    continuation.resume(returning: result)
                    
                } catch {
                    let edgeTAMError = EdgeTAMError.from(error)
                    self.logger.error("Inference failed: \(edgeTAMError.localizedDescription)")
                    
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
            logger.info("Unloading EdgeTAM model")
            
            edgeTAMModel = nil
            visionRequest = nil
            _memoryUsage = 0
            _inferenceTime = 0
            
            // Notify delegate on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.modelManagerDidUnloadModel(self)
            }
            
            logger.info("Model unloaded successfully")
        }
    }
}

// MARK: - Private Methods

private extension ModelManager {
    
    /// Loads the CoreML model from the app bundle
    func loadCoreMLModel() throws -> MLModel {
        // Try to find the model in the app bundle
        // Check for compiled model first (.mlmodelc), then source model (.mlmodel)
        let modelURL = Bundle.main.url(forResource: configuration.modelName, withExtension: "mlmodelc") ??
                       Bundle.main.url(forResource: configuration.modelName, withExtension: "mlmodel")
        
        guard let url = modelURL else {
            logger.error("EdgeTAM model '\(self.configuration.modelName)' not found in app bundle")
            logger.info("To use this app, you need to:")
            logger.info("1. Convert EdgeTAM PyTorch model to CoreML format")
            logger.info("2. Add the EdgeTAM.mlpackage file to the Xcode project")
            logger.info("3. Ensure the model is added to the EdgeTAM-iOS target")
            logger.info("See README.md for detailed conversion instructions")
            throw EdgeTAMError.modelNotFound(configuration.modelName)
        }
        
        // Create model configuration
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = configuration.computeUnits
        
        // Set memory limit if specified
        if let memoryLimit = configuration.memoryLimit {
            // Note: MLParameterKey.memoryLimit may not be available in all iOS versions
            // For now, we'll skip setting memory limit to avoid compilation errors
            // modelConfig.parameters = [MLParameterKey.memoryLimit: memoryLimit]
        }
        
        // Load the model
        do {
            let model = try MLModel(contentsOf: url, configuration: modelConfig)
            logger.info("CoreML model loaded from: \(url.lastPathComponent)")
            return model
        } catch {
            logger.error("Failed to load CoreML model: \(error.localizedDescription)")
            throw EdgeTAMError.modelLoadingFailed(error.localizedDescription)
        }
    }
    
    /// Creates a Vision request for the loaded model
    func createVisionRequest(with model: MLModel) throws -> VNCoreMLRequest {
        do {
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            
            // Configure request properties
            request.imageCropAndScaleOption = .scaleFill
            
            logger.info("Vision request created successfully")
            return request
        } catch {
            logger.error("Failed to create Vision request: \(error.localizedDescription)")
            throw EdgeTAMError.modelLoadingFailed("Failed to create Vision request: \(error.localizedDescription)")
        }
    }
    
    /// Validates inference input parameters
    private func validateInferenceInput(pixelBuffer: CVPixelBuffer, prompts: [Prompt]) throws {
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
        
        // Validate prompt coordinates are within bounds
        for prompt in prompts {
            switch prompt {
            case .point(let pointPrompt):
                let point = pointPrompt.modelCoordinates
                guard point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1 else {
                    throw EdgeTAMError.invalidPrompt("Point coordinates must be normalized (0-1)")
                }
            case .box(let boxPrompt):
                let rect = boxPrompt.modelCoordinates
                guard rect.minX >= 0 && rect.maxX <= 1 && rect.minY >= 0 && rect.maxY <= 1 else {
                    throw EdgeTAMError.invalidPrompt("Box coordinates must be normalized (0-1)")
                }
            case .mask(let maskPrompt):
                let maskWidth = CVPixelBufferGetWidth(maskPrompt.maskBuffer)
                let maskHeight = CVPixelBufferGetHeight(maskPrompt.maskBuffer)
                guard maskWidth > 0 && maskHeight > 0 else {
                    throw EdgeTAMError.invalidPrompt("Invalid mask buffer dimensions")
                }
            }
        }
    }
    
    /// Preprocesses pixel buffer for model input
    func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        // For now, return the original buffer
        // In a real implementation, this would handle:
        // - Resizing to model input size
        // - Color space conversion
        // - Normalization
        return pixelBuffer
    }
    
    /// Performs inference using Vision framework
    func performVisionInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) throws -> SegmentationResult {
        guard let request = visionRequest else {
            throw EdgeTAMError.invalidState("Vision request not available")
        }
        
        // Create Vision image
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        // Perform the request
        try requestHandler.perform([request])
        
        // Process results
        guard let results = request.results else {
            throw EdgeTAMError.inferenceFailure("No results from model")
        }
        
        // Convert Vision results to SegmentationResult
        return try processVisionResults(results, with: prompts, timestamp: CMTime.zero)
    }
    
    /// Processes Vision framework results into SegmentationResult
    func processVisionResults(_ results: [VNObservation], with prompts: [Prompt], timestamp: CMTime) throws -> SegmentationResult {
        var masks: [SegmentationMask] = []
        var totalConfidence: Float = 0
        
        // Process each result
        for (_, result) in results.enumerated() {
            if let pixelBufferObservation = result as? VNPixelBufferObservation {
                // Create segmentation mask from pixel buffer observation
                let objectId = UUID()
                let confidence = result.confidence
                // VNPixelBufferObservation doesn't have boundingBox, use full frame
                let boundingBox = CGRect(x: 0, y: 0, width: 1, height: 1)
                
                let mask = SegmentationMask(
                    objectId: objectId,
                    maskBuffer: pixelBufferObservation.pixelBuffer,
                    confidence: confidence,
                    boundingBox: boundingBox,
                    area: Float(boundingBox.width * boundingBox.height),
                    centroid: CGPoint(x: boundingBox.midX, y: boundingBox.midY),
                    timestamp: timestamp
                )
                
                masks.append(mask)
                totalConfidence += confidence
            }
        }
        
        // Calculate average confidence
        let averageConfidence = masks.isEmpty ? 0 : totalConfidence / Float(masks.count)
        
        // Create inference metadata
        let metadata = InferenceMetadata(
            modelVersion: "1.0",
            inputResolution: configuration.inputSize,
            outputResolution: configuration.inputSize,
            processingDevice: getProcessingDevice(),
            memoryUsed: memoryUsage,
            computeUnitsUsed: configuration.computeUnits
        )
        
        return SegmentationResult(
            masks: masks,
            inferenceTime: inferenceTime,
            confidence: averageConfidence,
            metadata: metadata,
            timestamp: timestamp
        )
    }
    
    /// Gets the current processing device description
    func getProcessingDevice() -> String {
        switch configuration.computeUnits {
        case .all:
            return "Neural Engine + GPU + CPU"
        case .cpuAndGPU:
            return "GPU + CPU"
        case .cpuAndNeuralEngine:
            return "Neural Engine + CPU"
        case .cpuOnly:
            return "CPU"
        @unknown default:
            return "Unknown"
        }
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
        // This is a simplified estimation
        // In a real implementation, this would use more sophisticated memory tracking
        let baseMemoryUsage: UInt64 = 100 * 1024 * 1024 // 100MB base estimate
        let modelMemoryUsage: UInt64 = isModelLoaded ? 200 * 1024 * 1024 : 0 // 200MB when loaded
        
        _memoryUsage = baseMemoryUsage + modelMemoryUsage
    }
}

// MARK: - Required Imports
import UIKit