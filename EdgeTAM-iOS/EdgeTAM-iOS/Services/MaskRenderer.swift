import Foundation
import CoreVideo
import UIKit
import Metal
import MetalKit
import CoreImage

/// Metal-based implementation of mask overlay rendering
class MaskRenderer: MaskRendererProtocol {
    
    // MARK: - Properties
    
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private var renderPipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?
    
    // Configuration properties
    private var _opacity: Float = 0.6
    private var _colorPalette: [UIColor] = [
        .systemRed,
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPurple,
        .systemYellow,
        .systemPink,
        .systemTeal
    ]
    private var _renderingMode: MaskRenderingMode = .solid
    private var _antiAliasingEnabled: Bool = true
    
    // Performance tracking
    private var _renderingMetrics: RenderingMetrics = RenderingMetrics()
    private var renderTimes: [TimeInterval] = []
    private let maxRenderTimeHistory = 30
    
    // Delegate
    weak var delegate: MaskRendererDelegate?
    
    // MARK: - Initialization
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw EdgeTAMError.renderingFailed("Failed to create Metal device")
        }
        
        self.metalDevice = device
        
        guard let queue = device.makeCommandQueue() else {
            throw EdgeTAMError.renderingFailed("Failed to create Metal command queue")
        }
        
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device)
        
        try setupMetalPipeline()
    }
    
    // MARK: - MaskRendererProtocol Implementation
    
    var opacity: Float {
        return _opacity
    }
    
    var colorPalette: [UIColor] {
        return _colorPalette
    }
    
    var renderingMode: MaskRenderingMode {
        return _renderingMode
    }
    
    var antiAliasingEnabled: Bool {
        return _antiAliasingEnabled
    }
    
    var renderingMetrics: RenderingMetrics {
        return _renderingMetrics
    }
    
    func renderMasks(_ masks: [SegmentationMask], 
                    on pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let options = RenderingOptions(
            opacity: _opacity,
            colors: _colorPalette,
            mode: _renderingMode,
            antiAliasing: _antiAliasingEnabled
        )
        
        return try renderMasks(masks, on: pixelBuffer, with: options)
    }
    
    func renderMasks(_ masks: [SegmentationMask], 
                    on pixelBuffer: CVPixelBuffer, 
                    with options: RenderingOptions) throws -> CVPixelBuffer {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try performMaskRendering(masks, on: pixelBuffer, with: options)
            
            let renderTime = CFAbsoluteTimeGetCurrent() - startTime
            updateRenderingMetrics(renderTime: renderTime)
            
            delegate?.maskRenderer(self, didRenderMasks: masks, renderTime: renderTime)
            
            return result
        } catch {
            let edgeTAMError = EdgeTAMError.from(error)
            delegate?.maskRenderer(self, didFailWithError: edgeTAMError)
            throw edgeTAMError
        }
    }
    
    func setOpacity(_ opacity: Float) {
        let clampedOpacity = max(0.0, min(0.8, opacity)) // Clamp to 0-80% as per requirements
        _opacity = clampedOpacity
        delegate?.maskRendererDidUpdateSettings(self)
    }
    
    func setColorPalette(_ colors: [UIColor]) {
        _colorPalette = colors.isEmpty ? [.systemRed] : colors
        delegate?.maskRendererDidUpdateSettings(self)
    }
    
    func setRenderingMode(_ mode: MaskRenderingMode) {
        _renderingMode = mode
        delegate?.maskRendererDidUpdateSettings(self)
    }
    
    func setAntiAliasing(_ enabled: Bool) {
        _antiAliasingEnabled = enabled
        delegate?.maskRendererDidUpdateSettings(self)
    }
    
    // MARK: - Private Implementation
    
    private func setupMetalPipeline() throws {
        // Create Metal library with default shaders
        guard metalDevice.makeDefaultLibrary() != nil else {
            throw EdgeTAMError.renderingFailed("Failed to create Metal library")
        }
        
        // For now, we'll use CoreImage for rendering since creating custom Metal shaders
        // would require additional .metal files. In a production app, custom shaders
        // would provide better performance.
        
        // The compute pipeline would be set up here for custom Metal compute shaders
        // For this implementation, we'll use CoreImage which provides good performance
        // and handles the Metal integration internally
    }
    
    private func performMaskRendering(_ masks: [SegmentationMask], 
                                    on pixelBuffer: CVPixelBuffer, 
                                    with options: RenderingOptions) throws -> CVPixelBuffer {
        // Create base image from pixel buffer
        let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Start with the base image
        var compositeImage = baseImage
        
        // Apply each mask as an overlay
        for (index, mask) in masks.enumerated() {
            let maskImage = try createMaskOverlay(from: mask, 
                                                at: index, 
                                                with: options,
                                                baseImageExtent: baseImage.extent)
            
            // Composite the mask onto the image
            compositeImage = try compositeMask(maskImage, onto: compositeImage, with: options)
        }
        
        // Create output pixel buffer
        let outputPixelBuffer = try createOutputPixelBuffer(from: pixelBuffer)
        
        // Render the final composite image to the output buffer
        ciContext.render(compositeImage, to: outputPixelBuffer)
        
        return outputPixelBuffer
    }
    
    private func createMaskOverlay(from mask: SegmentationMask, 
                                 at index: Int, 
                                 with options: RenderingOptions,
                                 baseImageExtent: CGRect) throws -> CIImage {
        // Create mask image from pixel buffer
        let maskImage = CIImage(cvPixelBuffer: mask.maskBuffer)
        
        // Get color for this mask
        let colors = options.colors ?? _colorPalette
        let colorIndex = index % colors.count
        let maskColor = colors[colorIndex]
        
        // Convert UIColor to CIColor
        let ciColor = CIColor(color: maskColor)
        
        // Create colored overlay based on rendering mode
        let coloredMask = try createColoredMask(maskImage, 
                                              color: ciColor, 
                                              mode: options.mode ?? _renderingMode,
                                              baseExtent: baseImageExtent)
        
        return coloredMask
    }
    
    private func createColoredMask(_ maskImage: CIImage, 
                                 color: CIColor, 
                                 mode: MaskRenderingMode,
                                 baseExtent: CGRect) throws -> CIImage {
        switch mode {
        case .solid:
            return createSolidMask(maskImage, color: color, baseExtent: baseExtent)
        case .outline:
            return createOutlineMask(maskImage, color: color, baseExtent: baseExtent)
        case .gradient:
            return createGradientMask(maskImage, color: color, baseExtent: baseExtent)
        case .pattern:
            return createPatternMask(maskImage, color: color, baseExtent: baseExtent)
        case .highlight:
            return createHighlightMask(maskImage, color: color, baseExtent: baseExtent)
        }
    }
    
    private func createSolidMask(_ maskImage: CIImage, color: CIColor, baseExtent: CGRect) -> CIImage {
        // Scale mask to match base image if needed
        let scaledMask = scaleMaskToBase(maskImage, baseExtent: baseExtent)
        
        // Create solid color image
        let colorImage = CIImage(color: color).cropped(to: baseExtent)
        
        // Use mask to create colored overlay
        let maskedColor = colorImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: scaledMask
        ])
        
        return maskedColor
    }
    
    private func createOutlineMask(_ maskImage: CIImage, color: CIColor, baseExtent: CGRect) -> CIImage {
        // Scale mask to match base image if needed
        let scaledMask = scaleMaskToBase(maskImage, baseExtent: baseExtent)
        
        // Create edge detection filter to get outline
        let edges = scaledMask.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 1.0
        ])
        
        // Create solid color image
        let colorImage = CIImage(color: color).cropped(to: baseExtent)
        
        // Use edge mask to create colored outline
        let maskedColor = colorImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: edges
        ])
        
        return maskedColor
    }
    
    private func createGradientMask(_ maskImage: CIImage, color: CIColor, baseExtent: CGRect) -> CIImage {
        // For gradient mode, create a radial gradient effect
        let scaledMask = scaleMaskToBase(maskImage, baseExtent: baseExtent)
        
        // Create a radial gradient
        let center = CIVector(x: baseExtent.midX, y: baseExtent.midY)
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": 0,
            "inputRadius1": min(baseExtent.width, baseExtent.height) / 4,
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        ])?.outputImage?.cropped(to: baseExtent)
        
        guard let gradientImage = gradient else {
            return createSolidMask(maskImage, color: color, baseExtent: baseExtent)
        }
        
        // Apply mask to gradient
        let maskedGradient = gradientImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: scaledMask
        ])
        
        return maskedGradient
    }
    
    private func createPatternMask(_ maskImage: CIImage, color: CIColor, baseExtent: CGRect) -> CIImage {
        // For pattern mode, create a simple checkerboard pattern
        let scaledMask = scaleMaskToBase(maskImage, baseExtent: baseExtent)
        
        // Create checkerboard pattern
        let checkerboard = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: baseExtent.midX, y: baseExtent.midY),
            "inputColor0": color,
            "inputColor1": CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * 0.5),
            "inputWidth": 20,
            "inputSharpness": 1.0
        ])?.outputImage?.cropped(to: baseExtent)
        
        guard let patternImage = checkerboard else {
            return createSolidMask(maskImage, color: color, baseExtent: baseExtent)
        }
        
        // Apply mask to pattern
        let maskedPattern = patternImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: scaledMask
        ])
        
        return maskedPattern
    }
    
    private func createHighlightMask(_ maskImage: CIImage, color: CIColor, baseExtent: CGRect) -> CIImage {
        // For highlight mode, create a bright overlay with soft edges
        let scaledMask = scaleMaskToBase(maskImage, baseExtent: baseExtent)
        
        // Create bright highlight color
        let highlightColor = CIColor(red: min(1.0, color.red * 1.5),
                                   green: min(1.0, color.green * 1.5),
                                   blue: min(1.0, color.blue * 1.5),
                                   alpha: color.alpha * 0.7)
        
        // Create highlight image
        let colorImage = CIImage(color: highlightColor).cropped(to: baseExtent)
        
        // Apply gaussian blur to mask for soft edges
        let blurredMask = scaledMask.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: 2.0
        ])
        
        // Use blurred mask to create soft highlight
        let maskedColor = colorImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: blurredMask
        ])
        
        return maskedColor
    }
    
    private func scaleMaskToBase(_ maskImage: CIImage, baseExtent: CGRect) -> CIImage {
        let maskExtent = maskImage.extent
        
        // Calculate scale factors
        let scaleX = baseExtent.width / maskExtent.width
        let scaleY = baseExtent.height / maskExtent.height
        
        // Apply scaling if needed
        if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
            let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            return maskImage.transformed(by: transform)
        }
        
        return maskImage
    }
    
    private func compositeMask(_ maskImage: CIImage, 
                             onto baseImage: CIImage, 
                             with options: RenderingOptions) throws -> CIImage {
        let opacity = options.opacity ?? _opacity
        
        // Apply opacity to mask
        let opacityFilter = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: maskImage,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
        ])
        
        guard let opaqueMask = opacityFilter?.outputImage else {
            throw EdgeTAMError.renderingFailed("Failed to apply opacity to mask")
        }
        
        // Composite mask onto base image using source over blending
        let blendMode = options.blendMode ?? .normal
        let blendFilter = CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: opaqueMask,
            kCIInputBackgroundImageKey: baseImage
        ])
        
        guard let compositeImage = blendFilter?.outputImage else {
            throw EdgeTAMError.renderingFailed("Failed to composite mask onto base image")
        }
        
        return compositeImage
    }
    
    private func createOutputPixelBuffer(from inputBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(inputBuffer)
        let height = CVPixelBufferGetHeight(inputBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(inputBuffer)
        
        var outputBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       width,
                                       height,
                                       pixelFormat,
                                       attributes as CFDictionary,
                                       &outputBuffer)
        
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            throw EdgeTAMError.renderingFailed("Failed to create output pixel buffer")
        }
        
        return buffer
    }
    
    private func updateRenderingMetrics(renderTime: TimeInterval) {
        // Update render time history
        renderTimes.append(renderTime)
        if renderTimes.count > maxRenderTimeHistory {
            renderTimes.removeFirst()
        }
        
        // Calculate metrics
        let averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let totalFrames = _renderingMetrics.totalFramesRendered + 1
        
        // Update metrics
        _renderingMetrics = RenderingMetrics(
            averageRenderTime: averageRenderTime,
            lastRenderTime: renderTime,
            totalFramesRendered: totalFrames,
            droppedFrames: _renderingMetrics.droppedFrames,
            gpuUtilization: estimateGPUUtilization(renderTime: renderTime)
        )
    }
    
    private func estimateGPUUtilization(renderTime: TimeInterval) -> Float {
        // Simple estimation based on render time
        // In a production app, this would use Metal performance counters
        let targetRenderTime: TimeInterval = 1.0 / 60.0 // 60 FPS target
        let utilization = min(1.0, Float(renderTime / targetRenderTime))
        return utilization
    }
}

