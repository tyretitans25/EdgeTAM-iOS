//
//  TorchBridge.h
//  EdgeTAM-iOS
//
//  PyTorch Mobile bridge for EdgeTAM model inference
//  This Objective-C++ header provides the interface between Swift and PyTorch C++ API
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Result of model inference containing masks and confidence scores
@interface TorchInferenceResult : NSObject

/// Segmentation mask as pixel buffer (grayscale, 0-255)
/// Note: Using CF_RETURNS_RETAINED to indicate ownership transfer
@property (nonatomic, assign) CVPixelBufferRef _Nullable maskBuffer CF_RETURNS_NOT_RETAINED;

/// Confidence score (0.0 - 1.0)
@property (nonatomic, assign) float confidence;

/// Inference time in seconds
@property (nonatomic, assign) double inferenceTime;

@end

/// PyTorch model wrapper for EdgeTAM
@interface TorchModule : NSObject

/// Initialize with model file path
/// @param modelPath Path to the TorchScript model file (.pt)
/// @return Initialized TorchModule instance or nil if loading fails
- (nullable instancetype)initWithModelPath:(NSString *)modelPath;

/// Load the model from file
/// @param error Error pointer for failure information
/// @return YES if successful, NO otherwise
- (BOOL)loadModelWithError:(NSError **)error;

/// Check if model is loaded
@property (nonatomic, readonly) BOOL isLoaded;

/// Perform inference on an image with point prompts
/// @param pixelBuffer Input image as CVPixelBuffer (RGB, 1024x1024)
/// @param pointCoordinates Array of CGPoint values (normalized 0-1)
/// @param pointLabels Array of NSNumber (1 for foreground, 0 for background)
/// @param error Error pointer for failure information
/// @return TorchInferenceResult or nil if inference fails
- (nullable TorchInferenceResult *)predictWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         pointCoordinates:(NSArray<NSValue *> *)pointCoordinates
                                              pointLabels:(NSArray<NSNumber *> *)pointLabels
                                                    error:(NSError **)error;

/// Get model memory usage in bytes
@property (nonatomic, readonly) NSUInteger memoryUsage;

/// Unload the model from memory
- (void)unloadModel;

@end

NS_ASSUME_NONNULL_END
