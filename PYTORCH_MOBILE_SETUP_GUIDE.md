# PyTorch Mobile Setup Guide for EdgeTAM iOS

This guide walks you through setting up PyTorch Mobile integration for the EdgeTAM iOS application.

## Prerequisites

- macOS with Xcode 15+
- Python 3.11 with PyTorch 2.7.0 installed
- EdgeTAM repository cloned and set up
- CocoaPods installed (`sudo gem install cocoapods`)

## Step 1: Export EdgeTAM to TorchScript

### 1.1 Activate Python Environment

```bash
# Use the Python 3.11 environment we set up earlier
source edgetam_export_py311/bin/activate

# Or if using the EdgeTAM venv:
# source edgetam_venv/bin/activate
```

### 1.2 Run Export Script

```bash
python export_edgetam_to_torchscript.py \
    --checkpoint EdgeTAM/checkpoints/edgetam.pt \
    --config EdgeTAM/sam2/configs/edgetam.yaml \
    --output edgetam_mobile.pt \
    --validate
```

**Expected Output:**
```
Loading EdgeTAM model...
  Config: /path/to/EdgeTAM/sam2/configs/edgetam.yaml
  Checkpoint: /path/to/EdgeTAM/checkpoints/edgetam.pt
  Loaded checkpoint: EdgeTAM/checkpoints/edgetam.pt

Exporting to TorchScript...
  Example inputs:
    Image: torch.Size([1, 3, 1024, 1024])
    Point coords: torch.Size([1, 1, 2])
    Point labels: torch.Size([1, 1])
  Tracing model...
  Optimizing for mobile...
  Saving to: edgetam_mobile.pt
  Model size: 56.23 MB

Validating exported model...
  ✓ Model loaded successfully
  ✓ Inference successful
    Output masks: torch.Size([1, 1, 1024, 1024])
    Output scores: torch.Size([1, 1])

✅ Export completed successfully!
```

### 1.3 Verify Export

```bash
# Check file size
ls -lh edgetam_mobile.pt

# Should be around 56 MB
```

## Step 2: Install PyTorch Mobile Dependencies

### 2.1 Navigate to iOS Project

```bash
cd EdgeTAM-iOS
```

### 2.2 Install CocoaPods Dependencies

```bash
# Install pods (this will download LibTorch-Lite)
pod install

# This may take 5-10 minutes as LibTorch-Lite is ~50 MB
```

**Expected Output:**
```
Analyzing dependencies
Downloading dependencies
Installing LibTorch-Lite (2.7.0)
Generating Pods project
Integrating client project

[!] Please close any current Xcode sessions and use `EdgeTAM-iOS.xcworkspace` for this project from now on.
```

### 2.3 Open Workspace

```bash
# IMPORTANT: Use .xcworkspace, not .xcodeproj
open EdgeTAM-iOS.xcworkspace
```

## Step 3: Add Model to Xcode Project

### 3.1 Copy Model File

```bash
# Copy the exported model to the iOS project
cp ../edgetam_mobile.pt EdgeTAM-iOS/Models/
```

### 3.2 Add to Xcode

1. In Xcode, right-click on `EdgeTAM-iOS/Models` folder
2. Select "Add Files to EdgeTAM-iOS..."
3. Navigate to and select `edgetam_mobile.pt`
4. **Important:** Check "Copy items if needed"
5. **Important:** Ensure "EdgeTAM-iOS" target is selected
6. Click "Add"

### 3.3 Verify Model is in Bundle

1. Select `EdgeTAM-iOS` target
2. Go to "Build Phases"
3. Expand "Copy Bundle Resources"
4. Verify `edgetam_mobile.pt` is listed

## Step 4: Configure Xcode Build Settings

### 4.1 Add Bridging Header

1. In Xcode, select `EdgeTAM-iOS` target
2. Go to "Build Settings"
3. Search for "Objective-C Bridging Header"
4. Set value to: `EdgeTAM-iOS/PyTorch/TorchBridge.h`

### 4.2 Enable C++ Compilation

1. Search for "C++ Language Dialect"
2. Set to: `GNU++17 [-std=gnu++17]`

### 4.3 Disable Bitcode

1. Search for "Enable Bitcode"
2. Set to: `No`

### 4.4 Set Deployment Target

1. Search for "iOS Deployment Target"
2. Ensure it's set to: `16.0` or higher

