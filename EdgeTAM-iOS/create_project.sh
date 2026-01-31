#!/bin/bash

# Create a new iOS project using Xcode's template
# This script should be run from the EdgeTAM-iOS directory

echo "Creating new EdgeTAM iOS project..."

# Remove any existing project files
rm -rf EdgeTAM-iOS.xcodeproj

# Create the project using xcodegen if available, or manually
if command -v xcodegen &> /dev/null; then
    echo "Using xcodegen to create project..."
    
    # Create project.yml for xcodegen
    cat > project.yml << EOF
name: EdgeTAM-iOS
options:
  bundleIdPrefix: com.edgetam
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: en
  
targets:
  EdgeTAM-iOS:
    type: application
    platform: iOS
    sources:
      - EdgeTAM-iOS
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.edgetam.EdgeTAM-iOS
      INFOPLIST_KEY_NSCameraUsageDescription: "EdgeTAM requires camera access for real-time video segmentation and object tracking."
      INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "EdgeTAM needs photo library access to save processed videos with segmentation masks."
      SWIFT_VERSION: "6.0"
      TARGETED_DEVICE_FAMILY: "1,2"
      ENABLE_PREVIEWS: YES
      DEVELOPMENT_ASSET_PATHS: "EdgeTAM-iOS/Preview Content"
    dependencies:
      - framework: SwiftUI.framework
      - framework: AVFoundation.framework
      - framework: CoreML.framework
      - framework: Metal.framework
      - framework: MetalKit.framework
      - framework: CoreImage.framework
      - framework: Vision.framework
      - framework: Combine.framework
        
  EdgeTAM-iOSTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - EdgeTAM-iOSTests
    dependencies:
      - target: EdgeTAM-iOS
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.edgetam.EdgeTAM-iOSTests
      SWIFT_VERSION: "6.0"
      TARGETED_DEVICE_FAMILY: "1,2"
EOF

    # Generate the project
    xcodegen generate
    
    # Clean up
    rm project.yml
    
else
    echo "xcodegen not found. Please install it with: brew install xcodegen"
    echo "Or create the project manually in Xcode."
fi

echo "Project creation completed!"