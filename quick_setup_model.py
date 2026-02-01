#!/usr/bin/env python3
"""
Quick Model Setup for EdgeTAM iOS App

This script downloads and converts a lightweight segmentation model
that can be used immediately for testing the EdgeTAM iOS app.

This is NOT the actual EdgeTAM model, but a simpler alternative that:
- Works out of the box
- Requires no large downloads
- Provides basic segmentation functionality
- Can be replaced with EdgeTAM later

Usage:
    python quick_setup_model.py
"""

import sys
import os

try:
    import torch
    import torchvision
    import coremltools as ct
    import numpy as np
except ImportError as e:
    print(f"Error: Missing required package: {e}")
    print("\nPlease install required packages:")
    print("pip install torch torchvision coremltools numpy")
    sys.exit(1)

def create_simple_segmentation_model():
    """Create a simple segmentation model for testing"""
    print("=" * 60)
    print("Quick Model Setup for EdgeTAM iOS App")
    print("=" * 60)
    print("\nThis will create a lightweight segmentation model for testing.")
    print("Note: This is NOT the actual EdgeTAM model, but a simpler alternative.")
    print()
    
    # Step 1: Load pre-trained model
    print("Step 1: Loading DeepLabV3-MobileNetV3 model...")
    print("(This may take a few minutes on first run)")
    
    try:
        model = torchvision.models.segmentation.deeplabv3_mobilenet_v3_large(
            weights=torchvision.models.segmentation.DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT
        )
        model.eval()
        print("✓ Model loaded successfully")
    except Exception as e:
        print(f"✗ Failed to load model: {e}")
        sys.exit(1)
    
    # Step 2: Create example input
    print("\nStep 2: Preparing model for conversion...")
    example_input = torch.randn(1, 3, 512, 512)
    
    # Step 3: Trace the model
    print("Step 3: Tracing model...")
    try:
        with torch.no_grad():
            traced_model = torch.jit.trace(model, example_input)
        print("✓ Model traced successfully")
    except Exception as e:
        print(f"✗ Failed to trace model: {e}")
        sys.exit(1)
    
    # Step 4: Convert to CoreML
    print("\nStep 4: Converting to CoreML format...")
    print("(This may take several minutes)")
    
    try:
        coreml_model = ct.convert(
            traced_model,
            inputs=[ct.ImageType(
                name="image",
                shape=(1, 3, 512, 512),
                scale=1.0/255.0,
                bias=[0, 0, 0]
            )],
            compute_units=ct.ComputeUnit.ALL,
            minimum_deployment_target=ct.target.iOS17,
            convert_to="mlprogram"
        )
        
        # Add metadata
        coreml_model.author = "PyTorch Team"
        coreml_model.license = "BSD"
        coreml_model.short_description = "DeepLabV3-MobileNetV3 segmentation model for testing"
        coreml_model.version = "1.0"
        
        print("✓ Conversion successful")
    except Exception as e:
        print(f"✗ Failed to convert model: {e}")
        sys.exit(1)
    
    # Step 5: Save the model
    output_path = "EdgeTAM.mlpackage"
    print(f"\nStep 5: Saving model to {output_path}...")
    
    try:
        coreml_model.save(output_path)
        print(f"✓ Model saved successfully")
    except Exception as e:
        print(f"✗ Failed to save model: {e}")
        sys.exit(1)
    
    # Step 6: Verify the model
    print("\nStep 6: Verifying model...")
    try:
        spec = coreml_model.get_spec()
        print("✓ Model verification successful")
        print(f"  - Inputs: {len(spec.description.input)}")
        print(f"  - Outputs: {len(spec.description.output)}")
        
        file_size = os.path.getsize(output_path)
        print(f"  - File size: {file_size / (1024*1024):.1f} MB")
    except Exception as e:
        print(f"✗ Verification failed: {e}")
    
    # Success message
    print("\n" + "=" * 60)
    print("✓ Setup completed successfully!")
    print("=" * 60)
    print(f"\nModel created: {output_path}")
    print(f"\nNext steps:")
    print(f"1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj in Xcode")
    print(f"2. Drag {output_path} into the project navigator")
    print(f"3. Check 'Copy items if needed'")
    print(f"4. Ensure 'EdgeTAM-iOS' target is selected")
    print(f"5. Build and run the app")
    print(f"\nNote: This is a basic segmentation model for testing.")
    print(f"For production, follow EDGETAM_CONVERSION_GUIDE.md to")
    print(f"convert the actual EdgeTAM model.")
    
    return output_path

def main():
    try:
        model_path = create_simple_segmentation_model()
        print(f"\n✓ All done! Model ready at: {model_path}")
    except KeyboardInterrupt:
        print("\n\nConversion cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
