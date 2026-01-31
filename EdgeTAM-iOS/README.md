# EdgeTAM iOS Application

A real-time video segmentation and object tracking iOS application that integrates Meta's EdgeTAM (Track Anything Model) with Apple's CoreML framework.

## Project Structure

```
EdgeTAM-iOS/
├── EdgeTAM-iOS.xcodeproj/          # Xcode project file
└── EdgeTAM-iOS/                    # Main application source
    ├── EdgeTAM_iOSApp.swift        # App entry point with dependency injection
    ├── ContentView.swift           # Main SwiftUI view
    ├── Protocols/                  # Protocol definitions for all major components
    │   ├── CameraManagerProtocol.swift
    │   ├── ModelManagerProtocol.swift
    │   ├── VideoSegmentationEngineProtocol.swift
    │   ├── ObjectTrackerProtocol.swift
    │   ├── PromptHandlerProtocol.swift
    │   └── MaskRendererProtocol.swift
    ├── Models/                     # Data models and types
    │   ├── DataModels.swift        # Core data structures
    │   └── ErrorTypes.swift        # Comprehensive error handling
    ├── Core/                       # Core infrastructure
    │   └── DependencyContainer.swift # Dependency injection container
    ├── Assets.xcassets/            # App assets and resources
    └── Preview Content/            # SwiftUI preview assets
```

## Architecture

The application follows a layered architecture with clear separation of concerns:

- **User Interface Layer**: SwiftUI views for camera preview, controls, and overlays
- **View Model Layer**: MVVM pattern implementation with Combine for reactive updates
- **Service Layer**: Business logic coordination and state management
- **Machine Learning Layer**: CoreML model management and inference pipeline
- **AVFoundation Layer**: Low-level video capture and processing

## Key Features

- Real-time video capture and processing at 15+ FPS
- Interactive object selection via point taps and bounding boxes
- Object tracking across video frames with temporal consistency
- GPU-accelerated mask rendering with customizable opacity
- On-device CoreML inference with Neural Engine optimization
- Comprehensive error handling and recovery mechanisms
- Dependency injection for testable and maintainable code

## Requirements

- iOS 17.0 or later
- iPhone 15 Pro Max or similar device with Neural Engine
- Camera and Photo Library permissions

## Frameworks Used

- **SwiftUI**: Modern declarative UI framework
- **AVFoundation**: Video capture and processing
- **CoreML**: On-device machine learning inference
- **Metal**: GPU-accelerated rendering
- **Combine**: Reactive programming and data binding

## Development Status

This is the initial project structure with core protocols and dependency injection setup. Subsequent tasks will implement:

1. Camera management and video capture pipeline
2. EdgeTAM CoreML model integration
3. Video segmentation engine
4. Object tracking system
5. Mask rendering with Metal
6. SwiftUI user interface
7. Export functionality
8. Performance monitoring
9. Privacy and security features

## Testing Strategy

The application employs a dual testing approach:
- **Unit Tests**: Specific examples, edge cases, and error conditions
- **Property-Based Tests**: Universal correctness validation across randomized inputs
- **Integration Tests**: End-to-end workflow verification
- **Performance Tests**: Frame rate, memory usage, and thermal behavior validation

## Privacy

All video processing is performed on-device using CoreML. No data is sent to external servers, ensuring complete user privacy and enabling offline functionality.