## Step 5: Update ModelManager

### 5.1 Create PyTorchModelManager

The PyTorch-based ModelManager has been created at:
- `EdgeTAM-iOS/EdgeTAM-iOS/Services/PyTorchModelManager.swift`

### 5.2 Update DependencyContainer

Open `EdgeTAM-iOS/EdgeTAM-iOS/Core/DependencyContainer.swift` and update:

```swift
// Replace CoreML ModelManager with PyTorch version
func makeModelManager() -> ModelManagerProtocol {
    return PyTorchModelManager(configuration: ModelConfiguration())
}
```

## Step 6: Build and Test

### 6.1 Clean Build Folder

1. In Xcode: Product → Clean Build Folder (⇧⌘K)

### 6.2 Build Project

1. Select a simulator or device
2. Product → Build (⌘B)

**Expected:** Build should succeed with no errors

### 6.3 Run Tests

```bash
# Run unit tests
xcodebuild test \
    -workspace EdgeTAM-iOS.xcworkspace \
    -scheme EdgeTAM-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
```

### 6.4 Run on Device/Simulator

1. Select target device
2. Product → Run (⌘R)
3. App should launch successfully

## Step 7: Verify Integration

### 7.1 Check Model Loading

Look for log messages in Xcode console:

```
[TorchBridge] Loading model from: /path/to/edgetam_mobile.pt
[TorchBridge] Model loaded successfully
[PyTorchModelManager] Model loaded successfully in 2.34s
```

### 7.2 Test Inference

1. Grant camera permissions
2. Tap on video preview to select an object
3. Check console for inference logs:

```
[TorchBridge] Inference completed in 0.089s (confidence: 0.923)
[PyTorchModelManager] Inference completed in 0.089s
```

## Troubleshooting

### Issue: "Module 'LibTorch-Lite' not found"

**Solution:**
```bash
cd EdgeTAM-iOS
pod deintegrate
pod install
```

### Issue: "Model file not found"

**Solution:**
1. Verify `edgetam_mobile.pt` is in Xcode project navigator
2. Check "Copy Bundle Resources" in Build Phases
3. Clean build folder and rebuild

### Issue: "Undefined symbols for architecture arm64"

**Solution:**
1. Verify C++ Language Dialect is set to GNU++17
2. Check that LibTorch-Lite pod is installed
3. Clean and rebuild

### Issue: Slow inference (>200ms per frame)

**Solution:**
1. Ensure running on device (not simulator)
2. Check that Metal GPU acceleration is enabled
3. Verify model is optimized (exported with --optimize flag)

### Issue: High memory usage (>1GB)

**Solution:**
1. Implement frame skipping (process every 2nd or 3rd frame)
2. Reduce input resolution if possible
3. Unload model when app is backgrounded

## Performance Benchmarks

### Expected Performance (iPhone 15 Pro Max)

| Metric | Value |
|--------|-------|
| Model Load Time | 2-4 seconds |
| Inference Time | 80-120ms per frame |
| FPS | 10-15 FPS |
| Memory Usage | 300-500 MB |
| App Size Increase | ~106 MB |

### Optimization Tips

1. **Frame Skipping:** Process every 2nd frame for 2x speedup
2. **Resolution Reduction:** Use 512x512 instead of 1024x1024
3. **Batch Processing:** Process multiple frames in one inference call
4. **Model Quantization:** Use quantized model for smaller size and faster inference

## Next Steps

1. ✅ Model exported to TorchScript
2. ✅ PyTorch Mobile integrated
3. ✅ ModelManager updated
4. ⬜ Test on physical device
5. ⬜ Optimize performance
6. ⬜ Add error handling
7. ⬜ Implement frame skipping
8. ⬜ Profile memory usage

## Additional Resources

- [PyTorch Mobile Documentation](https://pytorch.org/mobile/home/)
- [LibTorch iOS Tutorial](https://pytorch.org/mobile/ios/)
- [TorchScript Guide](https://pytorch.org/docs/stable/jit.html)
- [EdgeTAM Repository](https://github.com/facebookresearch/EdgeTAM)

## Support

If you encounter issues:

1. Check Xcode console for error messages
2. Verify all build settings are correct
3. Ensure model file is in app bundle
4. Test on physical device (not just simulator)

---

**Last Updated:** February 1, 2026
**Status:** Ready for implementation
