#!/usr/bin/env python3
"""
Create a simple CoreML model for EdgeTAM iOS app testing

This creates a minimal working model that the app can load successfully.
"""

import torch
import torch.nn as nn
import coremltools as ct
import os

class SimpleSegmentationModel(nn.Module):
    """
    A simple segmentation model that can be converted to CoreML.
    This is a placeholder that allows the app to run and test the UI.
    """
    def __init__(self):
        super().__init__()
        # Simple convolutional layers
        self.conv1 = nn.Conv2d(3, 64, kernel_size=3, padding=1)
        self.relu1 = nn.ReLU()
        self.conv2 = nn.Conv2d(64, 64, kernel_size=3, padding=1)
        self.relu2 = nn.ReLU()
        self.conv3 = nn.Conv2d(64, 1, kernel_size=1)
        self.sigmoid = nn.Sigmoid()
        
    def forward(self, x):
        x = self.relu1(self.conv1(x))
        x = self.relu2(self.conv2(x))
        x = self.sigmoid(self.conv3(x))
        return x

def create_model():
    """Create and convert the model"""
    print("=" * 60)
    print("Creating Simple Segmentation Model for EdgeTAM iOS")
    print("=" * 60)
    print()
    
    print("Step 1: Creating model...")
    model = SimpleSegmentationModel()
    model.eval()
    print("✓ Model created")
    
    print("\nStep 2: Tracing model...")
    example_input = torch.randn(1, 3, 512, 512)
    with torch.no_grad():
        traced_model = torch.jit.trace(model, example_input)
    print("✓ Model traced")
    
    print("\nStep 3: Converting to CoreML...")
    print("(This may take a minute)")
    
    coreml_model = ct.convert(
        traced_model,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, 512, 512),
            scale=1.0/255.0,
            bias=[0, 0, 0]
        )],
        outputs=[ct.TensorType(name="output")],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram"
    )
    
    # Add metadata
    coreml_model.author = "EdgeTAM Team"
    coreml_model.license = "Apache 2.0"
    coreml_model.short_description = "Simple segmentation model for EdgeTAM iOS testing"
    coreml_model.version = "1.0"
    
    print("✓ Conversion successful")
    
    print("\nStep 4: Saving model...")
    output_path = "EdgeTAM-iOS/EdgeTAM-iOS/EdgeTAM.mlpackage"
    coreml_model.save(output_path)
    print(f"✓ Model saved to: {output_path}")
    
    # Get file size
    total_size = 0
    for root, dirs, files in os.walk(output_path):
        for file in files:
            total_size += os.path.getsize(os.path.join(root, file))
    print(f"  Size: {total_size / (1024*1024):.1f} MB")
    
    print("\n" + "=" * 60)
    print("✓ Model creation completed successfully!")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Open EdgeTAM-iOS/EdgeTAM-iOS.xcodeproj in Xcode")
    print("2. Add EdgeTAM.mlpackage to the project:")
    print("   - Right-click 'EdgeTAM-iOS' folder")
    print("   - Select 'Add Files to EdgeTAM-iOS...'")
    print("   - Navigate to EdgeTAM-iOS/EdgeTAM-iOS/")
    print("   - Select 'EdgeTAM.mlpackage'")
    print("   - Check 'Copy items if needed'")
    print("   - Ensure 'EdgeTAM-iOS' target is selected")
    print("   - Click 'Add'")
    print("3. Build and run the app (⌘R)")
    print()
    print("Note: This is a simple test model.")
    print("For production, you'll need to implement proper EdgeTAM conversion.")
    print()

if __name__ == "__main__":
    try:
        create_model()
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
