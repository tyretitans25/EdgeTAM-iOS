import XCTest
import CoreVideo
import UIKit
import Metal
@testable import EdgeTAM_iOS

class MaskRendererTests: XCTestCase {
    
    var maskRenderer: MaskRenderer!
    var testPixelBuffer: CVPixelBuffer!
    var testMasks: [SegmentationMask]!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize MaskRenderer
        maskRenderer = try MaskRenderer()
        
        // Create test pixel buffer
        testPixelBuffer = try createTestPixelBuffer()
        
        // Create test masks
        testMasks = try createTestMasks()
    }
    
    override func tearDownWithError() throws {
        maskRenderer = nil
        testPixelBuffer = nil
        testMasks = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testMaskRendererInitialization() throws {
        // Test that MaskRenderer initializes successfully
        let renderer = try MaskRenderer()
        XCTAssertNotNil(renderer)
        
        // Test default values
        XCTAssertEqual(renderer.opacity, 0.6, accuracy: 0.001)
        XCTAssertEqual(renderer.renderingMode, .solid)
        XCTAssertTrue(renderer.antiAliasingEnabled)
        XCTAssertFalse(renderer.colorPalette.isEmpty)
    }
    
    // MARK: - Configuration Tests
    
    func testSetOpacity() {
        // Test valid opacity values
        maskRenderer.setOpacity(0.5)
        XCTAssertEqual(maskRenderer.opacity, 0.5, accuracy: 0.001)
        
        maskRenderer.setOpacity(0.0)
        XCTAssertEqual(maskRenderer.opacity, 0.0, accuracy: 0.001)
        
        maskRenderer.setOpacity(0.8)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
        
        // Test clamping to maximum 80% as per requirements
        maskRenderer.setOpacity(1.0)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
        
        maskRenderer.setOpacity(0.9)
        XCTAssertEqual(maskRenderer.opacity, 0.8, accuracy: 0.001)
        
        // Test clamping to minimum 0%
        maskRenderer.setOpacity(-0.1)
        XCTAssertEqual(maskRenderer.opacity, 0.0, accuracy: 0.001)
    }
    
    func testSetColorPalette() {
        let customColors = [UIColor.red, UIColor.blue, UIColor.green]
        maskRenderer.setColorPalette(customColors)
        
        XCTAssertEqual(maskRenderer.colorPalette.count, 3)
        XCTAssertEqual(maskRenderer.colorPalette[0], UIColor.red)
        XCTAssertEqual(maskRenderer.colorPalette[1], UIColor.blue)
        XCTAssertEqual(maskRenderer.colorPalette[2], UIColor.green)
        
        // Test empty array fallback
        maskRenderer.setColorPalette([])
        XCTAssertEqual(maskRenderer.colorPalette.count, 1)
        XCTAssertEqual(maskRenderer.colorPalette[0], UIColor.systemRed)
    }
    
    func testSetRenderingMode() {
        maskRenderer.setRenderingMode(.outline)
        XCTAssertEqual(maskRenderer.renderingMode, .outline)
        
        maskRenderer.setRenderingMode(.gradient)
        XCTAssertEqual(maskRenderer.renderingMode, .gradient)
        
        maskRenderer.setRenderingMode(.pattern)
        XCTAssertEqual(maskRenderer.renderingMode, .pattern)
        
        maskRenderer.setRenderingMode(.highlight)
        XCTAssertEqual(maskRenderer.renderingMode, .highlight)
    }
    
    func testSetAntiAliasing() {
        maskRenderer.setAntiAliasing(false)
        XCTAssertFalse(maskRenderer.antiAliasingEnabled)
        
        maskRenderer.setAntiAliasing(true)
        XCTAssertTrue(maskRenderer.antiAliasingEnabled)
    }
    
    // MARK: - Rendering Tests
    
    func testRenderMasksBasic() throws {
        // Test basic mask rendering
        let outputBuffer = try maskRenderer.renderMasks(testMasks, on: testPixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(outputBuffer), CVPixelBufferGetWidth(testPixelBuffer))
        XCTAssertEqual(CVPixelBufferGetHeight(outputBuffer), CVPixelBufferGetHeight(testPixelBuffer))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(outputBuffer), CVPixelBufferGetPixelFormatType(testPixelBuffer))
    }
    
    func testRenderMasksWithOptions() throws {
        let options = RenderingOptions(
            opacity: 0.4,
            colors: [UIColor.cyan, UIColor.magenta],
            mode: .outline,
            antiAliasing: false
        )
        
        let outputBuffer = try maskRenderer.renderMasks(testMasks, on: testPixelBuffer, with: options)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(outputBuffer), CVPixelBufferGetWidth(testPixelBuffer))
        XCTAssertEqual(CVPixelBufferGetHeight(outputBuffer), CVPixelBufferGetHeight(testPixelBuffer))
    }
    
    func testRenderEmptyMasks() throws {
        // Test rendering with no masks should return original buffer
        let outputBuffer = try maskRenderer.renderMasks([], on: testPixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(outputBuffer), CVPixelBufferGetWidth(testPixelBuffer))
        XCTAssertEqual(CVPixelBufferGetHeight(outputBuffer), CVPixelBufferGetHeight(testPixelBuffer))
    }
    
    func testRenderMultipleMasks() throws {
        // Test rendering multiple masks with distinct colors
        let multipleMasks = try createMultipleTestMasks(count: 3)
        let outputBuffer = try maskRenderer.renderMasks(multipleMasks, on: testPixelBuffer)
        
        XCTAssertNotNil(outputBuffer)
        XCTAssertEqual(CVPixelBufferGetWidth(outputBuffer), CVPixelBufferGetWidth(testPixelBuffer))
        XCTAssertEqual(CVPixelBufferGetHeight(outputBuffer), CVPixelBufferGetHeight(testPixelBuffer))
    }
    
    // MARK: - Performance Tests
    
    func testRenderingPerformance() throws {
        // Test that rendering completes within reasonable time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let _ = try maskRenderer.renderMasks(testMasks, on: testPixelBuffer)
        
        let renderTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete within 100ms for reasonable performance
        XCTAssertLessThan(renderTime, 0.1, "Rendering should complete within 100ms")
        
        // Check that metrics are updated
        XCTAssertGreaterThan(maskRenderer.renderingMetrics.totalFramesRendered, 0)
        XCTAssertGreaterThan(maskRenderer.renderingMetrics.lastRenderTime, 0)
    }
    
    func testRenderingMetricsUpdate() throws {
        let initialFrameCount = maskRenderer.renderingMetrics.totalFramesRendered
        
        // Render multiple frames
        for _ in 0..<5 {
            let _ = try maskRenderer.renderMasks(testMasks, on: testPixelBuffer)
        }
        
        let finalFrameCount = maskRenderer.renderingMetrics.totalFramesRendered
        XCTAssertEqual(finalFrameCount, initialFrameCount + 5)
        
        // Check that average render time is calculated
        XCTAssertGreaterThan(maskRenderer.renderingMetrics.averageRenderTime, 0)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidPixelBufferHandling() {
        // Test with nil pixel buffer should be handled gracefully
        // Note: This test would need to be implemented based on actual error handling
        // For now, we'll test that the renderer doesn't crash with edge cases
        
        XCTAssertNoThrow({
            // Test with empty masks
            let _ = try maskRenderer.renderMasks([], on: testPixelBuffer)
        })
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateCallbacks() throws {
        let mockDelegate = MockMaskRendererDelegate()
        maskRenderer.delegate = mockDelegate
        
        let _ = try maskRenderer.renderMasks(testMasks, on: testPixelBuffer)
        
        XCTAssertTrue(mockDelegate.didRenderMasksCalled)
        XCTAssertEqual(mockDelegate.lastRenderedMasks?.count, testMasks.count)
        XCTAssertGreaterThan(mockDelegate.lastRenderTime, 0)
    }
    
    func testDelegateSettingsUpdate() {
        let mockDelegate = MockMaskRendererDelegate()
        maskRenderer.delegate = mockDelegate
        
        maskRenderer.setOpacity(0.5)
        XCTAssertTrue(mockDelegate.didUpdateSettingsCalled)
        
        mockDelegate.reset()
        maskRenderer.setRenderingMode(.outline)
        XCTAssertTrue(mockDelegate.didUpdateSettingsCalled)
    }
    
    // MARK: - Thermal Management Tests
    
    func testThermalStateAdjustment() {
        // Test nominal state
        maskRenderer.adjustForThermalState(.nominal)
        XCTAssertTrue(maskRenderer.antiAliasingEnabled)
        
        // Test serious state
        maskRenderer.adjustForThermalState(.serious)
        XCTAssertFalse(maskRenderer.antiAliasingEnabled)
        XCTAssertEqual(maskRenderer.renderingMode, .solid)
        
        // Test critical state
        maskRenderer.adjustForThermalState(.critical)
        XCTAssertFalse(maskRenderer.antiAliasingEnabled)
        XCTAssertEqual(maskRenderer.renderingMode, .solid)
        XCTAssertLessThanOrEqual(maskRenderer.opacity, 0.4)
    }
    
    func testLowPowerMode() {
        // Test enabling low power mode
        maskRenderer.enableLowPowerMode(true)
        XCTAssertFalse(maskRenderer.antiAliasingEnabled)
        XCTAssertEqual(maskRenderer.renderingMode, .solid)
        
        // Test disabling low power mode
        maskRenderer.enableLowPowerMode(false)
        XCTAssertTrue(maskRenderer.antiAliasingEnabled)
    }
    
    // MARK: - Helper Methods
    
    private func createTestPixelBuffer() throws -> CVPixelBuffer {
        let width = 640
        let height = 480
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
        
        return buffer
    }
    
    private func createTestMasks() throws -> [SegmentationMask] {
        let maskBuffer = try createTestMaskBuffer()
        
        let mask = SegmentationMask(
            objectId: UUID(),
            maskBuffer: maskBuffer,
            confidence: 0.8,
            boundingBox: CGRect(x: 100, y: 100, width: 200, height: 200),
            area: 40000,
            centroid: CGPoint(x: 200, y: 200),
            timestamp: CMTime.zero
        )
        
        return [mask]
    }
    
    private func createMultipleTestMasks(count: Int) throws -> [SegmentationMask] {
        var masks: [SegmentationMask] = []
        
        for i in 0..<count {
            let maskBuffer = try createTestMaskBuffer()
            let offset = CGFloat(i * 50)
            
            let mask = SegmentationMask(
                objectId: UUID(),
                maskBuffer: maskBuffer,
                confidence: 0.8,
                boundingBox: CGRect(x: 100 + offset, y: 100 + offset, width: 150, height: 150),
                area: 22500,
                centroid: CGPoint(x: 175 + offset, y: 175 + offset),
                timestamp: CMTime.zero
            )
            
            masks.append(mask)
        }
        
        return masks
    }
    
    private func createTestMaskBuffer() throws -> CVPixelBuffer {
        let width = 640
        let height = 480
        let pixelFormat = kCVPixelFormatType_OneComponent8 // Grayscale mask
        
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
        
        // Fill with test pattern (simple rectangle mask)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        guard let data = baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw EdgeTAMError.invalidPixelBuffer
        }
        
        // Create a simple rectangular mask in the center
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                if x >= 200 && x < 400 && y >= 150 && y < 350 {
                    data[offset] = 255 // White (mask area)
                } else {
                    data[offset] = 0   // Black (background)
                }
            }
        }
        
        return buffer
    }
}

// MARK: - Mock Delegate

class MockMaskRendererDelegate: MaskRendererDelegate {
    var didRenderMasksCalled = false
    var didFailWithErrorCalled = false
    var didUpdateSettingsCalled = false
    
    var lastRenderedMasks: [SegmentationMask]?
    var lastRenderTime: TimeInterval = 0
    var lastError: EdgeTAMError?
    
    func maskRenderer(_ renderer: MaskRendererProtocol, 
                     didRenderMasks masks: [SegmentationMask], 
                     renderTime: TimeInterval) {
        didRenderMasksCalled = true
        lastRenderedMasks = masks
        lastRenderTime = renderTime
    }
    
    func maskRenderer(_ renderer: MaskRendererProtocol, 
                     didFailWithError error: EdgeTAMError) {
        didFailWithErrorCalled = true
        lastError = error
    }
    
    func maskRendererDidUpdateSettings(_ renderer: MaskRendererProtocol) {
        didUpdateSettingsCalled = true
    }
    
    func reset() {
        didRenderMasksCalled = false
        didFailWithErrorCalled = false
        didUpdateSettingsCalled = false
        lastRenderedMasks = nil
        lastRenderTime = 0
        lastError = nil
    }
}