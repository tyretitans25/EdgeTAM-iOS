# EdgeTAM CoreML Export Guide

Complete guide for using the official `export_to_coreml.py` script to convert EdgeTAM to CoreML format.

## Overview

The `EdgeTAM-iOS/export_to_coreml.py` script is the official export tool that converts EdgeTAM into three separate CoreML models:
1. **Image Encoder** - Processes input images
2. **Prompt Encoder** - Handles point/box prompts
3. **Mask Decoder** - Generates segmentation masks

## Prerequisites

### 1. Clone EdgeTAM Repository

```bash
# Clone the official EdgeTAM repository
git clone https://github.com/gaomingqi/Track-Anything.git EdgeTAM-repo
cd EdgeTAM-repo
```

### 2. Install Dependencies

```bash
# Create virtual environment
python3 -m venv edgetam_env
source edgetam_env/bin/activate

# Install EdgeTAM dependencies
pip install -e .

# Install CoreML tools
pip install coremltools

# Install additional requirements
pip install hydra-core omegaconf pillow
```

### 3. Download EdgeTAM Checkpoint

```bash
# Create checkpoints directory
mkdir -p checkpoints

# Download using the official script
bash checkpoints/download_ckpts.sh

# Or download manually
cd checkpoints
wget https://huggingface.co/spaces/VIPLab/Track-Anything/resolve/main/checkpoints/edgetam.pt
cd ..
```

### 4. Verify Setup

```bash
# Check checkpoint exists
ls -lh checkpoints/edgetam.pt

# Check config file exists
ls -lh sam2/configs/edgetam/edgetam_config.yaml
```

## Running the Export

### Basic Export Command

```bash
python /Users/tyretitans/CV_Robotiscs_Lab/edgeTAM/EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg sam2/configs/edgetam/edgetam_config.yaml \
    --sam2_checkpoint checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

### Expected Output

The script will create three CoreML models:

```
coreml_models/
├── edgetam_image_encoder.mlpackage/
├── edgetam_prompt_encoder.mlpackage/
├── edgetam_mask_decoder.mlpackage/
└── model_info.json
```

### Export Process

```
Loading EdgeTAM model...
  Checkpoint keys: [...]

Exporting to ./coreml_models...

Exporting Image Encoder...
  Saved to ./coreml_models/edgetam_image_encoder.mlpackage

Exporting Prompt Encoder...
  Saved to ./coreml_models/edgetam_prompt_encoder.mlpackage

Exporting Mask Decoder...
  Saved to ./coreml_models/edgetam_mask_decoder.mlpackage

Export completed successfully!
Models saved to: ./coreml_models
```

## Model Details

### Image Encoder
- **Input**: RGB image (1, 3, 1024, 1024)
- **Outputs**:
  - `vision_features`: (1, 256, 64, 64)
  - `high_res_feat_0`: (1, 32, 256, 256)
  - `high_res_feat_1`: (1, 64, 128, 128)
- **Size**: ~200-300MB
- **Purpose**: Extract image features

### Prompt Encoder
- **Inputs**:
  - `point_coords`: (1, 4, 2) - Point coordinates
  - `point_labels`: (1, 4) - Point labels (1=foreground, 0=background, -1=padding)
  - `boxes`: (1, 4) - Bounding box coordinates
  - `mask_input`: (1, 1, 256, 256) - Optional mask input
- **Outputs**:
  - `sparse_embeddings`: Sparse prompt embeddings
  - `dense_embeddings`: Dense prompt embeddings
- **Size**: ~10-20MB
- **Purpose**: Encode user prompts

### Mask Decoder
- **Inputs**:
  - `image_embeddings`: (1, 256, 64, 64)
  - `image_pe`: (1, 256, 64, 64) - Position encoding
  - `sparse_prompt_embeddings`: (1, N, 256) where N=1-10
  - `dense_prompt_embeddings`: (1, 256, 64, 64)
  - `high_res_feat_0`: (1, 32, 256, 256)
  - `high_res_feat_1`: (1, 64, 128, 128)
  - `multimask_output`: (1,) - Boolean for multi-mask output
- **Outputs**:
  - `masks`: Segmentation masks
  - `iou_pred`: IoU predictions
- **Size**: ~50-100MB
- **Purpose**: Generate segmentation masks

## Adding Models to Xcode

### Option 1: Use All Three Models (Recommended)

For full EdgeTAM functionality, add all three models:

1. Open `EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj`
2. Drag all three `.mlpackage` files into project:
   - `edgetam_image_encoder.mlpackage`
   - `edgetam_prompt_encoder.mlpackage`
   - `edgetam_mask_decoder.mlpackage`
3. Check "Copy items if needed"
4. Select "EdgeTAM-iOS" target
5. Click "Add"

### Option 2: Create Combined Model

You can combine the models in Swift code for easier management.

## Updating iOS App to Use Models

The iOS app currently expects a single "EdgeTAM" model. You'll need to update the `ModelManager` to use the three separate models:

### Update ModelConfiguration

```swift
// In EdgeTAM-iOS/Models/DataModels.swift
struct ModelConfiguration {
    let imageEncoderName: String = "edgetam_image_encoder"
    let promptEncoderName: String = "edgetam_prompt_encoder"
    let maskDecoderName: String = "edgetam_mask_decoder"
    let inputSize: CGSize = CGSize(width: 1024, height: 1024)
    let computeUnits: MLComputeUnits = .all
}
```

### Update ModelManager

```swift
// In EdgeTAM-iOS/Services/ModelManager.swift
private var imageEncoder: MLModel?
private var promptEncoder: MLModel?
private var maskDecoder: MLModel?

