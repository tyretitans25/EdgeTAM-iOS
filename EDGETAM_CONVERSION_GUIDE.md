# EdgeTAM Model Conversion Guide

This guide walks you through converting the EdgeTAM/SAM model to CoreML format for use in the iOS app.

## Prerequisites

### 1. Install Python Dependencies

```bash
# Create a virtual environment (recommended)
python3 -m venv edgetam_env
source edgetam_env/bin/activate  # On macOS/Linux

# Install required packages
pip install torch torchvision
pip install coremltools
pip install numpy pillow
pip install git+https://github.com/facebookresearch/segment-anything.git
```

### 2. Download SAM Checkpoint

Choose one of the SAM model variants:

**Option A: SAM ViT-H (Huge) - Best Quality, Largest Size**
```bash
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
# Size: ~2.4GB
```

**Option B: SAM ViT-L (Large) - Good Balance**
```bash
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth
# Size: ~1.2GB
```

**Option C: SAM ViT-B (Base) - Smallest, Fastest**
```bash
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth
# Size: ~375MB
```

**Recommendation**: Start with ViT-B for faster conversion and testing, then upgrade to ViT-H for production.

## Conversion Process

### Method 1: Using the Provided Script (Recommended)

```bash
# Make the script executable
chmod +x convert_edgetam_to_coreml.py

# Run the conversion
python convert_edgetam_to_coreml.py \
    --checkpoint sam_vit_b_01ec64.pth \
    --output EdgeTAM.mlpackage \
    --model-type vit_b \
    --image-size 1024
```

### Method 2: Manual Conversion

If the automated script doesn't work due to SAM's complex architecture, you may need to export components separately:

#### Step 1: Export Image Encoder

```python
import torch
import coremltools as ct
from segment_anything import sam_model_registry

# Load model
sam = sam_model_registry["vit_b"](checkpoint="sam_vit_b_01ec64.pth")
sam.eval()

# Export image encoder
image_encoder = sam.image_encoder
example_input = torch.randn(1, 3, 1024, 1024)

with torch.no_grad():
    traced_encoder = torch.jit.trace(image_encoder, example_input)

# Convert to CoreML
encoder_model = ct.convert(
    traced_encoder,
    inputs=[ct.ImageType(name="image", shape=(1, 3, 1024, 1024))],
    compute_units=ct.ComputeUnit.ALL,
    minimum_deployment_target=ct.target.iOS17
)

encoder_model.save("SAM_ImageEncoder.mlpackage")
```

#### Step 2: Export Mask Decoder

```python
# Export mask decoder
mask_decoder = sam.mask_decoder

# Create example inputs
image_embeddings = torch.randn(1, 256, 64, 64)
point_coords = torch.randn(1, 1, 2)
point_labels = torch.ones(1, 1)

with torch.no_grad():
    traced_decoder = torch.jit.trace(
        mask_decoder,
        (image_embeddings, point_coords, point_labels)
    )

# Convert to CoreML
decoder_model = ct.convert(
    traced_decoder,
    inputs=[
        ct.TensorType(name="image_embeddings", shape=(1, 256, 64, 64)),
        ct.TensorType(name="point_coords", shape=(1, 1, 2)),
        ct.TensorType(name="point_labels", shape=(1, 1))
    ],
    compute_units=ct.ComputeUnit.ALL,
    minimum_deployment_target=ct.target.iOS17
)

decoder_model.save("SAM_MaskDecoder.mlpackage")
```

## Alternative: Use MobileNetV3 Segmentation (Quick Start)

If SAM conversion is too complex, you can start with a simpler segmentation model:

```python
import torch
import torchvision
import coremltools as ct

# Load a pre-trained segmentation model
model = torchvision.models.segmentation.deeplabv3_mobilenet_v3_large(pretrained=True)
model.eval()

# Trace the model
example_input = torch.randn(1, 3, 512, 512)
traced_model = torch.jit.trace(model, example_input)

# Convert to CoreML
coreml_model = ct.convert(
    traced_model,
    inputs=[ct.ImageType(name="image", shape=(1, 3, 512, 512))],
    compute_units=ct.ComputeUnit.ALL,
    minimum_deployment_target=ct.target.iOS17
)

coreml_model.save("MobileSegmentation.mlpackage")
```

Then update `ModelConfiguration` in the app to use "MobileSegmentation" instead of "EdgeTAM".

## Adding Model to Xcode Project

### Step 1: Locate the Model File

After conversion, you should have:
- `EdgeTAM.mlpackage` (or `MobileSegmentation.mlpackage`)

### Step 2: Add to Xcode

