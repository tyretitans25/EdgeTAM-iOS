# Malloc Error - Final Fix: Input Buffer Ownership

## Problem

Even after adding thread safety with NSLock, the malloc error persisted:
```
malloc: *** error for object 0x103b74000: pointer being freed was not allocated
```

The crash occurred during the first inference call in `pixelBufferToTensor`.

## Root Cause

The issue was **incorrect memory management of the input CVPixelBuffer**:

1. The camera owns the input `CVPixelBuffer` and passes it to us
2. We were calling `CVPixelBufferRetain()` at the start of `pixelBufferToTensor`
3. We were calling `CVPixelBufferRelease()` at the end
4. This caused a **double-free** because we were releasing a buffer we didn't own

### The Mistake

```objective-c
// WRONG - Don't retain/release buffers we don't own!
- (torch::Tensor)pixelBufferToTensor:(CVPixelBufferRef)pixelBuffer {
    CVPixelBufferRetain(pixelBuffer);  // ❌ We don't own this!
    
    // ... copy data ...
    
    CVPixelBufferRelease(pixelBuffer);  // ❌ Double-free!
    return tensor;
}
```

### The Correct Approach

```objective-c
// CORRECT - Just borrow the buffer, don't manage its lifetime
- (torch::Tensor)pixelBufferToTensor:(CVPixelBufferRef)pixelBuffer {
    // Lock for reading (caller still owns it)
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // ... copy data to tensor ...
    
    // Unlock (caller still owns it)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return tensor;  // Caller will release when done
}
```

## Solution

### Removed Incorrect Retain/Release from pixelBufferToTensor

**File**: `EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchBridge.mm`

**Before**:
```objective-c
- (torch::Tensor)pixelBufferToTensor:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        NSLog(@"[TorchBridge] ERROR: pixelBuffer is NULL");
        return torch::zeros({1, 3, 1, 1});
    }
    
    // Retain the pixel buffer to ensure it stays valid during processing
    CVPixelBufferRetain(pixelBuffer);  // ❌ WRONG
    
    CVReturn lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockResult != kCVReturnSuccess) {
        NSLog(@"[TorchBridge] ERROR: Failed to lock pixel buffer: %d", lockResult);
        CVPixelBufferRelease(pixelBuffer);  // ❌ WRONG
        return torch::zeros({1, 3, 1, 1});
    }
    
    // ... copy data ...
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferRelease(pixelBuffer);  // ❌ WRONG - Release our retain
    
    return tensor;
}
```

**After**:
```objective-c
- (torch::Tensor)pixelBufferToTensor:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        NSLog(@"[TorchBridge] ERROR: pixelBuffer is NULL");
        return torch::zeros({1, 3, 1, 1});
    }
    
    // Lock the pixel buffer for reading (caller owns the buffer, we just borrow it)
    CVReturn lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockResult != kCVReturnSuccess) {
        NSLog(@"[TorchBridge] ERROR: Failed to lock pixel buffer: %d", lockResult);
        return torch::zeros({1, 3, 1, 1});
    }
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    if (!baseAddress) {
        NSLog(@"[TorchBridge] ERROR: baseAddress is NULL");
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return torch::zeros({1, 3, 1, 1});
    }
    
    // Create tensor with shape [1, 3, height, width]
    torch::Tensor tensor = torch::zeros({1, 3, (long)height, (long)width});
    
    // Copy pixel data to tensor
    // Assuming BGRA format, convert to RGB and normalize to [0, 1]
    auto tensorAccessor = tensor.accessor<float, 4>();
    
    for (size_t y = 0; y < height; y++) {
        uint8_t *row = (uint8_t *)baseAddress + y * bytesPerRow;
        for (size_t x = 0; x < width; x++) {
            uint8_t *pixel = row + x * 4; // BGRA
            
            // Convert BGRA to RGB and normalize
            tensorAccessor[0][0][y][x] = pixel[2] / 255.0f; // R
            tensorAccessor[0][1][y][x] = pixel[1] / 255.0f; // G
            tensorAccessor[0][2][y][x] = pixel[0] / 255.0f; // B
        }
    }
    
    // Unlock the buffer (caller still owns it)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return tensor;
}
```