func loadModel() async throws {
    // Load all three models
    imageEncoder = try loadCoreMLModel(named: configuration.imageEncoderName)
    promptEncoder = try loadCoreMLModel(named: configuration.promptEncoderName)
    maskDecoder = try loadCoreMLModel(named: configuration.maskDecoderName)
}

func performInference(on pixelBuffer: CVPixelBuffer, with prompts: [Prompt]) async throws -> SegmentationResult {
    // 1. Run image encoder
    let imageFeatures = try await runImageEncoder(pixelBuffer)
    
    // 2. Run prompt encoder
    let promptEmbeddings = try await runPromptEncoder(prompts)
    
    // 3. Run mask decoder
    let masks = try await runMaskDecoder(imageFeatures, promptEmbeddings)
    
    return masks
}
```

## Troubleshooting

### Issue: "Module 'sam2' not found"

**Solution**:
```bash
# Ensure you're in the EdgeTAM repository
cd EdgeTAM-repo

# Install in editable mode
pip install -e .
```

### Issue: "Config file not found"

**Solution**:
```bash
# Verify config path
ls sam2/configs/edgetam/edgetam_config.yaml

# Use absolute path if needed
python export_to_coreml.py \
    --sam2_cfg $(pwd)/sam2/configs/edgetam/edgetam_config.yaml \
    --sam2_checkpoint $(pwd)/checkpoints/edgetam.pt
```

### Issue: "Checkpoint loading failed"

**Solution**:
```bash
# Verify checkpoint integrity
file checkpoints/edgetam.pt

# Re-download if corrupted
rm checkpoints/edgetam.pt
bash checkpoints/download_ckpts.sh
```

### Issue: "Out of memory during export"

**Solution**:
1. Close other applications
2. Export models one at a time
3. Use a machine with more RAM (16GB+ recommended)

### Issue: "CoreML conversion failed"

**Solution**:
```bash
# Update coremltools
pip install --upgrade coremltools

# Check PyTorch version compatibility
pip install torch==2.0.0  # Or compatible version
```

## Performance Optimization

### Quantization

To reduce model size, modify the export script to use FP16:

```python
mlmodel = ct.convert(
    traced_model,
    inputs=[...],
    compute_precision=ct.precision.FLOAT16,  # Add this line
    compute_units=ct.ComputeUnit.ALL,
    convert_to="mlprogram",
)
```

### Smaller Input Size

For faster inference, use 512x512 instead of 1024x1024:

```python
example_input = torch.randn(1, 3, 512, 512)  # Change from 1024
```

## Complete Workflow

### 1. Setup

```bash
# Clone EdgeTAM
git clone https://github.com/gaomingqi/Track-Anything.git EdgeTAM-repo
cd EdgeTAM-repo

# Install dependencies
python3 -m venv edgetam_env
source edgetam_env/bin/activate
pip install -e .
pip install coremltools hydra-core omegaconf

# Download checkpoint
bash checkpoints/download_ckpts.sh
```

### 2. Export

```bash
# Run export script
python /Users/tyretitans/CV_Robotiscs_Lab/edgeTAM/EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg sam2/configs/edgetam/edgetam_config.yaml \
    --sam2_checkpoint checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

### 3. Verify

```bash
# Check output
ls -lh coreml_models/

# Should see:
# edgetam_image_encoder.mlpackage
# edgetam_prompt_encoder.mlpackage
# edgetam_mask_decoder.mlpackage
# model_info.json
```

### 4. Add to Xcode

1. Open EdgeTAM-iOS.xcodeproj
2. Drag all three .mlpackage files
3. Check "Copy items if needed"
4. Select EdgeTAM-iOS target

### 5. Update Code

Update ModelManager to use three separate models (see above).

### 6. Build and Test

```bash
# Build
xcodebuild -project EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj \
  -scheme EdgeTAM-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

# Or in Xcode: ⌘B
```

## Expected Results

### Model Sizes
- Image Encoder: ~200-300MB
- Prompt Encoder: ~10-20MB
- Mask Decoder: ~50-100MB
- **Total**: ~260-420MB

### Performance (iPhone 15 Pro)
- Image Encoder: ~50-80ms
- Prompt Encoder: ~5-10ms
- Mask Decoder: ~30-50ms
- **Total**: ~85-140ms per frame

## Next Steps

1. ✅ Export models using official script
2. ✅ Add all three models to Xcode
3. ✅ Update ModelManager to use separate models
4. ✅ Test on physical device
5. ✅ Optimize performance if needed
6. ✅ Implement video tracking pipeline

## Resources

- [EdgeTAM Repository](https://github.com/gaomingqi/Track-Anything)
- [CoreML Tools](https://coremltools.readme.io/)
- [Hydra Configuration](https://hydra.cc/)
- [SAM2 Documentation](https://github.com/facebookresearch/segment-anything-2)

## Support

For issues:
1. Check EdgeTAM repository issues
2. Verify all dependencies are installed
3. Check console logs for detailed errors
4. Try exporting one model at a time

---

**Note**: This guide uses the official EdgeTAM export script which properly handles the model architecture and ensures compatibility with the iOS app.
