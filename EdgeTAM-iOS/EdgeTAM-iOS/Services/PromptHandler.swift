import Foundation
import CoreGraphics
import CoreVideo
import UIKit

/// Implementation of prompt handling for user interaction processing
/// Handles point and box prompt coordinate conversion, validates inputs, and manages multiple simultaneous prompts
class PromptHandler: PromptHandlerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Currently active prompts
    private(set) var activePrompts: [Prompt] = []
    
    /// Maximum number of simultaneous prompts allowed (up to system limits)
    var maxPrompts: Int = 5
    
    /// Prompt validation configuration
    var validationRules: PromptValidationRules = PromptValidationRules()
    
    /// Delegate for prompt events
    weak var delegate: PromptHandlerDelegate?
    
    /// Thread-safe access queue
    private let promptQueue = DispatchQueue(label: "com.edgetam.prompthandler", qos: .userInteractive)
    
    // MARK: - Initialization
    
    init(maxPrompts: Int = 5, validationRules: PromptValidationRules = PromptValidationRules()) {
        self.maxPrompts = maxPrompts
        self.validationRules = validationRules
    }
    
    // MARK: - PromptHandlerProtocol Implementation
    
    func addPointPrompt(at location: CGPoint, in frame: CGRect) {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we've reached the maximum number of prompts
            if self.activePrompts.count >= self.maxPrompts {
                let error = PromptValidationError.tooManyPrompts
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: .point(PointPrompt(location: location, modelCoordinates: location)), reason: error)
                }
                return
            }
            
            // Convert to model coordinates (assuming 1024x1024 model input size)
            let modelSize = CGSize(width: 1024, height: 1024)
            let modelCoordinates = self.convertToModelCoordinates(viewPoint: location, viewFrame: frame, modelSize: modelSize)
            
            // Create point prompt
            let pointPrompt = PointPrompt(
                location: location,
                modelCoordinates: modelCoordinates,
                isPositive: true
            )
            
            let prompt = Prompt.point(pointPrompt)
            
            // Validate the prompt
            if !self.validatePrompt(prompt) {
                let error = self.determineValidationError(for: prompt, in: frame)
                DispatchQueue.main.async {
                    self.delegate?.promptHandler(self, didFailValidation: prompt, reason: error)
                }
                return
            }
            
            // Add the prompt
            self.activePrompts.append(prompt)
            
            // Notify delegate on main queue
            DispatchQueue.main.async {
                self.delegate?.promptHandler(self, didAddPrompt: prompt)
            }
        }
    }
    
    func addBoxPrompt(with rect: CGRect, in frame: CGRect) {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we've reached the maximum number of prompts
            if self.activePrompts.count >= self.maxPrompts {
                let error = PromptValidationError.tooManyPrompts
                let tempPrompt = Prompt.box(BoxPrompt(rect: rect, modelCoordinates: rect))
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: tempPrompt, reason: error)
                }
                return
            }
            
            // Convert to model coordinates
            let modelSize = CGSize(width: 1024, height: 1024)
            let modelRect = self.convertRectToModelCoordinates(viewRect: rect, viewFrame: frame, modelSize: modelSize)
            
            // Create box prompt
            let boxPrompt = BoxPrompt(
                rect: rect,
                modelCoordinates: modelRect
            )
            
            let prompt = Prompt.box(boxPrompt)
            
            // Validate the prompt
            if !self.validatePrompt(prompt) {
                let error = self.determineValidationError(for: prompt, in: frame)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: prompt, reason: error)
                }
                return
            }
            
            // Add the prompt
            self.activePrompts.append(prompt)
            
            // Notify delegate on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.promptHandler(self, didAddPrompt: prompt)
            }
        }
    }
    
    func addMaskPrompt(with mask: CVPixelBuffer) {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if we've reached the maximum number of prompts
            if self.activePrompts.count >= self.maxPrompts {
                let error = PromptValidationError.tooManyPrompts
                let tempPrompt = Prompt.mask(MaskPrompt(maskBuffer: mask))
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: tempPrompt, reason: error)
                }
                return
            }
            
            // Create mask prompt
            let maskPrompt = MaskPrompt(maskBuffer: mask)
            let prompt = Prompt.mask(maskPrompt)
            
            // Validate the prompt (mask prompts are generally always valid if they have content)
            if !self.validatePrompt(prompt) {
                let error = PromptValidationError.pointOutOfBounds // Generic error for invalid mask
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: prompt, reason: error)
                }
                return
            }
            
            // Add the prompt
            self.activePrompts.append(prompt)
            
            // Notify delegate on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.promptHandler(self, didAddPrompt: prompt)
            }
        }
    }
    
    func removePrompt(withId promptId: UUID) {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Find and remove the prompt
            if let index = self.activePrompts.firstIndex(where: { $0.id == promptId }) {
                self.activePrompts.remove(at: index)
                
                // Notify delegate on main queue
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didRemovePrompt: promptId)
                }
            }
        }
    }
    
    func clearPrompts() {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.activePrompts.removeAll()
            
            // Notify delegate on main queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.promptHandlerDidClearAllPrompts(self)
            }
        }
    }
    
    func validatePrompt(_ prompt: Prompt) -> Bool {
        switch prompt {
        case .point(let pointPrompt):
            return validatePointPrompt(pointPrompt)
        case .box(let boxPrompt):
            return validateBoxPrompt(boxPrompt)
        case .mask(let maskPrompt):
            return validateMaskPrompt(maskPrompt)
        }
    }
    
    func convertToModelCoordinates(viewPoint: CGPoint, viewFrame: CGRect, modelSize: CGSize) -> CGPoint {
        // Normalize the point to [0, 1] range
        let normalizedX = viewPoint.x / viewFrame.width
        let normalizedY = viewPoint.y / viewFrame.height
        
        // Convert to model coordinates
        let modelX = normalizedX * modelSize.width
        let modelY = normalizedY * modelSize.height
        
        // Clamp to model bounds
        let clampedX = max(0, min(modelSize.width, modelX))
        let clampedY = max(0, min(modelSize.height, modelY))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - Private Helper Methods
    
    private func convertRectToModelCoordinates(viewRect: CGRect, viewFrame: CGRect, modelSize: CGSize) -> CGRect {
        // Convert each corner of the rectangle
        let topLeft = convertToModelCoordinates(
            viewPoint: CGPoint(x: viewRect.minX, y: viewRect.minY),
            viewFrame: viewFrame,
            modelSize: modelSize
        )
        
        let bottomRight = convertToModelCoordinates(
            viewPoint: CGPoint(x: viewRect.maxX, y: viewRect.maxY),
            viewFrame: viewFrame,
            modelSize: modelSize
        )
        
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }
    
    private func validatePointPrompt(_ pointPrompt: PointPrompt) -> Bool {
        // Check if point is within reasonable bounds (model coordinates should be positive)
        guard pointPrompt.modelCoordinates.x >= 0 && pointPrompt.modelCoordinates.y >= 0 else {
            return false
        }
        
        // Check minimum distance from other point prompts if required
        if validationRules.requireMinimumDistance > 0 {
            for existingPrompt in activePrompts {
                if case .point(let existingPoint) = existingPrompt {
                    let distance = sqrt(
                        pow(pointPrompt.modelCoordinates.x - existingPoint.modelCoordinates.x, 2) +
                        pow(pointPrompt.modelCoordinates.y - existingPoint.modelCoordinates.y, 2)
                    )
                    if distance < validationRules.requireMinimumDistance {
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    private func validateBoxPrompt(_ boxPrompt: BoxPrompt) -> Bool {
        let rect = boxPrompt.modelCoordinates
        
        // Check minimum size
        if rect.width < validationRules.minBoxSize.width || rect.height < validationRules.minBoxSize.height {
            return false
        }
        
        // Check maximum size
        if rect.width > validationRules.maxBoxSize.width || rect.height > validationRules.maxBoxSize.height {
            return false
        }
        
        // Check for overlapping prompts if not allowed
        if !validationRules.allowOverlappingPrompts {
            for existingPrompt in activePrompts {
                if case .box(let existingBox) = existingPrompt {
                    if rect.intersects(existingBox.modelCoordinates) {
                        return false
                    }
                }
            }
        }
        
        return true
    }
    
    private func validateMaskPrompt(_ maskPrompt: MaskPrompt) -> Bool {
        // Basic validation - ensure the mask buffer is valid
        let width = CVPixelBufferGetWidth(maskPrompt.maskBuffer)
        let height = CVPixelBufferGetHeight(maskPrompt.maskBuffer)
        
        return width > 0 && height > 0
    }
    
    private func determineValidationError(for prompt: Prompt, in frame: CGRect) -> PromptValidationError {
        switch prompt {
        case .point(let pointPrompt):
            // Check if point is out of bounds
            if pointPrompt.location.x < 0 || pointPrompt.location.y < 0 ||
               pointPrompt.location.x > frame.width || pointPrompt.location.y > frame.height {
                return .pointOutOfBounds
            }
            
            // Check minimum distance
            if validationRules.requireMinimumDistance > 0 {
                for existingPrompt in activePrompts {
                    if case .point(let existingPoint) = existingPrompt {
                        let distance = sqrt(
                            pow(pointPrompt.modelCoordinates.x - existingPoint.modelCoordinates.x, 2) +
                            pow(pointPrompt.modelCoordinates.y - existingPoint.modelCoordinates.y, 2)
                        )
                        if distance < validationRules.requireMinimumDistance {
                            return .insufficientDistance
                        }
                    }
                }
            }
            
            return .pointOutOfBounds
            
        case .box(let boxPrompt):
            let rect = boxPrompt.modelCoordinates
            
            if rect.width < validationRules.minBoxSize.width || rect.height < validationRules.minBoxSize.height {
                return .boxTooSmall
            }
            
            if rect.width > validationRules.maxBoxSize.width || rect.height > validationRules.maxBoxSize.height {
                return .boxTooLarge
            }
            
            if !validationRules.allowOverlappingPrompts {
                for existingPrompt in activePrompts {
                    if case .box(let existingBox) = existingPrompt {
                        if rect.intersects(existingBox.modelCoordinates) {
                            return .overlappingPrompts
                        }
                    }
                }
            }
            
            return .boxTooSmall
            
        case .mask:
            return .pointOutOfBounds // Generic error for mask validation failure
        }
    }
}

// MARK: - Thread-Safe Property Access

extension PromptHandler {
    /// Thread-safe access to active prompts
    var safeActivePrompts: [Prompt] {
        return promptQueue.sync {
            return activePrompts
        }
    }
    
    /// Thread-safe count of active prompts
    var activePromptCount: Int {
        return promptQueue.sync {
            return activePrompts.count
        }
    }
    
    /// Thread-safe check if prompts are at capacity
    var isAtCapacity: Bool {
        return promptQueue.sync {
            return activePrompts.count >= maxPrompts
        }
    }
}

// MARK: - Convenience Methods

extension PromptHandler {
    /// Adds a negative point prompt (for background selection)
    func addNegativePointPrompt(at location: CGPoint, in frame: CGRect) {
        promptQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check capacity
            if self.activePrompts.count >= self.maxPrompts {
                let error = PromptValidationError.tooManyPrompts
                let tempPrompt = Prompt.point(PointPrompt(location: location, modelCoordinates: location, isPositive: false))
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: tempPrompt, reason: error)
                }
                return
            }
            
            // Convert to model coordinates
            let modelSize = CGSize(width: 1024, height: 1024)
            let modelCoordinates = self.convertToModelCoordinates(viewPoint: location, viewFrame: frame, modelSize: modelSize)
            
            // Create negative point prompt
            let pointPrompt = PointPrompt(
                location: location,
                modelCoordinates: modelCoordinates,
                isPositive: false
            )
            
            let prompt = Prompt.point(pointPrompt)
            
            // Validate and add
            if self.validatePrompt(prompt) {
                self.activePrompts.append(prompt)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didAddPrompt: prompt)
                }
            } else {
                let error = self.determineValidationError(for: prompt, in: frame)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.promptHandler(self, didFailValidation: prompt, reason: error)
                }
            }
        }
    }
    
    /// Gets all point prompts (both positive and negative)
    func getPointPrompts() -> [PointPrompt] {
        return promptQueue.sync {
            return activePrompts.compactMap { prompt in
                if case .point(let pointPrompt) = prompt {
                    return pointPrompt
                }
                return nil
            }
        }
    }
    
    /// Gets all box prompts
    func getBoxPrompts() -> [BoxPrompt] {
        return promptQueue.sync {
            return activePrompts.compactMap { prompt in
                if case .box(let boxPrompt) = prompt {
                    return boxPrompt
                }
                return nil
            }
        }
    }
    
    /// Gets all mask prompts
    func getMaskPrompts() -> [MaskPrompt] {
        return promptQueue.sync {
            return activePrompts.compactMap { prompt in
                if case .mask(let maskPrompt) = prompt {
                    return maskPrompt
                }
                return nil
            }
        }
    }
}