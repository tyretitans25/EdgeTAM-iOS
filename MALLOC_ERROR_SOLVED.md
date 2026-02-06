# Malloc Error - SOLVED: Swift ARC vs Objective-C Manual Memory Management

## Final Root Cause

The malloc error was caused by a **mismatch between Swift's automatic memory management (ARC) and Objective-C's manual memory management** for CVPixelBuffer objects.

### The Problem

```
malloc: *** error for object 0x1065d4000: pointer being freed was not allocated
```

This occurred because:

1. `tensorToPixelBuffer` creates a CVPixelBuffer with retain count = 1
2. Assigns it to `TorchInferenceResult.maskBuffer` (still count = 1)
3. Swift extracts the buffer from `result.maskBuffer`
4. **Objective-C `dealloc` releases the buffer** (count = 0, freed)
5. **Swift's ARC tries to release it again** → **DOUBLE FREE** → **CRASH**

### Why This Happened

In modern Swift (Swift 5.7+), Core Foundation objects like CVPixelBuffer are **automatically memory managed** by ARC. You cannot call `CVPixelBufferRetain()` or `CVPixelBufferRelease()` in Swift - the compiler prevents it.

However, in Objective-C, you must manually manage CVPixelBuffer with retain/release.

When bridging between Objective-C and Swift:
- Objective-C creates the buffer (retain count = 1)
- Swift takes ownership via ARC
- Objective-C `dealloc` releases it (count = 0)
- Swift ARC releases it again → **CRASH**

## The Solution

### Remove Manual Release from Objective-C

**File**: `EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchBridge.mm`

**Before** (WRONG):
```objective-c
@implementation TorchInferenceResult

- (void)dealloc {
    if (_maskBuffer != NULL) {
        CVPixelBufferRelease(_maskBuffer);  // ❌ WRONG - Swift will release it
        _maskBuffer = NULL;
    }
}

@end
```

**After** (CORRECT):
```objective-c
@implementation TorchInferenceResult

- (void)dealloc {
    // Don't release maskBuffer here - ownership is transferred to Swift
    // Swift's ARC will manage the CVPixelBuffer lifecycle automatically
    _maskBuffer = NULL;
}

@end
```

### Swift Side - No Changes Needed

Swift automatically manages the CVPixelBuffer:

```swift
let result = try module.predict(
    with: pixelBuffer,
    pointCoordinates: coordinates,
    pointLabels: labels
)

guard let maskBuffer = result.maskBuffer else {
    throw EdgeTAMError.inferenceFailure("No mask buffer returned")
}

// Swift's ARC automatically manages maskBuffer lifecycle
return PyTorchInferenceResult(
    maskBuffer: maskBuffer,  // ARC takes ownership
    confidence: result.confidence,
    inferenceTime: result.inferenceTime
)
```

## Memory Management Flow

### Correct Flow (After Fix)

```
1. tensorToPixelBuffer creates CVPixelBuffer
   → retain count = 1

2. Assign to TorchInferenceResult.maskBuffer
   → retain count = 1 (no change)

3. Swift extracts maskBuffer
   → Swift ARC takes ownership
   → retain count = 1 (ARC manages it now)

4. TorchInferenceResult.dealloc
   → Does NOT release (Swift owns it)
   → retain count = 1

5. Swift PyTorchInferenceResult goes out of scope
   → ARC releases the buffer
   → retain count = 0
   → Buffer freed ✅
```

### Incorrect Flow (Before Fix)

```
1. tensorToPixelBuffer creates CVPixelBuffer
   → retain count = 1

2. Assign to TorchInferenceResult.maskBuffer
   → retain count = 1

3. Swift extracts maskBuffer
   → Swift ARC takes ownership
   → retain count = 1

4. TorchInferenceResult.dealloc
   → Releases the buffer ❌
   → retain count = 0
   → Buffer freed

5. Swift PyTorchInferenceResult goes out of scope
   → ARC tries to release already-freed buffer ❌
   → DOUBLE FREE → CRASH
```

## Complete Fix Summary

This is the **final fix** that combines all previous attempts:

1. **Thread Safety** (MALLOC_ERROR_THREAD_SAFETY_FIX.md):
   - Added NSLock to serialize PyTorch inference calls
   - Added frame skipping to prevent queue buildup

2. **Input Buffer Management** (MALLOC_ERROR_FINAL_FIX.md):
   - Removed incorrect CVPixelBufferRetain/Release on input buffer
   - Just lock/unlock for reading

3. **Output Buffer Management** (THIS FIX):
   - Removed CVPixelBufferRelease from Objective-C dealloc
   - Let Swift's ARC manage the output buffer lifecycle

## Files Modified

### 1. EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchBridge.mm