## Why This Works

### CVPixelBuffer Ownership Rules

1. **Caller owns the buffer**: The camera/AVFoundation creates and owns the CVPixelBuffer
2. **We borrow it**: We only need to lock/unlock for reading
3. **No retain/release needed**: We don't extend the buffer's lifetime
4. **Lock protects the data**: Locking ensures the buffer isn't deallocated while we read

### Memory Management Pattern

```
Camera (Owner)
    ↓ passes CVPixelBufferRef
VideoPipelineCoordinator
    ↓ passes CVPixelBufferRef
PyTorchModelManager
    ↓ passes CVPixelBufferRef
TorchModule
    ↓ passes CVPixelBufferRef
TorchBridge.predictWithPixelBuffer
    ↓ passes CVPixelBufferRef
TorchBridge.pixelBufferToTensor
    ↓ Lock → Read → Unlock (NO retain/release!)
    ↑ returns torch::Tensor (copied data)
```

The data is **copied** from the CVPixelBuffer into the torch::Tensor, so we don't need to keep the buffer alive after the copy completes.

## Complete Fix Summary

This fix combines with the previous thread safety fix:

1. **Thread Safety** (from MALLOC_ERROR_THREAD_SAFETY_FIX.md):
   - Added NSLock to serialize PyTorch inference calls
   - Added frame skipping to prevent queue buildup

2. **Input Buffer Management** (this fix):
   - Removed incorrect CVPixelBufferRetain/Release
   - Just lock/unlock for reading, don't manage lifetime

## Files Modified

1. **EdgeTAM-iOS/EdgeTAM-iOS/PyTorch/TorchBridge.mm**
   - Removed `CVPixelBufferRetain()` at start of `pixelBufferToTensor`
   - Removed `CVPixelBufferRelease()` calls in error paths
   - Removed `CVPixelBufferRelease()` at end of function
   - Added comments explaining ownership model

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
- ✅ Stable memory usage
- ✅ Proper buffer lifecycle management
- ✅ Thread-safe inference
- ✅ Aggressive frame dropping when busy

## Key Learnings

1. **Don't retain/release buffers you don't own** - Only the creator should manage lifetime
2. **Lock/unlock is sufficient for reading** - No need to extend lifetime if you're just copying data
3. **Understand ownership semantics** - Know who owns what and when
4. **Copy data, don't hold references** - Torch tensors copy the pixel data, so we don't need the buffer after

## CVPixelBuffer Memory Management Rules

### When to Retain/Release

✅ **DO retain/release when**:
- You create the buffer with `CVPixelBufferCreate()`
- You need to keep the buffer alive beyond the current scope
- You're storing the buffer as a property

❌ **DON'T retain/release when**:
- The buffer is passed to you as a parameter
- You only need to read the data temporarily
- You're copying the data to another structure

### Lock/Unlock Rules

✅ **Always lock before accessing**:
```objective-c
CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
// ... access data ...
CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
```

✅ **Unlock in all code paths**:
- Success path
- Error paths
- Exception handlers

## Related Documents

- `MALLOC_ERROR_THREAD_SAFETY_FIX.md` - Thread safety with NSLock
- `MALLOC_ERROR_FIX_V2.md` - Previous attempt (autorelease pools)
- `MALLOC_ERROR_FIX_V3_FINAL.md` - Previous attempt (custom setter)
- `MALLOC_ERROR_FINAL_SOLUTION.md` - Previous attempt (simplified ownership)

---

**Status**: ✅ Fix implemented and builds successfully
**Date**: 2026-02-02
**Build**: Successful
**Ready for testing**: Yes - deploy to device and test
