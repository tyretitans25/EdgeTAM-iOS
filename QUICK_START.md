# Quick Start Guide - EdgeTAM iOS App

Get the EdgeTAM iOS app running in 3 simple steps.

## Option 1: Quick Test (5-10 minutes)

Use a lightweight model to test the app immediately:

```bash
# 1. Install dependencies
pip install torch torchvision coremltools numpy

# 2. Generate test model
python quick_setup_model.py

# 3. Add to Xcode and run
# - Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj
# - Drag EdgeTAM.mlpackage into project
# - Check "Copy items if needed"
# - Build and run (⌘R)
```

**Result**: App runs with basic segmentation functionality.

## Option 2: Full EdgeTAM Model (30-60 minutes)

Use the actual EdgeTAM model for production quality:

```bash
# 1. Run automated setup
chmod +x setup_edgetam.sh
./setup_edgetam.sh

# 2. Convert to CoreML
python edgetam_coreml_export.py --checkpoint EdgeTAM/checkpoints/edgetam.pt

# 3. Add to Xcode and run
# - Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj
# - Drag EdgeTAM.mlpackage into project
# - Check "Copy items if needed"
# - Build and run (⌘R)
```

**Result**: App runs with full EdgeTAM capabilities.

## What You Get

### Without Model
- Beautiful setup instructions screen
- Clear guidance on adding the model
- Professional error handling

### With Model
- ✅ Real-time camera preview
- ✅ Tap to select objects
- ✅ Segmentation mask overlays
- ✅ Object tracking across frames
- ✅ Performance metrics (FPS, memory)
- ✅ Camera switching
- ✅ Video export with masks

## File Structure

```
.
├── quick_setup_model.py          # Quick test model (Option 1)
├── setup_edgetam.sh               # Download EdgeTAM (Option 2)
├── edgetam_coreml_export.py       # Convert to CoreML (Option 2)
├── EDGETAM_SETUP_INSTRUCTIONS.md  # Detailed guide
└── EdgeTAM-iOS/                   # iOS app
    └── EdgeTAM-iOS.xcodeproj      # Xcode project
```

## Detailed Guides

- **Quick Setup**: See `quick_setup_model.py` comments
- **Full Setup**: See `EDGETAM_SETUP_INSTRUCTIONS.md`
- **Troubleshooting**: See `EDGETAM_CONVERSION_GUIDE.md`
- **Model Info**: See `MODEL_CONVERSION_README.md`

## Requirements

- **macOS**: 12.0+ (for Xcode)
- **Xcode**: 15.0+
- **Python**: 3.8+
- **iOS Device**: iPhone with iOS 17+ (recommended)
- **Disk Space**: 5GB (quick) or 15GB (full)

## Testing

### On Simulator
```bash
# Note: Camera won't work, but you'll see the UI
xcodebuild -project EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj \
  -scheme EdgeTAM-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### On Physical Device
1. Connect iPhone via USB
2. Select device in Xcode
3. Click Run (⌘R)
4. Grant camera permissions
5. Tap on objects to test

## Common Issues

### "Model not found"
- Run `quick_setup_model.py` or `setup_edgetam.sh`
- Verify EdgeTAM.mlpackage exists
- Add to Xcode project with "Copy items if needed"

### "Black screen"
- This is fixed! App now shows setup instructions
- Add the model to see camera view

### "Camera errors in simulator"
- Expected behavior (no camera hardware)
- Test on physical device

## Next Steps

1. **Start with Option 1** (quick test model)
2. **Verify app works** (camera, UI, basic features)
3. **Upgrade to Option 2** (full EdgeTAM) when ready
4. **Test all features** (tracking, export, performance)

## Support

- Check console logs in Xcode for errors
- Review detailed guides in this directory
- Open GitHub issue with error details

---

**Recommendation**: Start with Option 1 to verify everything works, then upgrade to Option 2 for production quality.
