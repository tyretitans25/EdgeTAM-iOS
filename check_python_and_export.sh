#!/bin/bash

# Check Python Version and Export EdgeTAM Models

echo "=========================================="
echo "EdgeTAM Export - Python Version Check"
echo "=========================================="
echo ""

# Check current Python version
CURRENT_PYTHON=$(python3 --version 2>&1 | awk '{print $2}')
echo "Current Python version: $CURRENT_PYTHON"

# Check if Python 3.11 is available
if command -v python3.11 &> /dev/null; then
    echo "✓ Python 3.11 found!"
    PYTHON_CMD="python3.11"
elif command -v python3.10 &> /dev/null; then
    echo "✓ Python 3.10 found (acceptable)"
    PYTHON_CMD="python3.10"
else
    echo "✗ Python 3.11 or 3.10 not found"
    echo ""
    echo "Python 3.14 is too new for CoreMLTools."
    echo "Please install Python 3.11:"
    echo ""
    echo "  brew install python@3.11"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo ""
echo "Using: $PYTHON_CMD"
echo ""

# Create environment with correct Python version
ENV_NAME="edgetam_export_py311"

if [ ! -d "$ENV_NAME" ]; then
    echo "Creating virtual environment with $PYTHON_CMD..."
    $PYTHON_CMD -m venv $ENV_NAME
fi

source $ENV_NAME/bin/activate

echo "Installing dependencies..."
pip install -q --upgrade pip
pip install -q torch torchvision coremltools numpy pillow hydra-core omegaconf

# Clone SAM2 if needed
if [ ! -d "segment-anything-2" ]; then
    echo "Cloning Segment Anything 2..."
    git clone https://github.com/facebookresearch/segment-anything-2.git
    cd segment-anything-2
    pip install -q -e .
    cd ..
else
    echo "✓ SAM2 repository exists"
fi

# Verify coremltools works
echo ""
echo "Verifying CoreMLTools..."
python -c "import coremltools as ct; print('CoreMLTools version:', ct.__version__)" 2>&1 | grep -v "Failed to load" | grep "CoreMLTools"

if [ $? -eq 0 ]; then
    echo "✓ CoreMLTools is working!"
else
    echo "✗ CoreMLTools has issues"
    exit 1
fi

# Find config file
CONFIG_FILE=""
if [ -f "segment-anything-2/sam2_configs/sam2_hiera_l.yaml" ]; then
    CONFIG_FILE="segment-anything-2/sam2_configs/sam2_hiera_l.yaml"
elif [ -f "segment-anything-2/sam2/configs/sam2/sam2_hiera_l.yaml" ]; then
    CONFIG_FILE="segment-anything-2/sam2/configs/sam2/sam2_hiera_l.yaml"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "✗ Config file not found"
    exit 1
fi

echo "✓ Config file: $CONFIG_FILE"

# Check checkpoint
CHECKPOINT="EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt"
if [ ! -f "$CHECKPOINT" ]; then
    echo "✗ Checkpoint not found: $CHECKPOINT"
    exit 1
fi

echo "✓ Checkpoint found"
echo ""

# Run export
echo "=========================================="
echo "Running Export (10-20 minutes)..."
echo "=========================================="
echo ""

python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg "$CONFIG_FILE" \
    --sam2_checkpoint "$CHECKPOINT" \
    --output_dir ./coreml_models

# Check results
if [ -d "coreml_models/edgetam_image_encoder.mlpackage" ] && \
   [ -d "coreml_models/edgetam_prompt_encoder.mlpackage" ] && \
   [ -d "coreml_models/edgetam_mask_decoder.mlpackage" ]; then
    
    echo ""
    echo "=========================================="
    echo "✓ Export Successful!"
    echo "=========================================="
    echo ""
    echo "Models created:"
    du -h coreml_models/*.mlpackage | while read size path; do
        echo "  - $(basename $path): $size"
    done
    echo ""
    echo "Next steps:"
    echo "1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj"
    echo "2. Drag .mlpackage files from coreml_models/ into Xcode"
    echo "3. Check 'Copy items if needed'"
    echo "4. Select 'EdgeTAM-iOS' target"
    echo "5. Build and run!"
else
    echo ""
    echo "✗ Export failed - check errors above"
    exit 1
fi
