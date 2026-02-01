#!/usr/bin/env python3
"""
EdgeTAM to CoreML Conversion Script

This script converts the EdgeTAM model checkpoint to CoreML format
for use in the EdgeTAM iOS application.

Requirements:
    - Python 3.8+
    - torch
    - torchvision  
    - coremltools
    - numpy
    - EdgeTAM repository cloned

Usage:
    python edgetam_coreml_export.py --checkpoint EdgeTAM/checkpoints/edgetam.pt
"""

import argparse
import sys
import os
from pathlib import Path

try:
    import torch
    import coremltools as ct
    import numpy as np
except ImportError as e:
    print(f"Error: Missing required package: {e}")
    print("\nPlease install required packages:")
    print("pip install torch torchvision coremltools numpy")
    sys.exit(1)

def load_edgetam_model(checkpoint_path):
    """Load EdgeTAM model from checkpoint"""
    print(f"Loading EdgeTAM model from {checkpoint_path}...")
    
    if not os.path.exists(checkpoint_path):
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path}")
    
    try:
        # Load the checkpoint
        checkpoint = torch.load(checkpoint_path, map_location='cpu')
        print("✓ Checkpoint loaded successfully")
        
        # Print checkpoint structure for debugging
        if isinstance(checkpoint, dict):
            print(f"  Checkpoint keys: {list(checkpoint.keys())}")
        
        return checkpoint
    except Exception as e:
        print(f"✗ Failed to load checkpoint: {e}")
        raise

def export_to_coreml(model, output_path="EdgeTAM.mlpackage", image_size=1024):
    """Export EdgeTAM model to CoreML format"""
    print(f"\nExporting to CoreML format...")
    
    try:
        # Set model to evaluation mode
        model.eval()
        
        # Create example inputs
        # EdgeTAM typically expects:
        # - Image: (1, 3, H, W)
        # - Point prompts: (1, N, 2) where N is number of points
        # - Point labels: (1, N) where 1=foreground, 0=background
        
        example_image = torch.randn(1, 3, image_size, image_size)
        example_points = torch.randn(1, 1, 2)  # Single point
        example_labels = torch.ones(1, 1)      # Foreground
        
        print("  Creating traced model...")
        with torch.no_grad():
            # Trace the model
            traced_model = torch.jit.trace(
                model,
                (example_image, example_points, example_labels),
                strict=False
            )
        
        print("  Converting to CoreML...")
        
        # Define inputs
        inputs = [
            ct.ImageType(
                name="image",
                shape=(1, 3, image_size, image_size),
                scale=1.0/255.0,
                bias=[0, 0, 0]
            ),
            ct.TensorType(
                name="point_coords",
                shape=(1, 1, 2)
            ),
            ct.TensorType(
                name="point_labels",
                shape=(1, 1)
            )
        ]
        
        # Convert to CoreML
        coreml_model = ct.convert(
            traced_model,
            inputs=inputs,
            compute_units=ct.ComputeUnit.ALL,
            minimum_deployment_target=ct.target.iOS17,
            convert_to="mlprogram"
        )
        
        # Add metadata
        coreml_model.author = "VIPLab"
        coreml_model.license = "Apache 2.0"
        coreml_model.short_description = "EdgeTAM - Track Anything Model for mobile devices"
        coreml_model.version = "1.0"
        
        # Save the model
        coreml_model.save(output_path)
        print(f"✓ CoreML model saved to: {output_path}")
        
        return coreml_model
        
    except Exception as e:
        print(f"✗ Export failed: {e}")
        print("\nNote: EdgeTAM has a complex architecture. You may need to:")
        print("1. Export components separately")
        print("2. Modify the model architecture for mobile")
        print("3. Use ONNX as an intermediate format")
        raise

def verify_coreml_model(model_path):
    """Verify the converted CoreML model"""
    print(f"\nVerifying CoreML model...")
    
    try:
        model = ct.models.MLModel(model_path)
        spec = model.get_spec()
        
        print(f"✓ Model verification successful!")
        print(f"  - Inputs: {len(spec.description.input)}")
        print(f"  - Outputs: {len(spec.description.output)}")
        
        # Get file size
        file_size = os.path.getsize(model_path)
        print(f"  - File size: {file_size / (1024*1024):.1f} MB")
        
        return True
    except Exception as e:
        print(f"✗ Verification failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Convert EdgeTAM model to CoreML format"
    )
    parser.add_argument(
        "--checkpoint",
        type=str,
        default="EdgeTAM/checkpoints/edgetam.pt",
        help="Path to EdgeTAM checkpoint file (default: EdgeTAM/checkpoints/edgetam.pt)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="EdgeTAM.mlpackage",
        help="Output CoreML model path (default: EdgeTAM.mlpackage)"
    )
    parser.add_argument(
        "--image-size",
        type=int,
        default=1024,
        help="Input image size (default: 1024)"
    )
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("EdgeTAM to CoreML Conversion")
    print("=" * 60)
    print()
    
    try:
        # Step 1: Load EdgeTAM checkpoint
        checkpoint = load_edgetam_model(args.checkpoint)
        
        # Step 2: Extract model from checkpoint
        # Note: The exact key may vary depending on how the checkpoint was saved
        if isinstance(checkpoint, dict):
            if 'model' in checkpoint:
                model = checkpoint['model']
            elif 'state_dict' in checkpoint:
                # Need to reconstruct model architecture
                print("Warning: Checkpoint contains state_dict only.")
                print("You may need to load the model architecture separately.")
                print("Please refer to EdgeTAM repository for model definition.")
                sys.exit(1)
            else:
                print("Warning: Unexpected checkpoint structure.")
                print("Available keys:", list(checkpoint.keys()))
                sys.exit(1)
        else:
            model = checkpoint
        
        # Step 3: Export to CoreML
        coreml_model = export_to_coreml(model, args.output, args.image_size)
        
        # Step 4: Verify the model
        verify_coreml_model(args.output)
        
        print("\n" + "=" * 60)
        print("✓ Conversion completed successfully!")
        print("=" * 60)
        print(f"\nNext steps:")
        print(f"1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj in Xcode")
        print(f"2. Drag {args.output} into the project navigator")
        print(f"3. Ensure 'Copy items if needed' is checked")
        print(f"4. Add to EdgeTAM-iOS target")
        print(f"5. Build and run the app")
        
    except Exception as e:
        print(f"\n✗ Conversion failed: {e}")
        print("\nTroubleshooting:")
        print("1. Verify checkpoint path is correct")
        print("2. Check EdgeTAM repository for model architecture")
        print("3. Consider using the quick_setup_model.py for testing")
        sys.exit(1)

if __name__ == "__main__":
    main()