// MARK: - Error Handling Extensions

extension MaskRenderer {
    private func handleRenderingError(_ error: Error, context: String) -> EdgeTAMError {
        let errorMessage = "\(context): \(error.localizedDescription)"
        return EdgeTAMError.renderingFailed(errorMessage)
    }
}

// MARK: - Performance Optimization

extension MaskRenderer {
    /// Optimizes rendering for low-power mode
    func enableLowPowerMode(_ enabled: Bool) {
        if enabled {
            // Reduce quality for better performance
            _antiAliasingEnabled = false
            _renderingMode = .solid
        } else {
            // Restore full quality
            _antiAliasingEnabled = true
        }
        delegate?.maskRendererDidUpdateSettings(self)
    }
    
    /// Adjusts rendering quality based on thermal state
    func adjustForThermalState(_ thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            // Full quality rendering
            _antiAliasingEnabled = true
        case .fair:
            // Slightly reduced quality
            _antiAliasingEnabled = true
        case .serious:
            // Reduced quality for thermal management
            _antiAliasingEnabled = false
            _renderingMode = .solid
        case .critical:
            // Minimal rendering to prevent overheating
            _antiAliasingEnabled = false
            _renderingMode = .solid
            _opacity = min(_opacity, 0.4)
        @unknown default:
            // Conservative approach for unknown states
            _antiAliasingEnabled = false
        }
        delegate?.maskRendererDidUpdateSettings(self)
    }
}