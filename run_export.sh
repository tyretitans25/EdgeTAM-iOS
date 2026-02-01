#!/bin/bash

# Simple EdgeTAM Export Script
# This script runs the export using the existing checkpoint

set -e

echo "=========================================="
echo "EdgeTAM CoreML Export"
echo "=========================================="
echo ""

# Check if checkpoint exists
CHECKPOINT="EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt"
if [ ! -f "$CHECKPOINT" ]; then
    echo "Error: Checkpoint not found at $CHECKPOINT"
    exit 1
fi

echo "✓ Checkpoint found: $CHECKPOINT"
FILE_SIZE=$(du -h "$CHECKPOINT" | cut -f1)
echo "  Size: $FILE_SIZE"
echo ""

# Setup Python environment
echo "Setting up Python environment..."

if [ ! -d "export_env" ]; then
    python3 -m venv export_env
fi

source export_env/bin/activate

echo "Installing dependencies..."
pip install -q --upgrade pip
pip install -q torch torchvision coremltools numpy pillow hydra-core omegaconf

# Check if we need SAM2
echo ""
echo "Checking for SAM2 repository..."

if [ ! -d "segment-anything-2" ]; then
    echo "Cloning Segment Anything 2..."
    git clone https://github.com/facebookresearch/segment-anything-2.git
    cd segment-anything-2
    pip install -q -e .
    cd ..
else
    echo "✓ SAM2 repository exists"
fi

# Find config file
echo ""
echo "Looking for config file..."

CONFIG_FILE=""
if [ -f "segment-anything-2/sam2_configs/sam2_hiera_l.yaml" ]; then
    CONFIG_FILE="segment-anything-2/sam2_configs/sam2_hiera_l.yaml"
elif [ -f "segment-anything-2/sam2/configs/sam2/sam2_hiera_l.yaml" ]; then
    CONFIG_FILE="segment-anything-2/sam2/configs/sam2/sam2_hiera_l.yaml"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "Error: Could not find SAM2 config file"
    echo "Please check segment-anything-2 repository structure"
    exit 1
fi

echo "✓ Config file: $CONFIG_FILE"

# Run export
echo ""
echo "Running export..."
echo "This may take 10-20 minutes..."
echo ""

python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg "$CONFIG_FILE" \
    --sam2_checkpoint "$CHECKPOINT" \
    --output_dir ./coreml_models

# Check results
echo ""
echo "Checking exported models..."

if [ -d "coreml_models/edgetam_image_encoder.mlpackage" ] && \
   [ -d "coreml_models/edgetam_prompt_encoder.mlpackage" ] && \
   [ -d "coreml_models/edgetam_mask_decoder.mlpackage" ]; then
    
    echo "✓ All models exported successfully!"
    echo ""
    echo "Models:"
    du -h coreml_models/*.mlpackage | while read size path; do
        echo "  - $(basename $path): $size"
    done
    
    echo ""
    echo "=========================================="
    echo "✓ Export completed!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj"
    echo "2. Drag the .mlpackage files from coreml_models/ into Xcode"
    echo "3. Check 'Copy items if needed'"
    echo "4. Select 'EdgeTAM-iOS' target"
    echo "5. Build and run"
else
    echo "✗ Export failed - some models are missing"
    exit 1
fi
