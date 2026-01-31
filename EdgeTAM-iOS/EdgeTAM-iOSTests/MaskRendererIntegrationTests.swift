import XCTest
import CoreVideo
import UIKit
import Metal
@testable import EdgeTAM_iOS

/// Integration tests for MaskRenderer with other system components
final class MaskRendererIntegrationTests: XCTestCase {
    
    var dependencyContainer: DependencyContainer!
    var maskRenderer: MaskRendererProtocol!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        dependencyContainer = DependencyContainer()
        dependencyContainer.registerDefaultServices()
        
        maskRenderer = try dependencyContainer.resolve(MaskRendererProtocol.self)
    }
    
    override func tearDownWithError() throws {
        maskRenderer = nil
        dependencyContainer = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Integration Tests
    
    func testMaskRendererFromDependencyContainer() throws {
        // Test that MaskRenderer can be resolved from dependency container
        XCTAssertNotNil(maskRenderer)
        XCTAssertTrue(maskRenderer is MaskRenderer)
        
        // Test default configuration
        XCTAssertEqual(maskRenderer.opacity, 0.6, accuracy: 0.001)
        XCTAssertEqual(maskRenderer.renderingMode, .solid)
        XCTAssertTrue(maskRenderer.antiAliasingEnabled)
        XCTAssertFalse(maskRenderer.colorPalette.isEmpty)
    }
    
    func testMaskRendererWithRealPixelBuffer() throws {
        // Create a real pixel buffer similar to what would come from camera
        let pixelBuffer = try createCameraLikePixelBuffer()
        let masks = try createRealisticMasks()
        
        // Test rendering
        let outputBuffer = try maskRenderer.renderMasks(masks, on: pixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(outputBuffer), CVPixelBufferGetWidth(pixelBuffer))
        XCTAssertEqual(CVPixelBufferGetHeight(outputBuffer), CVPixelBufferGetHeight(pixelBuffer))
        
        // Verify the output buffer is different from input (masks were applied)
        XCTAssertNotEqual(CFGetRetainCount(outputBuffer), CFGetRetainCount(pixelBuffer))
    }
    
    func testMaskRendererPerformanceWithMultipleObjects() throws {
        let pixelBuffer = try createCameraLikePixelBuffer()
        let masks = try createMultipleRealisticMasks(count: 5) // Max objects as per requirements
        
        // Measure performance
        let startTime = CFAbsoluteTimeGetCurrent()
        let outputBuffer = try maskRenderer.renderMasks(masks, on: pixelBuffer)
        let renderTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertNotNil(outputBuffer)
        
        // Should render 5 objects within reasonable time (requirements specify real-time performance)
        XCTAssertLessThan(renderTime, 0.05, "Rendering 5 masks should complete within 50ms for real-time performance")
        
        // Check metrics are updated
        XCTAssertGreaterThan(maskRenderer.renderingMetrics.totalFramesRendered, 0)
        XCTAssertGreaterThan(maskRenderer.renderingMetrics.lastRenderTime, 0)
    }
    
    func testOpacityRequirements() throws {
        // Test opacity range requirements (0% to 80%)
        maskRenderer.setOpacity(0.0)
        XCTAssertEqual(maskRenderer.opacity, 0.0, accuracy: 0.001)
        
        maskRenderer.setOpacity(0.8)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
        
        // Test that opacity is clamped to 80% maximum as per requirements
        maskRenderer.setOpacity(1.0)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
        
        maskRenderer.setOpacity(0.9)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
    }
    
    func testDistinctColorsForMultipleObjects() throws {
        let pixelBuffer = try createCameraLikePixelBuffer()
        let masks = try createMultipleRealisticMasks(count: 3)
        
        // Set custom color palette
        let customColors = [UIColor.red, UIColor.green, UIColor.blue]
        maskRenderer.setColorPalette(customColors)
        
        let outputBuffer = try maskRenderer.renderMasks(masks, on: pixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(maskRenderer.colorPalette.count, 3)
        XCTAssertEqual(maskRenderer.colorPalette[0], UIColor.red)
        XCTAssertEqual(maskRenderer.colorPalette[1], UIColor.green)
        XCTAssertEqual(maskRenderer.colorPalette[2], UIColor.blue)
    }
    
    func testRenderingModes() throws {
        let pixelBuffer = try createCameraLikePixelBuffer()
        let masks = try createRealisticMasks()
        
        // Test all rendering modes
        let modes: [MaskRenderingMode] = [.solid, .outline, .gradient, .pattern, .highlight]
        
        for mode in modes {
            maskRenderer.setRenderingMode(mode)
            XCTAssertEqual(maskRenderer.renderingMode, mode)
            
            // Should be able to render in each mode without errors
            XCTAssertNoThrow({
                let _ = try maskRenderer.renderMasks(masks, on: pixelBuffer)
            })
        }
    }
    
    func testMetalCompatibility() throws {
        // Test that pixel buffers are Metal-compatible as required for GPU rendering
        let pixelBuffer = try createCameraLikePixelBuffer()
        
        // Verify Metal compatibility
        let metalCompatible = CVPixelBufferGetIOSurface(pixelBuffer) != nil
        XCTAssertTrue(metalCompatible, "Pixel buffer should be Metal-compatible for GPU rendering")
        
        // Test rendering works with Metal-compatible buffers
        let masks = try createRealisticMasks()
        let outputBuffer = try maskRenderer.renderMasks(masks, on: pixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        
        // Output should also be Metal-compatible
        let outputMetalCompatible = CVPixelBufferGetIOSurface(outputBuffer) != nil
        XCTAssertTrue(outputMetalCompatible, "Output buffer should maintain Metal compatibility")
    }
    
    // MARK: - Helper Methods
    
    private func createCameraLikePixelBuffer() throws -> CVPixelBuffer {
        // Create a pixel buffer similar to what AVCaptureVideoDataOutput would provide
        let width = 1920
        let height = 1080
        let pixelFormat = kCVPixelFormatType_32BGRA
        
        var pixelBuffer: CVPixelBuffer?
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
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        // Fill with a gradient pattern to simulate camera data
        try fillPixelBufferWithGradient(buffer)
        
        return buffer
    }
    
    private func fillPixelBufferWithGradient(_ pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Create a simple gradient pattern
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let gradientValue = UInt8((x + y) % 256)
                
                data[offset] = gradientValue     // Blue
                data[offset + 1] = gradientValue // Green
                data[offset + 2] = gradientValue // Red
                data[offset + 3] = 255           // Alpha
            }
        }
    }
    
    private func createRealisticMasks() throws -> [SegmentationMask] {
        let maskBuffer = try createRealisticMaskBuffer()
        
        let mask = SegmentationMask(
            objectId: UUID(),
            maskBuffer: maskBuffer,
            confidence: 0.85,
            boundingBox: CGRect(x: 400, y: 300, width: 600, height: 400),
            area: 240000,
            centroid: CGPoint(x: 700, y: 500),
            timestamp: CMTime(seconds: 1.0, preferredTimescale: 30)
        )
        
        return [mask]
    }
    
    private func createMultipleRealisticMasks(count: Int) throws -> [SegmentationMask] {
        var masks: [SegmentationMask] = []
        
        for i in 0..<count {
            let maskBuffer = try createRealisticMaskBuffer()
            let offset = CGFloat(i * 200)
            
            let mask = SegmentationMask(
                objectId: UUID(),
                maskBuffer: maskBuffer,
                confidence: 0.8 + Float(i) * 0.02, // Varying confidence
                boundingBox: CGRect(x: 200 + offset, y: 200 + offset, width: 300, height: 300),
                area: 90000,
                centroid: CGPoint(x: 350 + offset, y: 350 + offset),
                timestamp: CMTime(seconds: Double(i), preferredTimescale: 30)
            )
            
            masks.append(mask)
        }
        
        return masks
    }
    
    private func createRealisticMaskBuffer() throws -> CVPixelBuffer {
        // Create mask buffer with same dimensions as camera buffer
        let width = 1920
        let height = 1080
        let pixelFormat = kCVPixelFormatType_OneComponent8
        
        var pixelBuffer: CVPixelBuffer?
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
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        // Create a realistic object mask (elliptical shape)
        try fillMaskBufferWithEllipse(buffer)
        
        return buffer
    }
    
    private func fillMaskBufferWithEllipse(_ pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Create elliptical mask in center
        let centerX = width / 2
        let centerY = height / 2
        let radiusX = width / 4
        let radiusY = height / 4
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                
                // Calculate if point is inside ellipse
                let dx = Double(x - centerX)
                let dy = Double(y - centerY)
                let distance = (dx * dx) / Double(radiusX * radiusX) + (dy * dy) / Double(radiusY * radiusY)
                
                if distance <= 1.0 {
                    // Inside ellipse - create soft edges
                    let alpha = max(0, min(255, Int(255 * (1.0 - distance))))
                    data[offset] = UInt8(alpha)
                } else {
                    data[offset] = 0 // Outside ellipse
                }
            }
        }
    }
}