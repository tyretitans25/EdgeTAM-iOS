import Foundation
import CoreVideo
import UIKit
import Metal

/// Protocol defining mask overlay rendering operations
protocol MaskRendererProtocol: AnyObject {
    /// Renders segmentation masks onto a video frame
    /// - Parameters:
    ///   - masks: Array of segmentation masks to render
    ///   - pixelBuffer: The video frame to render onto
    /// - Returns: New pixel buffer with rendered masks
    /// - Throws: EdgeTAMError if rendering fails
    func renderMasks(_ masks: [SegmentationMask], 
                    on pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer
    
    /// Renders masks with custom rendering options
    /// - Parameters:
    ///   - masks: Array of segmentation masks to render
    ///   - pixelBuffer: The video frame to render onto
    ///   - options: Custom rendering options
    /// - Returns: New pixel buffer with rendered masks
    /// - Throws: EdgeTAMError if rendering fails
    func renderMasks(_ masks: [SegmentationMask], 
                    on pixelBuffer: CVPixelBuffer, 
                    with options: RenderingOptions) throws -> CVPixelBuffer
    
    /// Sets the global opacity for all mask overlays
    /// - Parameter opacity: Opacity value between 0.0 and 1.0
    func setOpacity(_ opacity: Float)
    
    /// Sets the color palette for different tracked objects
    /// - Parameter colors: Array of colors to use for different objects
    func setColorPalette(_ colors: [UIColor])
    
    /// Sets the rendering mode (solid, outline, etc.)
    /// - Parameter mode: The rendering mode to use
    func setRenderingMode(_ mode: MaskRenderingMode)
    
    /// Enables or disables anti-aliasing for smoother edges
    /// - Parameter enabled: Whether to enable anti-aliasing
    func setAntiAliasing(_ enabled: Bool)
    
    /// Current opacity setting
    var opacity: Float { get }
    
    /// Current color palette
    var colorPalette: [UIColor] { get }
    
    /// Current rendering mode
    var renderingMode: MaskRenderingMode { get }
    
    /// Whether anti-aliasing is enabled
    var antiAliasingEnabled: Bool { get }
    
    /// Rendering performance metrics
    var renderingMetrics: RenderingMetrics { get }
    
    /// Delegate for rendering events
    var delegate: MaskRendererDelegate? { get set }
}

/// Delegate protocol for mask renderer events
protocol MaskRendererDelegate: AnyObject {
    /// Called when mask rendering completes successfully
    func maskRenderer(_ renderer: MaskRendererProtocol, 
                     didRenderMasks masks: [SegmentationMask], 
                     renderTime: TimeInterval)
    
    /// Called when rendering fails
    func maskRenderer(_ renderer: MaskRendererProtocol, 
                     didFailWithError error: EdgeTAMError)
    
    /// Called when rendering settings change
    func maskRendererDidUpdateSettings(_ renderer: MaskRendererProtocol)
}

/// Different modes for rendering segmentation masks
enum MaskRenderingMode {
    case solid          // Filled mask overlay
    case outline        // Only mask boundaries
    case gradient       // Gradient from center to edge
    case pattern        // Patterned fill
    case highlight      // Highlighted regions
}

/// Options for customizing mask rendering
struct RenderingOptions {
    let opacity: Float?
    let colors: [UIColor]?
    let mode: MaskRenderingMode?
    let antiAliasing: Bool?
    let blendMode: CGBlendMode?
    let strokeWidth: Float?
    
    init(opacity: Float? = nil,
         colors: [UIColor]? = nil,
         mode: MaskRenderingMode? = nil,
         antiAliasing: Bool? = nil,
         blendMode: CGBlendMode? = nil,
         strokeWidth: Float? = nil) {
        self.opacity = opacity
        self.colors = colors
        self.mode = mode
        self.antiAliasing = antiAliasing
        self.blendMode = blendMode
        self.strokeWidth = strokeWidth
    }
}

/// Performance metrics for mask rendering
struct RenderingMetrics {
    let averageRenderTime: TimeInterval
    let lastRenderTime: TimeInterval
    let totalFramesRendered: Int
    let droppedFrames: Int
    let gpuUtilization: Float
    
    init(averageRenderTime: TimeInterval = 0,
         lastRenderTime: TimeInterval = 0,
         totalFramesRendered: Int = 0,
         droppedFrames: Int = 0,
         gpuUtilization: Float = 0) {
        self.averageRenderTime = averageRenderTime
        self.lastRenderTime = lastRenderTime
        self.totalFramesRendered = totalFramesRendered
        self.droppedFrames = droppedFrames
        self.gpuUtilization = gpuUtilization
    }
}