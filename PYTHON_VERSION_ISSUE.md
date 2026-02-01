# Python Version Issue with CoreML Export

## Problem

The CoreML export is failing because:
1. **Python 3.14 is too new** - CoreMLTools doesn't have pre-compiled binaries for Python 3.14
2. **Missing libraries**: `coremltools.libcoremlpython` and `coremltools.libmilstoragepython` are not available

## Error Messages

```
Failed to load _MLModelProxy: No module named 'coremltools.libcoremlpython'
Fail to import BlobReader from libmilstoragepython
```

## Solutions

### Solution 1: Use Python 3.11 (Recommended)

Install Python 3.11 and create a new environment:

```bash
# Install Python 3.11 via Homebrew
brew install python@3.11

# Create new environment with Python 3.11
python3.11 -m venv export_env_py311
source export_env_py311/bin/activate

# Install dependencies
pip install torch torchvision coremltools numpy pillow hydra-core omegaconf

# Clone SAM2
git clone https://github.com/facebookresearch/segment-anything-2.git
cd segment-anything-2
pip install -e .
cd ..

# Run export
python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

### Solution 2: Use Docker

Create a Docker container with Python 3.11:

```bash
# Create Dockerfile
cat > Dockerfile <<'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y git wget

RUN pip install torch torchvision coremltools numpy pillow hydra-core omegaconf

CMD ["/bin/bash"]
EOF

# Build and run
docker build -t edgetam-export .
docker run -it -v $(pwd):/app edgetam-export

# Inside container:
git clone https://github.com/facebookresearch/segment-anything-2.git
cd segment-anything-2
pip install -e .
cd ..

python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

### Solution 3: Use Conda

```bash
# Install Miniconda
brew install miniconda

# Create environment with Python 3.11
conda create -n edgetam python=3.11
conda activate edgetam

# Install dependencies
pip install torch torchvision coremltools numpy pillow hydra-core omegaconf

# Clone SAM2
git clone https://github.com/facebookresearch/segment-anything-2.git
cd segment-anything-2
pip install -e .
cd ..

# Run export
python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

### Solution 4: Use Pre-built Models (Temporary Workaround)

For now, you can use the app without the model to test the UI:

1. The app already has graceful error handling
2. It shows a beautiful setup screen when the model is missing
3. You can test all UI features except actual segmentation

## Recommended Approach

**Use Solution 1 (Python 3.11 via Homebrew)** - This is the simplest and most reliable:

```bash
# 1. Install Python 3.11
brew install python@3.11

# 2. Create fresh environment
python3.11 -m venv edgetam_export_env
source edgetam_export_env/bin/activate

# 3. Install everything
pip install torch torchvision coremltools numpy pillow hydra-core omegaconf
git clone https://github.com/facebookresearch/segment-anything-2.git
cd segment-anything-2 && pip install -e . && cd ..

# 4. Run export
python EdgeTAM-iOS/export_to_coreml.py \
    --sam2_cfg segment-anything-2/sam2_configs/sam2_hiera_l.yaml \
    --sam2_checkpoint EdgeTAM-iOS/EdgeTAM-iOS/Model_Checkpoints/edgetam.pt \
    --output_dir ./coreml_models
```

## Why This Happened

- Python 3.14 was released very recently (October 2024)
- CoreMLTools hasn't released pre-compiled binaries for Python 3.14 yet
- The library needs to be compiled from source, which requires additional build tools
- Python 3.11 is the most stable version for CoreMLTools

## Verification

After installing Python 3.11 and coremltools, verify it works:

```bash
python -c "import coremltools as ct; print('CoreMLTools:', ct.__version__)"
```

You should see:
```
CoreMLTools: 7.2
```

Without the "Failed to load" errors.

## Timeline

- **Immediate**: Use Python 3.11 (Solution 1)
- **Short-term**: CoreMLTools will likely add Python 3.14 support in coming months
- **Long-term**: Python 3.14 will become standard

## Support

If you encounter issues:
1. Verify Python version: `python --version`
2. Check coremltools installation: `pip show coremltools`
3. Try in a fresh virtual environment
4. Use Docker if local setup fails

---

**Bottom Line**: Install Python 3.11 via Homebrew and use that for the export. Python 3.14 is too new for CoreMLTools.
