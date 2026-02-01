# Model Conversion for EdgeTAM iOS App

This directory contains scripts and guides for converting segmentation models to CoreML format for use in the EdgeTAM iOS application.

## Quick Start (Recommended for Testing)

If you want to test the app immediately with a working model:

```bash
# Install dependencies
pip install torch torchvision coremltools numpy

# Run the quick setup script
python quick_setup_model.py
```

This will:
- Download a lightweight segmentation model (~50MB)
- Convert it to CoreML format
- Create `EdgeTAM.mlpackage` ready to use
- Takes ~5-10 minutes

**Then add to Xcode:**
1. Open `EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj`
2. Drag `EdgeTAM.mlpackage` into project
3. Check "Copy items if needed"
4. Select "EdgeTAM-iOS" target
5. Build and run!

## Full EdgeTAM Conversion (Production)

For the actual EdgeTAM model with best quality:

```bash
# Install dependencies
pip install torch torchvision coremltools numpy pillow
pip install git+https://github.com/facebookresearch/segment-anything.git

# Download SAM checkpoint (choose one)
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth  # 375MB
# OR
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth  # 2.4GB

# Convert to CoreML
python convert_edgetam_to_coreml.py \
    --checkpoint sam_vit_b_01ec64.pth \
    --output EdgeTAM.mlpackage \
    --model-type vit_b
```

See `EDGETAM_CONVERSION_GUIDE.md` for detailed instructions.

## Files in This Directory

| File | Purpose |
|------|---------|
| `quick_setup_model.py` | Quick setup with lightweight model (recommended for testing) |
| `convert_edgetam_to_coreml.py` | Full EdgeTAM/SAM conversion script |
| `EDGETAM_CONVERSION_GUIDE.md` | Comprehensive conversion guide |
| `MODEL_CONVERSION_README.md` | This file |

## Comparison: Quick Setup vs Full EdgeTAM

| Feature | Quick Setup | Full EdgeTAM |
|---------|-------------|--------------|
| Download size | ~50MB | ~375MB - 2.4GB |
| Conversion time | 5-10 minutes | 30-60 minutes |
| Model size | ~40MB | ~190MB - 1.2GB |
| Quality | Good | Excellent |
| Speed | Fast | Medium |
| Use case | Testing, development | Production |

## Recommended Workflow

1. **Start with Quick Setup**
   - Get the app running quickly
   - Test UI and features
   - Verify everything works

2. **Upgrade to EdgeTAM**
   - When ready for production
   - Follow full conversion guide
   - Replace the model file

## System Requirements

### For Quick Setup
- Python 3.8+
- 2GB free disk space
- 4GB RAM
- 10 minutes

### For Full EdgeTAM
- Python 3.8+
- 10GB free disk space
- 16GB RAM (recommended)
- 1 hour

## Troubleshooting

### "Module not found" errors
```bash
pip install --upgrade torch torchvision coremltools numpy
```

### "Out of memory" errors
- Close other applications
- Use ViT-B instead of ViT-H
- Try quick setup model instead

### "Model not found in bundle" in Xcode
1. Verify model is in project navigator
2. Check target membership (EdgeTAM-iOS)
3. Clean build folder (⇧⌘K)
4. Rebuild

### Model loads but segmentation doesn't work
- The quick setup model uses different architecture
- May need to adjust ModelManager inference code
- Consider using full EdgeTAM for production

## Next Steps After Conversion

1. Add model to Xcode project
2. Build and run app
3. Test camera functionality
4. Test object selection
5. Verify segmentation masks
6. Check performance metrics

## Support

For issues or questions:
1. Check `EDGETAM_CONVERSION_GUIDE.md` for detailed troubleshooting
2. Review console logs in Xcode
3. Open an issue on GitHub with error details

## Important Notes

- **Quick Setup Model**: Not the actual EdgeTAM, but works for testing
- **Full EdgeTAM**: Requires significant resources and time
- **Model Size**: Large models may impact app size and performance
- **Testing**: Always test on physical device for accurate performance

## License

- Quick setup model (DeepLabV3-MobileNetV3): BSD License
- EdgeTAM/SAM: Apache 2.0 License
- Conversion scripts: MIT License
