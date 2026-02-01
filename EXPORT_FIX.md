# EdgeTAM Export - Quick Fix

## Issue

The `export_edgetam_models.sh` script was trying to use the wrong repository. The `export_to_coreml.py` script requires the SAM2 (Segment Anything 2) repository, not the Track-Anything repository.

## Solution

Use the new `run_export.sh` script which:
1. Uses your existing checkpoint at `EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt`
2. Clones the correct SAM2 repository
3. Installs dependencies
4. Runs the export

## Quick Start

```bash
# Run the fixed export script
./run_export.sh
```

This will:
- ✅ Use your existing 53MB checkpoint
- ✅ Clone segment-anything-2 repository
- ✅ Install all dependencies
- ✅ Export three CoreML models
- ✅ Take ~10-20 minutes

## What You'll Get

```
coreml_models/
├── edgetam_image_encoder.mlpackage
├── edgetam_prompt_encoder.mlpackage
└── edgetam_mask_decoder.mlpackage
```

## Then Add to Xcode

1. Open `EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj`
2. Drag all three `.mlpackage` files from `coreml_models/` into project
3. Check "Copy items if needed"
4. Select "EdgeTAM-iOS" target
5. Click "Add"

## Alternative: Manual Steps

If the script doesn't work, run these commands manually:

```bash
# 1. Setup environment
python3 -m venv export_env
source export_env/bin/activate

# 2. Install dependencies
pip install torch torchvision coremltools numpy pillow hydra-core omegaconf

# 3. Clone SAM2
git clone https://github.com/facebookresearch/segment-anything-2.git
cd segment-anything-2
pip install -e .
cd ..

# 4. Run export
python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

## Troubleshooting

### "Config file not found"

The SAM2 repository structure may vary. Try these paths:
- `segment-anything-2/sam2_configs/sam2_hiera_l.yaml`
- `segment-anything-2/sam2/configs/sam2/sam2_hiera_l.yaml`

### "Module 'sam2' not found"

```bash
cd segment-anything-2
pip install -e .
cd ..
```

### "Checkpoint format error"

The checkpoint at `EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt` should be compatible with SAM2. If not, you may need to download the SAM2 checkpoint:

```bash
cd segment-anything-2/checkpoints
wget https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_large.pt
cd ../..

# Then use this checkpoint in the export command
python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint segment-anything-2/checkpoints/sam2_hiera_large.pt \
    --output_dir ./coreml_models
```

## Summary

The key issue was using the wrong repository. The `export_to_coreml.py` script needs:
- ✅ SAM2 repository (segment-anything-2)
- ✅ SAM2 config file
- ✅ Compatible checkpoint

Use `./run_export.sh` for the easiest setup!
