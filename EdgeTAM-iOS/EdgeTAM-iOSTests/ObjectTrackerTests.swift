import XCTest
import CoreVideo
import CoreMedia
@testable import EdgeTAM_iOS

class ObjectTrackerTests: XCTestCase {
    
    var objectTracker: ObjectTracker!
    var mockDelegate: MockObjectTrackerDelegate!
    
    override func setUp() {
        super.setUp()
        objectTracker = ObjectTracker()
        mockDelegate = MockObjectTrackerDelegate()
        objectTracker.delegate = mockDelegate
    }
    
    override func tearDown() {
        objectTracker = nil
        mockDelegate = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(objectTracker.maxTrackedObjects, 5)
        XCTAssertEqual(objectTracker.confidenceThreshold, 0.7)
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        XCTAssertNotNil(objectTracker.configuration)
    }
    
    func testConfigurationDefaults() {
        let config = objectTracker.configuration
        XCTAssertEqual(config.maxTrajectoryLength, 30)
        XCTAssertEqual(config.reacquisitionAttempts, 5)
        XCTAssertEqual(config.temporalSmoothingFactor, 0.8)
        XCTAssertTrue(config.motionPredictionEnabled)
        XCTAssertTrue(config.occlusionHandlingEnabled)
    }
    
    // MARK: - Tracking Initialization Tests
    
    func testInitializeTrackingWithValidObjects() throws {
        let segmentedObjects = createMockSegmentedObjects(count: 3)
        
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        XCTAssertEqual(objectTracker.trackedObjects.count, 3)
        XCTAssertEqual(mockDelegate.initializeTrackingCallCount, 1)
        XCTAssertEqual(mockDelegate.lastInitializedObjects?.count, 3)
        
        // Verify each tracked object has correct initial state
        for (index, trackedObject) in objectTracker.trackedObjects.enumerated() {
            XCTAssertEqual(trackedObject.id, segmentedObjects[index].id)
            XCTAssertEqual(trackedObject.masks.count, 1)
            XCTAssertEqual(trackedObject.trajectory.count, 1)
            XCTAssertTrue(trackedObject.isActive)
            XCTAssertEqual(trackedObject.confidence, segmentedObjects[index].mask.confidence)
        }
    }
    
    func testInitializeTrackingExceedsMaxObjects() {
        let segmentedObjects = createMockSegmentedObjects(count: 6) // Exceeds default max of 5
        
        XCTAssertThrowsError(try objectTracker.initializeTracking(for: segmentedObjects)) { error in
            guard case EdgeTAMError.trackingFailed(let message) = error else {
                XCTFail("Expected trackingFailed error")
                return
            }
            XCTAssertTrue(message.contains("Cannot track more than 5 objects"))
        }
    }
    
    func testInitializeTrackingClearsExistingObjects() throws {
        // Initialize with some objects first
        let initialObjects = createMockSegmentedObjects(count: 2)
        try objectTracker.initializeTracking(for: initialObjects)
        XCTAssertEqual(objectTracker.trackedObjects.count, 2)
        
        // Initialize with new objects
        let newObjects = createMockSegmentedObjects(count: 3)
        try objectTracker.initializeTracking(for: newObjects)
        
        XCTAssertEqual(objectTracker.trackedObjects.count, 3)
        // Verify the objects are the new ones, not the old ones
        for (index, trackedObject) in objectTracker.trackedObjects.enumerated() {
            XCTAssertEqual(trackedObject.id, newObjects[index].id)
        }
    }
    
    // MARK: - Object Removal Tests
    
