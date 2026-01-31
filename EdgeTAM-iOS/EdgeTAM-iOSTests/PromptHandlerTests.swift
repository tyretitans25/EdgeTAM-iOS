import XCTest
import CoreGraphics
import CoreVideo
@testable import EdgeTAM_iOS

class PromptHandlerTests: XCTestCase {
    
    var promptHandler: PromptHandler!
    var mockDelegate: MockPromptHandlerDelegate!
    
    override func setUp() {
        super.setUp()
        promptHandler = PromptHandler()
        mockDelegate = MockPromptHandlerDelegate()
        promptHandler.delegate = mockDelegate
    }
    
    override func tearDown() {
        promptHandler = nil
        mockDelegate = nil
        super.tearDown()
    }
    
    // MARK: - Point Prompt Tests
    
    func testAddPointPrompt_ValidInput_AddsPrompt() {
        // Given
        let location = CGPoint(x: 100, y: 150)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addPointPrompt(at: location, in: frame)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Point prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 1)
        XCTAssertEqual(mockDelegate.addedPrompts.count, 1)
        
        if case .point(let pointPrompt) = promptHandler.activePrompts.first {
            XCTAssertEqual(pointPrompt.location, location)
            XCTAssertTrue(pointPrompt.isPositive)
        } else {
            XCTFail("Expected point prompt")
        }
    }
    
    func testAddPointPrompt_CoordinateConversion_CorrectModelCoordinates() {
        // Given
        let location = CGPoint(x: 200, y: 300) // Middle of 400x600 frame
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        let expectedModelX: CGFloat = 512 // 0.5 * 1024
        let expectedModelY: CGFloat = 512 // 0.5 * 1024
        
        // When
        promptHandler.addPointPrompt(at: location, in: frame)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Point prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        if case .point(let pointPrompt) = promptHandler.activePrompts.first {
            XCTAssertEqual(pointPrompt.modelCoordinates.x, expectedModelX, accuracy: 1.0)
            XCTAssertEqual(pointPrompt.modelCoordinates.y, expectedModelY, accuracy: 1.0)
        } else {
            XCTFail("Expected point prompt")
        }
    }
    
    func testAddNegativePointPrompt_ValidInput_AddsNegativePrompt() {
        // Given
        let location = CGPoint(x: 100, y: 150)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addNegativePointPrompt(at: location, in: frame)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Negative point prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 1)
        
        if case .point(let pointPrompt) = promptHandler.activePrompts.first {
            XCTAssertFalse(pointPrompt.isPositive)
        } else {
            XCTFail("Expected point prompt")
        }
    }
    
    // MARK: - Box Prompt Tests
    
    func testAddBoxPrompt_ValidInput_AddsPrompt() {
        // Given
        let rect = CGRect(x: 50, y: 75, width: 100, height: 150)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addBoxPrompt(with: rect, in: frame)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Box prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 1)
        XCTAssertEqual(mockDelegate.addedPrompts.count, 1)
        
        if case .box(let boxPrompt) = promptHandler.activePrompts.first {
            XCTAssertEqual(boxPrompt.rect, rect)
        } else {
            XCTFail("Expected box prompt")
        }
    }
    
    func testAddBoxPrompt_TooSmall_ValidationFails() {
        // Given
        let smallRect = CGRect(x: 50, y: 75, width: 5, height: 5) // Smaller than minimum
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addBoxPrompt(with: smallRect, in: frame)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Box prompt validation failed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 0)
        XCTAssertEqual(mockDelegate.validationErrors.count, 1)
        XCTAssertEqual(mockDelegate.validationErrors.first, .boxTooSmall)
    }
    
    // MARK: - Mask Prompt Tests
    
    func testAddMaskPrompt_ValidInput_AddsPrompt() {
        // Given
        let maskBuffer = createTestPixelBuffer()
        
        // When
        promptHandler.addMaskPrompt(with: maskBuffer)
        
        // Wait for async operation
        let expectation = XCTestExpectation(description: "Mask prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 1)
        XCTAssertEqual(mockDelegate.addedPrompts.count, 1)
        
        if case .mask(let maskPrompt) = promptHandler.activePrompts.first {
            XCTAssertEqual(CVPixelBufferGetWidth(maskPrompt.maskBuffer), 100)
            XCTAssertEqual(CVPixelBufferGetHeight(maskPrompt.maskBuffer), 100)
        } else {
            XCTFail("Expected mask prompt")
        }
    }
    
    // MARK: - Capacity and Validation Tests
    
    func testAddPrompts_ExceedsMaxCapacity_RejectsExtraPrompts() {
        // Given
        promptHandler.maxPrompts = 2
        let location1 = CGPoint(x: 100, y: 150)
        let location2 = CGPoint(x: 200, y: 250)
        let location3 = CGPoint(x: 300, y: 350)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addPointPrompt(at: location1, in: frame)
        promptHandler.addPointPrompt(at: location2, in: frame)
        promptHandler.addPointPrompt(at: location3, in: frame) // Should be rejected
        
        // Wait for async operations
        let expectation = XCTestExpectation(description: "Prompts processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 2)
        XCTAssertEqual(mockDelegate.addedPrompts.count, 2)
        XCTAssertEqual(mockDelegate.validationErrors.count, 1)
        XCTAssertEqual(mockDelegate.validationErrors.first, .tooManyPrompts)
    }
    
    func testValidatePrompt_MinimumDistance_EnforcesDistanceRule() {
        // Given
        promptHandler.validationRules.requireMinimumDistance = 50.0
        let location1 = CGPoint(x: 100, y: 150)
        let location2 = CGPoint(x: 110, y: 160) // Too close to first point
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        // When
        promptHandler.addPointPrompt(at: location1, in: frame)
        promptHandler.addPointPrompt(at: location2, in: frame)
        
        // Wait for async operations
        let expectation = XCTestExpectation(description: "Prompts processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 1) // Only first prompt should be added
        XCTAssertEqual(mockDelegate.validationErrors.count, 1)
        XCTAssertEqual(mockDelegate.validationErrors.first, .insufficientDistance)
    }
    
    // MARK: - Prompt Management Tests
    
    func testRemovePrompt_ValidId_RemovesPrompt() {
        // Given
        let location = CGPoint(x: 100, y: 150)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        promptHandler.addPointPrompt(at: location, in: frame)
        
        // Wait for prompt to be added
        let addExpectation = XCTestExpectation(description: "Point prompt added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        wait(for: [addExpectation], timeout: 1.0)
        
        let promptId = promptHandler.activePrompts.first?.id
        XCTAssertNotNil(promptId)
        
        // When
        promptHandler.removePrompt(withId: promptId!)
        
        // Wait for removal
        let removeExpectation = XCTestExpectation(description: "Prompt removed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            removeExpectation.fulfill()
        }
        wait(for: [removeExpectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 0)
        XCTAssertEqual(mockDelegate.removedPromptIds.count, 1)
        XCTAssertEqual(mockDelegate.removedPromptIds.first, promptId)
    }
    
    func testClearPrompts_WithActivePrompts_RemovesAllPrompts() {
        // Given
        let location1 = CGPoint(x: 100, y: 150)
        let location2 = CGPoint(x: 200, y: 250)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        
        promptHandler.addPointPrompt(at: location1, in: frame)
        promptHandler.addPointPrompt(at: location2, in: frame)
        
        // Wait for prompts to be added
        let addExpectation = XCTestExpectation(description: "Prompts added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        wait(for: [addExpectation], timeout: 1.0)
        
        XCTAssertEqual(promptHandler.activePrompts.count, 2)
        
        // When
        promptHandler.clearPrompts()
        
        // Wait for clearing
        let clearExpectation = XCTestExpectation(description: "Prompts cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(promptHandler.activePrompts.count, 0)
        XCTAssertTrue(mockDelegate.didClearAllPrompts)
    }
    
    // MARK: - Coordinate Conversion Tests
    
    func testConvertToModelCoordinates_VariousInputs_CorrectConversion() {
        // Test cases: (viewPoint, viewFrame, expectedModelPoint)
        let testCases: [(CGPoint, CGRect, CGPoint)] = [
            (CGPoint(x: 0, y: 0), CGRect(x: 0, y: 0, width: 100, height: 100), CGPoint(x: 0, y: 0)),
            (CGPoint(x: 100, y: 100), CGRect(x: 0, y: 0, width: 100, height: 100), CGPoint(x: 1024, y: 1024)),
            (CGPoint(x: 50, y: 50), CGRect(x: 0, y: 0, width: 100, height: 100), CGPoint(x: 512, y: 512)),
            (CGPoint(x: 200, y: 300), CGRect(x: 0, y: 0, width: 400, height: 600), CGPoint(x: 512, y: 512))
        ]
        
        let modelSize = CGSize(width: 1024, height: 1024)
        
        for (viewPoint, viewFrame, expectedModelPoint) in testCases {
            // When
            let result = promptHandler.convertToModelCoordinates(
                viewPoint: viewPoint,
                viewFrame: viewFrame,
                modelSize: modelSize
            )
            
            // Then
            XCTAssertEqual(result.x, expectedModelPoint.x, accuracy: 1.0,
                          "Failed for viewPoint: \(viewPoint), viewFrame: \(viewFrame)")
            XCTAssertEqual(result.y, expectedModelPoint.y, accuracy: 1.0,
                          "Failed for viewPoint: \(viewPoint), viewFrame: \(viewFrame)")
        }
    }
    
    func testConvertToModelCoordinates_OutOfBounds_ClampsToModelBounds() {
        // Given
        let viewPoint = CGPoint(x: -50, y: 150) // Negative x coordinate
        let viewFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let modelSize = CGSize(width: 1024, height: 1024)
        
        // When
        let result = promptHandler.convertToModelCoordinates(
            viewPoint: viewPoint,
            viewFrame: viewFrame,
            modelSize: modelSize
        )
        
        // Then
        XCTAssertEqual(result.x, 0) // Should be clamped to 0
        XCTAssertGreaterThanOrEqual(result.y, 0)
        XCTAssertLessThanOrEqual(result.y, modelSize.height)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentPromptAddition_ThreadSafe_NoDataRace() {
        // Given
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        let expectation = XCTestExpectation(description: "Concurrent operations completed")
        expectation.expectedFulfillmentCount = 10
        
        // When - Add prompts concurrently from multiple threads
        for i in 0..<10 {
            DispatchQueue.global().async {
                let location = CGPoint(x: CGFloat(i * 30), y: CGFloat(i * 40))
                self.promptHandler.addPointPrompt(at: location, in: frame)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Wait a bit more for all async operations to complete
        let finalExpectation = XCTestExpectation(description: "Final state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            finalExpectation.fulfill()
        }
        wait(for: [finalExpectation], timeout: 1.0)
        
        // Then
        XCTAssertLessThanOrEqual(promptHandler.activePrompts.count, promptHandler.maxPrompts)
        XCTAssertGreaterThan(promptHandler.activePrompts.count, 0)
    }
    
    // MARK: - Convenience Methods Tests
    
    func testGetPointPrompts_WithMixedPrompts_ReturnsOnlyPointPrompts() {
        // Given
        let location = CGPoint(x: 100, y: 150)
        let rect = CGRect(x: 50, y: 75, width: 100, height: 150)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        let maskBuffer = createTestPixelBuffer()
        
        promptHandler.addPointPrompt(at: location, in: frame)
        promptHandler.addBoxPrompt(with: rect, in: frame)
        promptHandler.addMaskPrompt(with: maskBuffer)
        
        // Wait for prompts to be added
        let expectation = XCTestExpectation(description: "Prompts added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // When
        let pointPrompts = promptHandler.getPointPrompts()
        let boxPrompts = promptHandler.getBoxPrompts()
        let maskPrompts = promptHandler.getMaskPrompts()
        
        // Then
        XCTAssertEqual(pointPrompts.count, 1)
        XCTAssertEqual(boxPrompts.count, 1)
        XCTAssertEqual(maskPrompts.count, 1)
        XCTAssertEqual(promptHandler.activePrompts.count, 3)
    }
    
    // MARK: - Helper Methods
    
    private func createTestPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            100, 100,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        XCTAssertEqual(status, kCVReturnSuccess)
        XCTAssertNotNil(pixelBuffer)
        
        return pixelBuffer!
    }
}

// MARK: - Mock Delegate

class MockPromptHandlerDelegate: PromptHandlerDelegate {
    var addedPrompts: [Prompt] = []
    var removedPromptIds: [UUID] = []
    var didClearAllPrompts = false
    var validationErrors: [PromptValidationError] = []
    
    func promptHandler(_ handler: PromptHandlerProtocol, didAddPrompt prompt: Prompt) {
        addedPrompts.append(prompt)
    }
    
    func promptHandler(_ handler: PromptHandlerProtocol, didRemovePrompt promptId: UUID) {
        removedPromptIds.append(promptId)
    }
    
    func promptHandlerDidClearAllPrompts(_ handler: PromptHandlerProtocol) {
        didClearAllPrompts = true
    }
    
    func promptHandler(_ handler: PromptHandlerProtocol, 
                      didFailValidation prompt: Prompt, 
                      reason: PromptValidationError) {
        validationErrors.append(reason)
    }
}