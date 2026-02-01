#!/bin/bash

# EdgeTAM CoreML Export Automation Script
# This script automates the entire process of exporting EdgeTAM to CoreML

set -e

echo "=========================================="
echo "EdgeTAM CoreML Export Automation"
echo "=========================================="
echo ""

# Configuration
EDGETAM_REPO="EdgeTAM-repo"
OUTPUT_DIR="coreml_models"
EXPORT_SCRIPT="/Users/tyretitans/CV_Robotiscs_Lab/edgeTAM/EdgeTAM-iOS/export_to_coreml.py"

# Step 1: Check if SAM2 repo exists
if [ ! -d "$EDGETAM_REPO" ]; then
    echo "Step 1: Cloning Segment Anything 2 repository..."
    git clone https://github.com/facebookresearch/segment-anything-2.git $EDGETAM_REPO
else
    echo "Step 1: Segment Anything 2 repository already exists"
fi

cd $EDGETAM_REPO

# Step 2: Setup Python environment
echo ""
echo "Step 2: Setting up Python environment..."

if [ ! -d "edgetam_env" ]; then
    echo "  Creating virtual environment..."
    python3 -m venv edgetam_env
fi

echo "  Activating virtual environment..."
source edgetam_env/bin/activate

echo "  Installing dependencies..."
pip install -q --upgrade pip
pip install -q -e .
pip install -q coremltools hydra-core omegaconf pillow

# Step 3: Download checkpoint
echo ""
echo "Step 3: Downloading EdgeTAM/SAM2 checkpoint..."

if [ ! -f "checkpoints/sam2_hiera_large.pt" ]; then
    mkdir -p checkpoints
    cd checkpoints
    
    echo "  Downloading SAM2 checkpoint..."
    if command -v wget &> /dev/null; then
        wget https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_large.pt
    else
        curl -L -O https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_large.pt
    fi
    cd ..
else
    echo "  Checkpoint already exists"
fi

# Verify checkpoint
if [ -f "checkpoints/sam2_hiera_large.pt" ]; then
    FILE_SIZE=$(du -h checkpoints/sam2_hiera_large.pt | cut -f1)
    echo "  ✓ Checkpoint ready: $FILE_SIZE"
else
    echo "  ✗ Failed to download checkpoint"
    exit 1
fi

# Step 4: Verify config file
echo ""
echo "Step 4: Verifying configuration..."

CONFIG_FILE="sam2_configs/sam2_hiera_l.yaml"
if [ -f "$CONFIG_FILE" ]; then
    echo "  ✓ Config file found: $CONFIG_FILE"
else
    echo "  ✗ Config file not found: $CONFIG_FILE"
    echo "  Checking alternative locations..."
    
    # Try alternative paths
    if [ -f "sam2/configs/sam2/sam2_hiera_l.yaml" ]; then
        CONFIG_FILE="sam2/configs/sam2/sam2_hiera_l.yaml"
        echo "  ✓ Found at: $CONFIG_FILE"
    else
        echo "  ✗ Config file not found"
        echo "  Please check SAM2 repository structure"
        exit 1
    fi
fi

# Step 5: Run export
echo ""
echo "Step 5: Exporting to CoreML..."
echo "  This may take 10-20 minutes..."
echo ""

python $EXPORT_SCRIPT \
    --sam2_cfg $CONFIG_FILE \
    --sam2_checkpoint checkpoints/sam2_hiera_large.pt \
    --output_dir $OUTPUT_DIR

# Step 6: Verify output
echo ""
echo "Step 6: Verifying exported models..."

if [ -d "$OUTPUT_DIR/edgetam_image_encoder.mlpackage" ] && \
   [ -d "$OUTPUT_DIR/edgetam_prompt_encoder.mlpackage" ] && \
   [ -d "$OUTPUT_DIR/edgetam_mask_decoder.mlpackage" ]; then
    
    echo "  ✓ All models exported successfully!"
    echo ""
    echo "  Models:"
    du -h $OUTPUT_DIR/*.mlpackage | while read size path; do
        echo "    - $(basename $path): $size"
    done
else
    echo "  ✗ Some models are missing"
    exit 1
fi

# Step 7: Copy to iOS project
echo ""
echo "Step 7: Copying models to iOS project..."

IOS_PROJECT_DIR="../EdgeTAM-iOS/EdgeTAM-iOS"
if [ -d "$IOS_PROJECT_DIR" ]; then
    echo "  Copying models..."
    cp -r $OUTPUT_DIR/*.mlpackage $IOS_PROJECT_DIR/
    echo "  ✓ Models copied to $IOS_PROJECT_DIR"
    echo ""
    echo "  IMPORTANT: You must add these files to Xcode:"
    echo "    1. Open EdgeTAM-iOS.xcodeproj"
    echo "    2. Drag the .mlpackage files into the project"
    echo "    3. Check 'Copy items if needed'"
    echo "    4. Select 'EdgeTAM-iOS' target"
else
    echo "  iOS project directory not found: $IOS_PROJECT_DIR"
    echo "  Models are available in: $(pwd)/$OUTPUT_DIR"
fi

echo ""
echo "=========================================="
echo "✓ Export completed successfully!"
echo "=========================================="
echo ""
echo "Exported models location:"
echo "  $(pwd)/$OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Add models to Xcode project (see above)"
echo "  2. Update ModelManager to use three separate models"
echo "  3. Build and test the app"
echo ""
echo "See EXPORT_EDGETAM_GUIDE.md for detailed instructions"
echo ""
