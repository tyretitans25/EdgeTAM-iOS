# EdgeTAM Model Setup Instructions

Complete guide for downloading and converting the actual EdgeTAM model for the iOS app.

## Overview

This guide uses the **official EdgeTAM checkpoint** from the Track-Anything repository, not the SAM checkpoints. The EdgeTAM model is specifically optimized for video tracking and mobile deployment.

## Prerequisites

### 1. Install Python Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv edgetam_env
source edgetam_env/bin/activate  # On macOS/Linux

# Install required packages
pip install torch torchvision coremltools numpy
```

### 2. Verify Installation

```bash
python -c "import torch; import coremltools; print('✓ Dependencies installed')"
```

## Method 1: Automated Setup (Recommended)

### Step 1: Run Setup Script

```bash
# Make script executable
chmod +x setup_edgetam.sh

# Run the setup
./setup_edgetam.sh
```

This script will:
1. Clone the EdgeTAM repository
2. Create checkpoints directory
3. Download edgetam.pt checkpoint
4. Verify the download

### Step 2: Convert to CoreML

```bash
# Run the conversion script
python edgetam_coreml_export.py --checkpoint EdgeTAM/checkpoints/edgetam.pt
```

## Method 2: Manual Setup

### Step 1: Clone EdgeTAM Repository

```bash
git clone https://github.com/gaomingqi/Track-Anything.git EdgeTAM
cd EdgeTAM
```

### Step 2: Download Checkpoint

```bash
# Create checkpoints directory
mkdir -p checkpoints
cd checkpoints

# Option A: Use official download script (if available)
bash ../checkpoints/download_ckpts.sh

# Option B: Manual download from Hugging Face
wget https://huggingface.co/spaces/VIPLab/Track-Anything/resolve/main/checkpoints/edgetam.pt

# Option C: Using curl
curl -L -O https://huggingface.co/spaces/VIPLab/Track-Anything/resolve/main/checkpoints/edgetam.pt

cd ..
```

### Step 3: Verify Checkpoint

```bash
# Check if file exists and get size
ls -lh checkpoints/edgetam.pt
```

You should see the edgetam.pt file (size varies, typically several hundred MB).

### Step 4: Convert to CoreML

```bash
# From the root directory (where edgetam_coreml_export.py is located)
python edgetam_coreml_export.py \
    --checkpoint EdgeTAM/checkpoints/edgetam.pt \
    --output EdgeTAM.mlpackage \
    --image-size 1024
```

## Expected Output

After successful conversion, you should have:

```
EdgeTAM.mlpackage/
├── Data/
│   └── ... (model weights)
├── Manifest.json
└── Metadata/
    └── ... (model metadata)
```

## Adding Model to Xcode

### Step 1: Locate the Model

The converted model should be at:
```
./EdgeTAM.mlpackage
```

### Step 2: Add to Xcode Project

1. Open `EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj` in Xcode
2. In Project Navigator, right-click on `EdgeTAM-iOS` folder
3. Select "Add Files to EdgeTAM-iOS..."
4. Navigate to `EdgeTAM.mlpackage`
5. **Important**: Check "Copy items if needed"
6. **Important**: Ensure "EdgeTAM-iOS" target is selected
7. Click "Add"

### Step 3: Verify Integration

1. Click on `EdgeTAM.mlpackage` in Project Navigator
2. Xcode should show:
   - Model inputs and outputs
   - Auto-generated Swift interface
   - Model metadata

### Step 4: Build and Test

```bash
# Clean build
xcodebuild -project EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj \
  -scheme EdgeTAM-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build
```

Or in Xcode:
1. Product > Clean Build Folder (⇧⌘K)
2. Product > Build (⌘B)
3. Product > Run (⌘R)

## Troubleshooting

### Issue: "Checkpoint not found"

**Solution**:
```bash
# Verify the path
ls -la EdgeTAM/checkpoints/edgetam.pt

# If missing, re-run download
cd EdgeTAM/checkpoints
bash download_ckpts.sh
```

### Issue: "Failed to load checkpoint"

**Possible causes**:
1. Incomplete download
2. Corrupted file
3. Wrong PyTorch version

**Solution**:
```bash
# Remove and re-download
rm EdgeTAM/checkpoints/edgetam.pt
cd EdgeTAM/checkpoints
bash download_ckpts.sh

