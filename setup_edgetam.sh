#!/bin/bash

# EdgeTAM Setup and CoreML Export Script
# This script automates the entire process of setting up EdgeTAM and exporting to CoreML

set -e  # Exit on error

echo "======================================================================"
echo "EdgeTAM Setup and CoreML Export"
echo "======================================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if Python 3.10+ is available
echo "Step 1: Checking Python version..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]); then
    print_error "Python 3.10+ required, found $PYTHON_VERSION"
    exit 1
fi

print_success "Python $PYTHON_VERSION found"

# Create virtual environment
echo ""
echo "Step 2: Creating virtual environment..."
if [ ! -d "edgetam_env" ]; then
    python3 -m venv edgetam_env
    print_success "Virtual environment created"
else
    print_info "Virtual environment already exists"
fi

# Activate virtual environment
source edgetam_env/bin/activate

# Upgrade pip
echo ""
echo "Step 3: Upgrading pip..."
pip install --upgrade pip > /dev/null 2>&1
print_success "pip upgraded"

# Install PyTorch
echo ""
echo "Step 4: Installing PyTorch..."
print_info "This may take several minutes..."
pip install torch>=2.3.1 torchvision>=0.18.1 --index-url https://download.pytorch.org/whl/cpu
print_success "PyTorch installed"

# Install CoreML Tools
echo ""
echo "Step 5: Installing CoreML Tools..."
pip install coremltools
print_success "CoreML Tools installed"

# Install other dependencies
echo ""
echo "Step 6: Installing additional dependencies..."
pip install numpy pillow huggingface_hub
print_success "Additional dependencies installed"

# Clone EdgeTAM repository
echo ""
echo "Step 7: Cloning EdgeTAM repository..."
if [ ! -d "EdgeTAM" ]; then
    git clone https://github.com/facebookresearch/EdgeTAM.git
    print_success "EdgeTAM repository cloned"
else
    print_info "EdgeTAM repository already exists"
    cd EdgeTAM
    git pull
    cd ..
    print_success "EdgeTAM repository updated"
fi

# Install EdgeTAM
echo ""
echo "Step 8: Installing EdgeTAM package..."
cd EdgeTAM
pip install -e .
cd ..
print_success "EdgeTAM package installed"

# Download checkpoint
echo ""
echo "Step 9: Downloading EdgeTAM checkpoint..."
print_info "This will download ~500MB, may take several minutes..."

mkdir -p checkpoints

if [ ! -f "checkpoints/edgetam.pt" ]; then
    python3 -c "
from huggingface_hub import hf_hub_download
checkpoint = hf_hub_download(
    repo_id='facebook/EdgeTAM',
    filename='edgetam.pt',
    local_dir='checkpoints'
)
print(f'Downloaded to: {checkpoint}')
"
    print_success "Checkpoint downloaded"
else
    print_info "Checkpoint already exists"
fi

# Export to CoreML
echo ""
echo "Step 10: Exporting to CoreML format..."
print_info "This may take 10-20 minutes..."

python3 edgetam_coreml_export.py \
    --checkpoint checkpoints/edgetam.pt \
    --output-dir EdgeTAM_CoreML

if [ $? -eq 0 ]; then
    print_success "CoreML export completed"
else
    print_error "CoreML export failed"
    exit 1
fi

# Copy models to Xcode project
echo ""
echo "Step 11: Copying models to Xcode project..."

if [ -d "EdgeTAM-iOS/EdgeTAM-iOS" ]; then
    cp -r EdgeTAM_CoreML/*.mlpackage EdgeTAM-iOS/EdgeTAM-iOS/
    print_success "Models copied to Xcode project"
    print_info "You still need to add them to the project in Xcode"
else
    print_info "EdgeTAM-iOS directory not found"
    print_info "Models are in: EdgeTAM_CoreML/"
fi

# Summary
echo ""
echo "======================================================================"
echo "✓ Setup completed successfully!"
echo "======================================================================"
echo ""
echo "Exported models:"
ls -lh EdgeTAM_CoreML/*.mlpackage 2>/dev/null || echo "  (Check EdgeTAM_CoreML directory)"
echo ""
echo "Next steps:"
echo "1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj in Xcode"
echo "2. Drag the .mlpackage files from EdgeTAM_CoreML/ into the project"
echo "3. Check 'Copy items if needed'"
echo "4. Ensure 'EdgeTAM-iOS' target is selected"
echo "5. Update ModelManager.swift to use the three separate models"
echo "6. Build and run the app"
echo ""
echo "Note: The app currently expects a single 'EdgeTAM.mlpackage'"
echo "You'll need to update the code to use three separate models:"
echo "  - EdgeTAM_ImageEncoder.mlpackage"
echo "  - EdgeTAM_PromptEncoder.mlpackage"
echo "  - EdgeTAM_MaskDecoder.mlpackage"
echo ""

# Deactivate virtual environment
deactivate
