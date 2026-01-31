import Foundation
import CoreGraphics
import CoreVideo

/// Protocol defining user interaction prompt handling
protocol PromptHandlerProtocol: AnyObject, Sendable {
    /// Adds a point prompt at the specified location
    /// - Parameters:
    ///   - location: The tap location in view coordinates
    ///   - frame: The view frame for coordinate conversion
    func addPointPrompt(at location: CGPoint, in frame: CGRect)
    
    /// Adds a box prompt with the specified rectangle
    /// - Parameters:
    ///   - rect: The bounding box in view coordinates
    ///   - frame: The view frame for coordinate conversion
    func addBoxPrompt(with rect: CGRect, in frame: CGRect)
    
    /// Adds a mask prompt from a previous segmentation
    /// - Parameter mask: The mask pixel buffer to use as prompt
    func addMaskPrompt(with mask: CVPixelBuffer)
    
    /// Removes a specific prompt
    /// - Parameter promptId: Unique identifier of the prompt to remove
    func removePrompt(withId promptId: UUID)
    
    /// Clears all active prompts
    func clearPrompts()
    
    /// Validates if a prompt is within acceptable bounds
    /// - Parameter prompt: The prompt to validate
    /// - Returns: True if the prompt is valid
    func validatePrompt(_ prompt: Prompt) -> Bool
    
    /// Converts view coordinates to model input coordinates
    /// - Parameters:
    ///   - viewPoint: Point in view coordinate system
    ///   - viewFrame: The view frame
    ///   - modelSize: The model input size
    /// - Returns: Point in model coordinate system
    func convertToModelCoordinates(viewPoint: CGPoint, 
                                  viewFrame: CGRect, 
                                  modelSize: CGSize) -> CGPoint
    
    /// Currently active prompts
    var activePrompts: [Prompt] { get }
    
    /// Maximum number of simultaneous prompts allowed
    var maxPrompts: Int { get set }
    
    /// Prompt validation configuration
    var validationRules: PromptValidationRules { get set }
    
    /// Delegate for prompt events
    var delegate: PromptHandlerDelegate? { get set }
}

/// Delegate protocol for prompt handler events
protocol PromptHandlerDelegate: AnyObject {
    /// Called when a new prompt is added
    func promptHandler(_ handler: PromptHandlerProtocol, didAddPrompt prompt: Prompt)
    
    /// Called when a prompt is removed
    func promptHandler(_ handler: PromptHandlerProtocol, didRemovePrompt promptId: UUID)
    
    /// Called when all prompts are cleared
    func promptHandlerDidClearAllPrompts(_ handler: PromptHandlerProtocol)
    
    /// Called when prompt validation fails
    func promptHandler(_ handler: PromptHandlerProtocol, 
                      didFailValidation prompt: Prompt, 
                      reason: PromptValidationError)
}

/// Validation rules for prompts
struct PromptValidationRules {
    let minBoxSize: CGSize
    let maxBoxSize: CGSize
    let allowOverlappingPrompts: Bool
    let requireMinimumDistance: CGFloat
    
    init(minBoxSize: CGSize = CGSize(width: 10, height: 10),
         maxBoxSize: CGSize = CGSize(width: 500, height: 500),
         allowOverlappingPrompts: Bool = false,
         requireMinimumDistance: CGFloat = 20.0) {
        self.minBoxSize = minBoxSize
        self.maxBoxSize = maxBoxSize
        self.allowOverlappingPrompts = allowOverlappingPrompts
        self.requireMinimumDistance = requireMinimumDistance
    }
}

/// Errors that can occur during prompt validation
enum PromptValidationError: LocalizedError {
    case boxTooSmall
    case boxTooLarge
    case pointOutOfBounds
    case tooManyPrompts
    case overlappingPrompts
    case insufficientDistance
    
    var errorDescription: String? {
        switch self {
        case .boxTooSmall:
            return "Bounding box is too small for accurate segmentation"
        case .boxTooLarge:
            return "Bounding box is too large"
        case .pointOutOfBounds:
            return "Point is outside the valid area"
        case .tooManyPrompts:
            return "Maximum number of prompts exceeded"
        case .overlappingPrompts:
            return "Prompts cannot overlap"
        case .insufficientDistance:
            return "Prompts must be sufficiently separated"
        }
    }
}