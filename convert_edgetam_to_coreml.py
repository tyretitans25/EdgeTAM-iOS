#!/usr/bin/env python3
"""
EdgeTAM to CoreML Conversion Script

This script converts Meta's EdgeTAM (Segment Anything Model) from PyTorch to CoreML format
for use in the EdgeTAM iOS application.

Requirements:
    - Python 3.8+
    - torch
    - torchvision
    - coremltools
    - numpy
    - pillow
    - segment-anything package

Usage:
    python convert_edgetam_to_coreml.py --checkpoint path/to/sam_checkpoint.pth --output EdgeTAM.mlpackage
"""

import argparse
import sys
import os
from pathlib import Path

try:
    import torch
    import coremltools as ct
    import numpy as np
    from PIL import Image
except ImportError as e:
    print(f"Error: Missing required package: {e}")
    print("\nPlease install required packages:")
    print("pip install torch torchvision coremltools numpy pillow")
    sys.exit(1)

def check_segment_anything():
    """Check if segment-anything package is available"""
    try:
        from segment_anything import sam_model_registry, SamPredictor
        return True
    except ImportError:
        print("Error: segment-anything package not found")
        print("\nPlease install segment-anything:")
        print("pip install git+https://github.com/facebookresearch/segment-anything.git")
        return False

def load_sam_model(checkpoint_path, model_type="vit_h"):
    """Load SAM model from checkpoint"""
    from segment_anything import sam_model_registry
    
    print(f"Loading SAM model (type: {model_type}) from {checkpoint_path}...")
    
    if not os.path.exists(checkpoint_path):
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path}")
    
    sam = sam_model_registry[model_type](checkpoint=checkpoint_path)
    sam.eval()
    
    print("✓ Model loaded successfully")
    return sam

def create_traced_model(sam_model, image_size=1024):
    """Create a traced version of the SAM model"""
    print(f"Creating traced model (image size: {image_size}x{image_size})...")
    
    # Create example inputs
    example_image = torch.randn(1, 3, image_size, image_size)
    example_point_coords = torch.randn(1, 1, 2)  # Single point
    example_point_labels = torch.ones(1, 1)      # Foreground point
    
    # Trace the model
    # Note: This is a simplified version. Full SAM has multiple components
    # that may need separate tracing
    try:
        with torch.no_grad():
            traced_model = torch.jit.trace(
                sam_model,
                (example_image, example_point_coords, example_point_labels),
                strict=False
            )
        print("✓ Model traced successfully")
        return traced_model
    except Exception as e:
        print(f"Error tracing model: {e}")
        print("\nNote: SAM has a complex architecture. You may need to:")
        print("1. Export individual components (image encoder, prompt encoder, mask decoder)")
        print("2. Use ONNX as an intermediate format")
        print("3. Simplify the model architecture")
        raise

def convert_to_coreml(traced_model, output_path, image_size=1024):
    """Convert traced PyTorch model to CoreML"""
    print(f"Converting to CoreML format...")
    
    try:
        # Define input types
        inputs = [
            ct.ImageType(
                name="image",
                shape=(1, 3, image_size, image_size),
                scale=1.0/255.0,  # Normalize to [0, 1]
                bias=[0, 0, 0]
            ),
            ct.TensorType(
                name="point_coords",
                shape=(1, 1, 2)  # (batch, num_points, 2)
            ),
            ct.TensorType(
                name="point_labels",
                shape=(1, 1)  # (batch, num_points)
            )
        ]
        
        # Define output types
        outputs = [
            ct.TensorType(
                name="masks",
                shape=(1, 1, image_size, image_size)
            ),
            ct.TensorType(
                name="iou_predictions",
                shape=(1, 1)
            )
        ]
        
        # Convert to CoreML
        model = ct.convert(
            traced_model,
            inputs=inputs,
            outputs=outputs,
            compute_units=ct.ComputeUnit.ALL,  # Use Neural Engine + GPU + CPU
            minimum_deployment_target=ct.target.iOS17,
            convert_to="mlprogram"  # Use ML Program format (newer)
        )
        
        # Add metadata
        model.author = "Meta AI"
        model.license = "Apache 2.0"
        model.short_description = "EdgeTAM - Efficient video segmentation for mobile devices"
        model.version = "1.0"
        
        # Add input descriptions
        model.input_description["image"] = "Input image (1024x1024 RGB)"
        model.input_description["point_coords"] = "Point prompt coordinates (normalized 0-1)"
        model.input_description["point_labels"] = "Point labels (1=foreground, 0=background)"
        
        # Add output descriptions
        model.output_description["masks"] = "Segmentation masks (1024x1024)"
        model.output_description["iou_predictions"] = "Intersection over Union predictions"
        
        # Save the model
        model.save(output_path)
        print(f"✓ CoreML model saved to: {output_path}")
        
        return model
        
    except Exception as e:
        print(f"Error converting to CoreML: {e}")
        raise

def verify_coreml_model(model_path):
    """Verify the converted CoreML model"""
    print(f"\nVerifying CoreML model...")
    
    try:
        # Load the model
        model = ct.models.MLModel(model_path)
        
        # Print model information
        spec = model.get_spec()
        print(f"\n✓ Model verification successful!")
        print(f"  - Format: {spec.specificationVersion}")
        print(f"  - Inputs: {len(spec.description.input)}")
        print(f"  - Outputs: {len(spec.description.output)}")
        
        # Print input details
        print("\n  Input details:")
        for input_desc in spec.description.input:
            print(f"    - {input_desc.name}: {input_desc.type}")
        
        # Print output details
        print("\n  Output details:")
        for output_desc in spec.description.output:
            print(f"    - {output_desc.name}: {output_desc.type}")
        
        return True
        
    except Exception as e:
        print(f"✗ Model verification failed: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Convert EdgeTAM/SAM model to CoreML format"
    )
    parser.add_argument(
        "--checkpoint",
        type=str,
        required=True,
        help="Path to SAM checkpoint file (.pth)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="EdgeTAM.mlpackage",
        help="Output CoreML model path (default: EdgeTAM.mlpackage)"
    )
    parser.add_argument(
        "--model-type",
        type=str,
        default="vit_h",
        choices=["vit_h", "vit_l", "vit_b"],
        help="SAM model type (default: vit_h)"
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
    
    # Check dependencies
    if not check_segment_anything():
        sys.exit(1)
    
    try:
        # Step 1: Load SAM model
        sam_model = load_sam_model(args.checkpoint, args.model_type)
        
        # Step 2: Create traced model
        traced_model = create_traced_model(sam_model, args.image_size)
        
        # Step 3: Convert to CoreML
        coreml_model = convert_to_coreml(traced_model, args.output, args.image_size)
        
        # Step 4: Verify the model
        verify_coreml_model(args.output)
        
        print("\n" + "=" * 60)
        print("✓ Conversion completed successfully!")
        print("=" * 60)
        print(f"\nNext steps:")
        print(f"1. Open EdgeTAM-iOS.xcodeproj in Xcode")
        print(f"2. Drag {args.output} into the project navigator")
        print(f"3. Ensure 'Copy items if needed' is checked")
        print(f"4. Add to EdgeTAM-iOS target")
        print(f"5. Build and run the app")
        
    except Exception as e:
        print(f"\n✗ Conversion failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
