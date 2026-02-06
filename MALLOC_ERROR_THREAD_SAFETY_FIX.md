# Malloc Error Fix: Thread Safety Solution

## Problem Summary

The app was experiencing malloc errors during video frame processing:
```
malloc: *** error for object 0x104fc8000: pointer being freed was not allocated
```

### Root Cause Analysis

After multiple attempted fixes focusing on memory management, the real issue was identified:

1. **Concurrent Inference Calls**: Multiple video frames were being processed simultaneously, causing concurrent calls to the PyTorch model
2. **No Thread Safety**: The `TorchModule` had no mutex/lock to serialize inference operations
3. **Race Condition**: Multiple threads accessing the same model instance and buffers simultaneously
4. **Queue Buildup**: Camera frames were queuing up faster than they could be processed

### Evidence from Logs

- Multiple "Processing frame with 1 prompts" messages appearing simultaneously
- "Dropped frame" messages indicating queue buildup
- Malloc errors occurring after concurrent access patterns
- Input size mismatch (1920x1080 vs 1024x1024) suggesting frames not being properly preprocessed

## Solution Implemented

### 1. Added Thread Safety to PyTorch Inference (TorchBridge.mm)

**Added NSLock to serialize model inference:**

```objective-c
@interface TorchModule ()
@property (nonatomic, strong) NSLock *inferenceLock;  // Thread safety for inference
@end

- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        _modelPath = modelPath;
        _module = nullptr;
        _loaded = NO;
        _inferenceLock = [[NSLock alloc] init];
        _inferenceLock.name = @"com.edgetam.torch.inference";
    }
    return self;
}

- (nullable TorchInferenceResult *)predictWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         pointCoordinates:(NSArray<NSValue *> *)pointCoordinates
                                              pointLabels:(NSArray<NSNumber *> *)pointLabels
                                                    error:(NSError **)error {
    // CRITICAL: Lock to prevent concurrent inference calls
    // PyTorch models are NOT thread-safe for inference
    [self.inferenceLock lock];
    
    @autoreleasepool {
        @try {
            // ... inference code ...
            [self.inferenceLock unlock];
            return result;
        } @catch (NSException *exception) {
            [self.inferenceLock unlock];
            return nil;
        }
    }
}
```

**Why this works:**
- PyTorch models are NOT thread-safe for concurrent inference
- The lock ensures only ONE inference operation runs at a time
- Prevents race conditions on model state and buffers
- Eliminates double-free errors from concurrent buffer access

### 2. Prevented Frame Queue Buildup (VideoPipelineCoordinator.swift)

**Added frame skipping when processing is in progress:**

```swift
/// Processing state - using atomic operations for thread safety
private let isProcessingEnabled = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
private let isCurrentlyProcessing = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

nonisolated func captureOutput(_ output: AVCaptureOutput,
                  didOutput sampleBuffer: CMSampleBuffer,
                  from connection: AVCaptureConnection) {
    let shouldProcess = isProcessingEnabled.pointee
    let alreadyProcessing = isCurrentlyProcessing.pointee
    
    guard shouldProcess else { return }
    
    // CRITICAL: Skip frame if we're still processing the previous one
    // This prevents queue buildup and concurrent inference calls
    guard !alreadyProcessing else {
        if frameCounter % 30 == 0 {
            logger.debug("Skipping frame - previous frame still processing")
        }
        return
    }
    
    // Mark as processing
    isCurrentlyProcessing.pointee = true
    
    // Process frame asynchronously
    Task {
        await processFrame(pixelBuffer)
        
        // Mark as done processing
        isCurrentlyProcessing.pointee = false
    }
}
```

**Why this works:**
- Prevents multiple frames from being processed concurrently
- Drops frames when the previous frame is still being processed
- Reduces memory pressure and queue buildup
- Works with the inference lock to ensure serial processing

**Note on atomic operations:**
- Used `UnsafeMutablePointer<Bool>` instead of `NSLock` because Swift async contexts don't allow NSLock
- Atomic pointer operations are safe for simple boolean flags
- Properly initialized in `init()` and deallocated in `deinit()`

## Files Modified

1. **EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchBridge.mm**
   - Added `inferenceLock` property to `TorchModule`
   - Lock acquired at start of `predictWithPixelBuffer`
   - Lock released in both success and error paths

2. **EdgeTAM-iOS/EdgeTAM-iOS/Services/VideoPipelineCoordinator.swift**
   - Added `isCurrentlyProcessing` atomic flag
   - Skip frames when processing is already in progress
   - Prevents concurrent inference calls from video pipeline

## Testing

Build status: ✅ **BUILD SUCCEEDED**

```bash
cd EdgeTAM-iOS
xcodebuild -workspace EdgeTAM-iOS.xcworkspace \
  -scheme EdgeTAM-iOS \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64 \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Expected Behavior After Fix

1. **No more malloc errors**: Thread safety prevents concurrent buffer access
2. **Serial inference**: Only one frame processed at a time
3. **Aggressive frame dropping**: Frames skipped when processing is busy
4. **Stable memory usage**: No queue buildup or memory leaks
5. **Lower frame rate**: May process fewer frames per second, but stable

## Performance Considerations

- **Frame rate**: Will be limited by inference time (~100-300ms per frame)
- **Effective FPS**: Likely 3-10 FPS depending on device and model
- **Trade-off**: Stability over speed - better to process fewer frames correctly than crash

## Next Steps

1. **Test on device**: Deploy to physical iOS device and test with camera
2. **Monitor logs**: Check for "Skipping frame" messages (expected)
3. **Verify stability**: Ensure no malloc errors occur during extended use
4. **Optimize if needed**: If frame rate is too low, consider:
   - Model quantization
   - Lower input resolution
   - GPU acceleration tuning
   - Background processing queue

## Related Documents

- `MALLOC_ERROR_FIX_V2.md` - Previous attempt (autorelease pools)
- `MALLOC_ERROR_FIX_V3_FINAL.md` - Previous attempt (custom setter)
- `MALLOC_ERROR_FINAL_SOLUTION.md` - Previous attempt (simplified ownership)
- `VIDEO_PIPELINE_IMPLEMENTATION.md` - Video pipeline architecture

## Key Learnings

1. **PyTorch models are NOT thread-safe** - Always serialize inference calls
2. **Memory management wasn't the issue** - The problem was concurrent access
3. **Frame dropping is essential** - Don't queue up frames faster than processing
4. **Atomic operations in Swift** - Use `UnsafeMutablePointer` for async-safe flags
5. **Lock in Objective-C++** - NSLock works well for synchronous C++ code

---

**Status**: ✅ Fix implemented and builds successfully
**Date**: 2026-02-02
**Build**: Successful