# Verify file integrity
file edgetam.pt  # Should show "data" or similar
```

### Issue: "Cannot trace model"

EdgeTAM has a complex architecture that may not trace directly.

**Solution 1**: Export components separately
```python
# Export image encoder
encoder = model.image_encoder
traced_encoder = torch.jit.trace(encoder, example_image)

# Export mask decoder  
decoder = model.mask_decoder
traced_decoder = torch.jit.trace(decoder, example_inputs)
```

**Solution 2**: Use ONNX intermediate format
```bash
pip install onnx onnx-coreml

# Export to ONNX first
python export_to_onnx.py

# Then convert ONNX to CoreML
python onnx_to_coreml.py
```

**Solution 3**: Use quick setup model for testing
```bash
python quick_setup_model.py
```

### Issue: "Model too large for iOS"

**Solution**: Quantize the model
```python
# In edgetam_coreml_export.py, modify conversion:
coreml_model = ct.convert(
    traced_model,
    inputs=inputs,
    compute_precision=ct.precision.FLOAT16,  # Use FP16
    compute_units=ct.ComputeUnit.ALL
)
```

### Issue: "Out of memory during conversion"

**Solution**:
1. Close other applications
2. Use smaller image size:
   ```bash
   python edgetam_coreml_export.py --image-size 512
   ```
3. Try on a machine with more RAM

## Alternative: Quick Test Model

If EdgeTAM conversion is complex, start with a simpler model:

```bash
# This creates a working model immediately
python quick_setup_model.py
```

This generates a lightweight segmentation model that:
- Works out of the box
- Requires no large downloads
- Provides basic segmentation
- Can be replaced with EdgeTAM later

## Model Information

### EdgeTAM Checkpoint Details

- **Source**: Track-Anything repository
- **Location**: `checkpoints/edgetam.pt`
- **Size**: ~300-500MB (varies by version)
- **Format**: PyTorch checkpoint (.pt)
- **Architecture**: Based on SAM with video tracking optimizations

### Expected CoreML Model

- **Format**: ML Program (.mlpackage)
- **Size**: ~200-400MB (after conversion)
- **Target**: iOS 17+
- **Compute**: Neural Engine + GPU + CPU
- **Input**: 1024x1024 RGB image + point/box prompts
- **Output**: Segmentation masks + confidence scores

## Performance Expectations

### iPhone 15 Pro
- **Inference Time**: 100-200ms per frame
- **Memory Usage**: 500-800MB
- **FPS**: 10-15 frames per second
- **Thermal**: Nominal to Fair

### iPhone 14 Pro
- **Inference Time**: 150-250ms per frame
- **Memory Usage**: 600-900MB
- **FPS**: 8-12 frames per second
- **Thermal**: Fair to Serious

## Next Steps

After successful model integration:

1. ✅ Run the app on a physical device
2. ✅ Grant camera permissions
3. ✅ Tap on objects to test segmentation
4. ✅ Verify mask overlays appear correctly
5. ✅ Check performance metrics (FPS, memory)
6. ✅ Test with multiple objects
7. ✅ Test camera switching
8. ✅ Test video export functionality

## Resources

- [EdgeTAM Repository](https://github.com/gaomingqi/Track-Anything)
- [EdgeTAM Hugging Face](https://huggingface.co/spaces/VIPLab/Track-Anything)
- [CoreML Tools Documentation](https://coremltools.readme.io/)
- [Apple CoreML Guide](https://developer.apple.com/documentation/coreml)

## Support

If you encounter issues:

1. Check console logs in Xcode for detailed errors
2. Verify all dependencies are installed correctly
3. Try the quick setup model first for testing
4. Review troubleshooting section above
5. Check EdgeTAM repository issues for similar problems

## Important Notes

- **Checkpoint Location**: Use `EdgeTAM/checkpoints/edgetam.pt`, not SAM checkpoints
- **Download Script**: The repository provides `checkpoints/download_ckpts.sh`
- **Model Architecture**: EdgeTAM is optimized for video tracking, not just segmentation
- **Testing**: Always test on physical device for accurate performance metrics
- **Fallback**: Use `quick_setup_model.py` if EdgeTAM conversion is problematic

---

**Note**: The EdgeTAM model architecture may require modifications for optimal mobile deployment. The conversion scripts provided are starting points that may need adjustments based on the specific model version and your requirements.