    func testRemoveObjectById() throws {
        let segmentedObjects = createMockSegmentedObjects(count: 3)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        let objectIdToRemove = segmentedObjects[1].id
        objectTracker.removeObject(withId: objectIdToRemove)
        
        XCTAssertEqual(objectTracker.trackedObjects.count, 2)
        XCTAssertFalse(objectTracker.trackedObjects.contains { $0.id == objectIdToRemove })
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 1)
        XCTAssertEqual(mockDelegate.lastRemovedObjectId, objectIdToRemove)
    }
    
    // MARK: - Camera Switching Tests
    
    func testHandleCameraSwitchClearsAllTracking() throws {
        // Initialize with some objects
        let segmentedObjects = createMockSegmentedObjects(count: 3)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        XCTAssertEqual(objectTracker.trackedObjects.count, 3)
        XCTAssertFalse(objectTracker.trackedObjects.isEmpty)
        
        // Handle camera switch
        objectTracker.handleCameraSwitch()
        
        // Verify all tracking state is cleared
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 3) // Should remove all 3 objects
    }
    
    func testHandleCameraSwitchWithNoObjects() {
        // Test camera switch when no objects are being tracked
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        
        // Should not crash or cause issues
        XCTAssertNoThrow(objectTracker.handleCameraSwitch())
        
        // State should remain empty
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 0)
    }
    
    func testCameraSwitchVsClearAllObjects() throws {
        // Initialize with objects
        let segmentedObjects = createMockSegmentedObjects(count: 2)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        // Both methods should have the same end result
        let trackerForClearAll = ObjectTracker()
        let mockDelegateForClearAll = MockObjectTrackerDelegate()
        trackerForClearAll.delegate = mockDelegateForClearAll
        try trackerForClearAll.initializeTracking(for: segmentedObjects)
        
        // Test camera switch
        objectTracker.handleCameraSwitch()
        
        // Test clear all
        trackerForClearAll.clearAllObjects()
        
        // Both should result in empty tracking state
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        XCTAssertTrue(trackerForClearAll.trackedObjects.isEmpty)
        
        // Both should notify delegate of removed objects
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 2)
        XCTAssertEqual(mockDelegateForClearAll.removeObjectCallCount, 2)
    }
        XCTAssertEqual(objectTracker.trackedObjects.count, 2)
        XCTAssertFalse(objectTracker.trackedObjects.contains { $0.id == objectIdToRemove })
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 1)
        XCTAssertEqual(mockDelegate.lastRemovedObjectId, objectIdToRemove)
    }
    
    func testRemoveNonExistentObject() throws {
        let segmentedObjects = createMockSegmentedObjects(count: 2)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        let nonExistentId = UUID()
        objectTracker.removeObject(withId: nonExistentId)
        
        // Should not crash and should not affect existing objects
        XCTAssertEqual(objectTracker.trackedObjects.count, 2)
    }
    
    func testClearAllObjects() throws {
        let segmentedObjects = createMockSegmentedObjects(count: 3)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        objectTracker.clearAllObjects()
        
        XCTAssertTrue(objectTracker.trackedObjects.isEmpty)
        XCTAssertEqual(mockDelegate.removeObjectCallCount, 3) // Should call for each removed object
    }
    
    // MARK: - Configuration Tests
    
    func testMaxTrackedObjectsConfiguration() {
        objectTracker.maxTrackedObjects = 10
        XCTAssertEqual(objectTracker.maxTrackedObjects, 10)
        
        let segmentedObjects = createMockSegmentedObjects(count: 8)
        XCTAssertNoThrow(try objectTracker.initializeTracking(for: segmentedObjects))
        XCTAssertEqual(objectTracker.trackedObjects.count, 8)
    }
    
    func testConfidenceThresholdConfiguration() {
        objectTracker.confidenceThreshold = 0.9
        XCTAssertEqual(objectTracker.confidenceThreshold, 0.9)
    }
    
    func testTrackingConfiguration() {
        let customConfig = TrackingConfiguration(
            maxTrajectoryLength: 50,
            reacquisitionAttempts: 10,
            temporalSmoothingFactor: 0.5,
            motionPredictionEnabled: false,
            occlusionHandlingEnabled: false
        )
        
        objectTracker.configuration = customConfig
        
        XCTAssertEqual(objectTracker.configuration.maxTrajectoryLength, 50)
        XCTAssertEqual(objectTracker.configuration.reacquisitionAttempts, 10)
        XCTAssertEqual(objectTracker.configuration.temporalSmoothingFactor, 0.5)
        XCTAssertFalse(objectTracker.configuration.motionPredictionEnabled)
        XCTAssertFalse(objectTracker.configuration.occlusionHandlingEnabled)
    }
    
    // MARK: - Update Tracking Tests
    
    func testUpdateTrackingWithMatchingMasks() throws {
        // Initialize tracking
        let segmentedObjects = createMockSegmentedObjects(count: 2)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        // Create a new frame with updated masks
        let newFrame = createMockProcessedFrame(
            frameNumber: 2,
            masks: createMockSegmentationMasks(
                objectIds: segmentedObjects.map { $0.id },
                confidences: [0.8, 0.9],
                centroids: [CGPoint(x: 105, y: 105), CGPoint(x: 205, y: 205)]
            )
        )
        
        let updatedObjects = try objectTracker.updateTracking(with: newFrame)
        
        XCTAssertEqual(updatedObjects.count, 2)
        XCTAssertEqual(mockDelegate.updateTrackingCallCount, 1)
        
        // Verify trajectory was updated
        for trackedObject in updatedObjects {
            XCTAssertEqual(trackedObject.trajectory.count, 2) // Initial + updated position
            XCTAssertEqual(trackedObject.masks.count, 2) // Initial + updated mask
        }
    }
    
    func testUpdateTrackingWithLowConfidenceMasks() throws {
        // Initialize tracking
        let segmentedObjects = createMockSegmentedObjects(count: 1)
        try objectTracker.initializeTracking(for: segmentedObjects)
        
        // Create a new frame with low confidence mask
        let newFrame = createMockProcessedFrame(
            frameNumber: 2,
            masks: createMockSegmentationMasks(
                objectIds: [segmentedObjects[0].id],
                confidences: [0.5], // Below default threshold of 0.7
                centroids: [CGPoint(x: 105, y: 105)]
            )
        )
        
        let updatedObjects = try objectTracker.updateTracking(with: newFrame)
        
        // Object should be lost due to low confidence
        XCTAssertEqual(updatedObjects.count, 0)
        XCTAssertEqual(mockDelegate.loseObjectCallCount, 1)
    }
    
    // MARK: - Helper Methods
    
    private func createMockSegmentedObjects(count: Int) -> [SegmentedObject] {
        var objects: [SegmentedObject] = []
        
        for i in 0..<count {
            let objectId = UUID()
            let mask = createMockSegmentationMask(
                objectId: objectId,
                confidence: 0.8,
                centroid: CGPoint(x: 100 + i * 100, y: 100 + i * 100)
            )
            let prompt = Prompt.point(PointPrompt(
                location: CGPoint(x: 100 + i * 100, y: 100 + i * 100),
                modelCoordinates: CGPoint(x: 100 + i * 100, y: 100 + i * 100)
            ))
            let frame = createMockProcessedFrame(frameNumber: 1, masks: [mask])
            
            let segmentedObject = SegmentedObject(
                id: objectId,
                mask: mask,
                prompt: prompt,
                initialFrame: frame
            )
            objects.append(segmentedObject)
        }
        
        return objects
    }
    
    private func createMockSegmentationMask(objectId: UUID, confidence: Float, centroid: CGPoint) -> SegmentationMask {
        let pixelBuffer = createMockPixelBuffer()
        return SegmentationMask(
            objectId: objectId,
            maskBuffer: pixelBuffer,
            confidence: confidence,
            boundingBox: CGRect(x: centroid.x - 50, y: centroid.y - 50, width: 100, height: 100),
            area: 10000,
            centroid: centroid,
            timestamp: CMTime(seconds: 1.0, preferredTimescale: 30)
        )
    }
    
    private func createMockSegmentationMasks(objectIds: [UUID], confidences: [Float], centroids: [CGPoint]) -> [SegmentationMask] {
        var masks: [SegmentationMask] = []
        
        for (index, objectId) in objectIds.enumerated() {
            let mask = createMockSegmentationMask(
                objectId: objectId,
                confidence: confidences[index],
                centroid: centroids[index]
            )
            masks.append(mask)
        }
        
        return masks
    }
    
    private func createMockProcessedFrame(frameNumber: Int, masks: [SegmentationMask]) -> ProcessedFrame {
        let pixelBuffer = createMockPixelBuffer()
        let metadata = FrameMetadata(
            frameNumber: frameNumber,
            processingTime: 0.016,
            inferenceTime: 0.050,
            memoryUsage: 1024 * 1024 * 100 // 100MB
        )
        
        return ProcessedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: CMTime(seconds: Double(frameNumber), preferredTimescale: 30),
            segmentationMasks: masks,
            metadata: metadata,
            frameNumber: frameNumber
        )
    }
    
    private func createMockPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            640,
            480,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            fatalError("Failed to create mock pixel buffer")
        }
        
        return buffer
    }
}