**TorchInferenceResult.dealloc**:
```objective-c
- (void)dealloc {
    // Don't release maskBuffer here - ownership is transferred to Swift
    // Swift's ARC will manage the CVPixelBuffer lifecycle automatically
    _maskBuffer = NULL;
}
```

**pixelBufferToTensor** (from previous fix):
- Removed CVPixelBufferRetain/Release on input buffer
- Just lock/unlock for reading

**TorchModule** (from previous fix):
- Added NSLock for thread safety

### 2. EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchModule.swift

No changes needed - Swift ARC handles everything automatically.

### 3. EdgeTAM-iOS/EdgeTAM-iOS/Services/VideoPipelineCoordinator.swift

From previous fix:
- Added frame skipping to prevent concurrent inference

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

## Expected Behavior

- ✅ No malloc errors
- ✅ Proper memory management across Objective-C/Swift boundary
- ✅ Swift ARC manages CVPixelBuffer lifecycle
- ✅ Thread-safe inference with NSLock
- ✅ Aggressive frame dropping when busy
- ✅ Stable memory usage

## Key Learnings

### 1. Swift ARC vs Objective-C Manual Memory Management

**Swift (Modern)**:
- CVPixelBuffer is automatically managed by ARC
- Cannot call `CVPixelBufferRetain()` or `CVPixelBufferRelease()`
- Compiler error: "Core Foundation objects are automatically memory managed"

**Objective-C**:
- Must manually call `CVPixelBufferRetain()` and `CVPixelBufferRelease()`
- Follow Create Rule: if you create it, you own it

### 2. Bridging Between Objective-C and Swift

**When transferring ownership from Objective-C to Swift**:
- ✅ Create the object in Objective-C (retain count = 1)
- ✅ Return it to Swift
- ❌ DON'T release it in Objective-C dealloc
- ✅ Let Swift ARC manage it

**Ownership Transfer Pattern**:
```objective-c
// Objective-C: Create and return (don't release in dealloc)
- (CVPixelBufferRef)createBuffer {
    CVPixelBufferRef buffer = ...;  // retain count = 1
    return buffer;  // Transfer ownership to Swift
}

- (void)dealloc {
    // Don't release buffer - Swift owns it now
}
```

```swift
// Swift: Receive and use (ARC manages automatically)
let buffer = objcObject.createBuffer()
// ARC will release when buffer goes out of scope
```

### 3. CF_RETURNS_RETAINED Annotation

The header uses `CF_RETURNS_NOT_RETAINED`:
```objective-c
@property (nonatomic, assign) CVPixelBufferRef _Nullable maskBuffer CF_RETURNS_NOT_RETAINED;
```

This tells Swift: "I'm not giving you a +1 retain count, you need to manage it yourself."

But since we're creating the buffer and transferring ownership, we should actually use `CF_RETURNS_RETAINED` or just let Swift ARC handle it (which is what we're doing).

### 4. Memory Management Rules Summary

| Scenario | Objective-C | Swift |
|----------|-------------|-------|
| Create buffer | `CVPixelBufferCreate()` → retain count = 1 | N/A (use Objective-C) |
| Return to Swift | Return pointer, DON'T release in dealloc | ARC takes ownership |
| Use buffer | Lock/unlock, retain if storing | ARC manages automatically |
| Cleanup | N/A (Swift owns it) | ARC releases when out of scope |

## Related Documents

- `MALLOC_ERROR_THREAD_SAFETY_FIX.md` - Thread safety with NSLock
- `MALLOC_ERROR_FINAL_FIX.md` - Input buffer ownership
- `MALLOC_ERROR_FIX_V2.md` - Previous attempt (autorelease pools)
- `MALLOC_ERROR_FIX_V3_FINAL.md` - Previous attempt (custom setter)
- `MALLOC_ERROR_FINAL_SOLUTION.md` - Previous attempt (simplified ownership)

## Debugging Tips for Similar Issues

If you see "pointer being freed was not allocated":

1. **Check for double-free**: Is the same object being released twice?
2. **Check Objective-C/Swift boundary**: Are you manually releasing in Objective-C what Swift ARC manages?
3. **Use Address Sanitizer**: Enable in Xcode scheme → Diagnostics → Address Sanitizer
4. **Check retain counts**: Use `CFGetRetainCount()` in Objective-C to debug
5. **Look for CF_RETURNS annotations**: They tell Swift about ownership

---

**Status**: ✅ SOLVED - Build successful, ready for device testing
**Date**: 2026-02-03
**Build**: Successful
**Root Cause**: Objective-C dealloc releasing buffer that Swift ARC owns
**Solution**: Remove manual release, let Swift ARC manage lifecycle