1. Open `EdgeTAM-iOS.xcodeproj` in Xcode
2. In Project Navigator, right-click on `EdgeTAM-iOS` folder
3. Select "Add Files to EdgeTAM-iOS..."
4. Navigate to your `.mlpackage` file
5. **Important**: Check "Copy items if needed"
6. **Important**: Ensure "EdgeTAM-iOS" target is selected
7. Click "Add"

### Step 3: Verify Model Integration

1. In Project Navigator, click on the `.mlpackage` file
2. Xcode will show model details:
   - Inputs
   - Outputs
   - Model class (auto-generated Swift code)
3. Verify the model is in the "EdgeTAM-iOS" target membership

### Step 4: Update Model Name (if needed)

If you used a different model name, update `ModelConfiguration`:

```swift
// In EdgeTAM-iOS/Models/DataModels.swift
struct ModelConfiguration {
    let modelName: String = "MobileSegmentation"  // Change this
    // ... rest of configuration
}
```

## Testing the Model

### Step 1: Build the App

```bash
# Clean build
xcodebuild -project EdgeTAM-iOS.xcodeproj \
  -scheme EdgeTAM-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build
```

### Step 2: Run on Device

1. Connect iPhone via USB
2. Select device in Xcode
3. Click Run (⌘R)
4. Grant camera permissions
5. Tap on objects to test segmentation

### Step 3: Verify Model Loading

Check console for:
```
✓ CoreML model loaded from: EdgeTAM.mlmodelc
✓ Model loaded successfully in X.XXs
```

## Troubleshooting

### Issue: "Cannot trace model"

**Solution**: SAM has a complex architecture. Try:
1. Export components separately (image encoder, mask decoder)
2. Use ONNX as intermediate format
3. Simplify model architecture
4. Use a simpler segmentation model for testing

### Issue: "Model too large"

**Solution**:
1. Use ViT-B instead of ViT-H
2. Quantize the model:
```python
model = ct.convert(
    traced_model,
    inputs=inputs,
    compute_precision=ct.precision.FLOAT16  # Use FP16
)
```

### Issue: "Neural Engine not supported"

**Solution**: Some operations may not be supported on Neural Engine:
```python
model = ct.convert(
    traced_model,
    inputs=inputs,
    compute_units=ct.ComputeUnit.CPU_AND_GPU  # Skip Neural Engine
)
```

### Issue: "Model not found in bundle"

**Solution**:
1. Verify model is in Xcode project
2. Check target membership
3. Clean build folder (⇧⌘K)
4. Rebuild project

## Performance Optimization

### 1. Quantization

Reduce model size and improve inference speed:

```python
model = ct.convert(
    traced_model,
    inputs=inputs,
    compute_precision=ct.precision.FLOAT16
)
```

### 2. Input Size Reduction

Use smaller input size for faster inference:

```python
# Instead of 1024x1024, use 512x512
inputs = [ct.ImageType(name="image", shape=(1, 3, 512, 512))]
```

### 3. Batch Processing

Process multiple frames together (if supported):

```python
inputs = [ct.ImageType(name="image", shape=(4, 3, 512, 512))]  # Batch of 4
```

## Expected Results

### Model Sizes
- **ViT-H**: ~2.4GB (PyTorch) → ~1.2GB (CoreML FP16)
- **ViT-L**: ~1.2GB (PyTorch) → ~600MB (CoreML FP16)
- **ViT-B**: ~375MB (PyTorch) → ~190MB (CoreML FP16)

### Inference Times (iPhone 15 Pro)
- **ViT-H**: ~200-300ms per frame
- **ViT-L**: ~150-200ms per frame
- **ViT-B**: ~100-150ms per frame

### Memory Usage
- **ViT-H**: ~1.5GB during inference
- **ViT-L**: ~800MB during inference
- **ViT-B**: ~500MB during inference

## Next Steps

After successful conversion:

1. ✅ Model loads without errors
2. ✅ Camera view appears (not black screen)
3. ✅ Tap on objects to test segmentation
4. ✅ Verify mask overlays appear
5. ✅ Check performance metrics (FPS)
6. ✅ Test on multiple objects
7. ✅ Test camera switching
8. ✅ Test video export

## Resources

- [Segment Anything GitHub](https://github.com/facebookresearch/segment-anything)
- [CoreML Tools Documentation](https://coremltools.readme.io/)
- [Apple CoreML Guide](https://developer.apple.com/documentation/coreml)
- [SAM Model Checkpoints](https://github.com/facebookresearch/segment-anything#model-checkpoints)

## Support

If you encounter issues:

1. Check the console logs for detailed error messages
2. Verify all dependencies are installed correctly
3. Try with a simpler model first (MobileNetV3)
4. Review the troubleshooting section above
5. Open an issue on GitHub with error details

---

**Note**: The actual SAM model conversion is complex and may require adjustments based on your specific needs. The provided scripts are starting points that may need modification for your use case.