// MARK: - Mock Delegate

class MockObjectTrackerDelegate: ObjectTrackerDelegate {
    var initializeTrackingCallCount = 0
    var updateTrackingCallCount = 0
    var loseObjectCallCount = 0
    var reacquireObjectCallCount = 0
    var removeObjectCallCount = 0
    var failWithErrorCallCount = 0
    
    var lastInitializedObjects: [TrackedObject]?
    var lastUpdatedObjects: [TrackedObject]?
    var lastLostObject: TrackedObject?
    var lastReacquiredObject: TrackedObject?
    var lastRemovedObjectId: UUID?
    var lastError: EdgeTAMError?
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didInitializeTracking objects: [TrackedObject]) {
        initializeTrackingCallCount += 1
        lastInitializedObjects = objects
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didUpdateTracking objects: [TrackedObject]) {
        updateTrackingCallCount += 1
        lastUpdatedObjects = objects
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didLoseObject object: TrackedObject) {
        loseObjectCallCount += 1
        lastLostObject = object
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didReacquireObject object: TrackedObject) {
        reacquireObjectCallCount += 1
        lastReacquiredObject = object
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didRemoveObject objectId: UUID) {
        removeObjectCallCount += 1
        lastRemovedObjectId = objectId
    }
    
    func objectTracker(_ tracker: ObjectTrackerProtocol, didFailWithError error: EdgeTAMError) {
        failWithErrorCallCount += 1
        lastError = error
    }
}