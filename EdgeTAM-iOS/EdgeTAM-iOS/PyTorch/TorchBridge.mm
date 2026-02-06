//
//  TorchBridge.mm
//  EdgeTAM-iOS
//
//  PyTorch Mobile bridge implementation
//  This Objective-C++ file bridges Swift/Objective-C to PyTorch C++ API
//

#import "TorchBridge.h"
#import <LibTorch/LibTorch.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Accelerate/Accelerate.h>
#import <UIKit/UIKit.h>

// MARK: - TorchInferenceResult Implementation

@implementation TorchInferenceResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _maskBuffer = NULL;
        _confidence = 0.0f;
        _inferenceTime = 0.0;
    }
    return self;
}

- (void)dealloc {
    // Don't release maskBuffer here - ownership is transferred to Swift
    // Swift's ARC will manage the CVPixelBuffer lifecycle automatically
    _maskBuffer = NULL;
}

@end

// MARK: - TorchModule Implementation

@interface TorchModule ()
@property (nonatomic, strong) NSString *modelPath;
@property (nonatomic, assign) torch::jit::script::Module *module;
@property (nonatomic, assign) BOOL loaded;
@property (nonatomic, strong) NSLock *inferenceLock;  // Thread safety for inference
@end

@implementation TorchModule

- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        _modelPath = modelPath;
        _module = nullptr;
        _loaded = NO;
        _inferenceLock = [[NSLock alloc] init];
        _inferenceLock.name = @"com.edgetam.torch.inference";
    }
    return self;
}

- (void)dealloc {
    [self unloadModel];
}

- (BOOL)loadModelWithError:(NSError **)error {
    @try {
        NSLog(@"[TorchBridge] Loading model from: %@", self.modelPath);
        
        // Check if file exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.modelPath]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.edgetam.torch"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Model file not found"}];
            }
            return NO;
        }
        
        // Load the model
        auto module = new torch::jit::script::Module();
        *module = torch::jit::load([self.modelPath UTF8String]);
        module->eval();
        
        self.module = module;
        self.loaded = YES;
        
        NSLog(@"[TorchBridge] Model loaded successfully");
        return YES;
        
    } @catch (NSException *exception) {
        NSLog(@"[TorchBridge] Failed to load model: %@", exception.reason);
        if (error) {
            *error = [NSError errorWithDomain:@"com.edgetam.torch"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        }
        return NO;
    }
}

- (BOOL)isLoaded {
    return self.loaded && self.module != nullptr;
}

- (nullable TorchInferenceResult *)predictWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         pointCoordinates:(NSArray<NSValue *> *)pointCoordinates
                                              pointLabels:(NSArray<NSNumber *> *)pointLabels
                                                    error:(NSError **)error {
    if (!self.isLoaded) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.edgetam.torch"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        }
        return nil;
    }
    
    // CRITICAL: Lock to prevent concurrent inference calls
    // PyTorch models are NOT thread-safe for inference
    [self.inferenceLock lock];
    
    @autoreleasepool {
        @try {
            NSDate *startTime = [NSDate date];
            
            NSLog(@"[TorchBridge] Starting inference with %lu points", (unsigned long)pointCoordinates.count);
            
            // Convert pixel buffer to tensor
            torch::Tensor imageTensor = [self pixelBufferToTensor:pixelBuffer];
            
            // Convert point coordinates to tensor
            torch::Tensor coordsTensor = [self pointCoordinatesToTensor:pointCoordinates];
            
            // Convert point labels to tensor
            torch::Tensor labelsTensor = [self pointLabelsToTensor:pointLabels];
            
            // Prepare inputs
            std::vector<torch::jit::IValue> inputs;
            inputs.push_back(imageTensor);
            inputs.push_back(coordsTensor);
            inputs.push_back(labelsTensor);
            
            // Run inference
            auto output = self.module->forward(inputs).toTuple();
            
            // Extract masks and scores
            torch::Tensor masksTensor = output->elements()[0].toTensor();
            torch::Tensor scoresTensor = output->elements()[1].toTensor();
            
            // Convert mask tensor to pixel buffer
            CVPixelBufferRef maskBuffer = [self tensorToPixelBuffer:masksTensor];
            
            if (!maskBuffer) {
                NSLog(@"[TorchBridge] ERROR: Failed to create mask buffer");
                if (error) {
                    *error = [NSError errorWithDomain:@"com.edgetam.torch"
                                                 code:500
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to create mask buffer"}];
                }
                return nil;
            }
            
            // Extract confidence score
            float confidence = scoresTensor[0][0].item<float>();
            
            // Calculate inference time
            NSTimeInterval inferenceTime = [[NSDate date] timeIntervalSinceDate:startTime];
            
            // Create result
            TorchInferenceResult *result = [[TorchInferenceResult alloc] init];
            
            // Transfer ownership - result will release in dealloc
            // tensorToPixelBuffer created it with retain count = 1
            // We're transferring that +1 to the result object
            result.maskBuffer = maskBuffer;  // Property access, no custom setter so no retain
            result.confidence = confidence;
            result.inferenceTime = inferenceTime;
            
            NSLog(@"[TorchBridge] Inference completed in %.3fs (confidence: %.3f), buffer=%p", inferenceTime, confidence, maskBuffer);
            
            [self.inferenceLock unlock];
            return result;
            
        } @catch (NSException *exception) {
            NSLog(@"[TorchBridge] Inference failed: %@", exception.reason);
            if (error) {
                *error = [NSError errorWithDomain:@"com.edgetam.torch"
                                             code:500
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Inference failed"}];
            }
            [self.inferenceLock unlock];
            return nil;
        }
    }
}

- (NSUInteger)memoryUsage {
    // Estimate memory usage (simplified)
    // In production, this should track actual tensor memory
    return self.isLoaded ? 300 * 1024 * 1024 : 0; // ~300 MB estimate
}

- (void)unloadModel {
    if (self.module != nullptr) {
        delete self.module;
        self.module = nullptr;
    }
    self.loaded = NO;
    NSLog(@"[TorchBridge] Model unloaded");
}

// MARK: - Tensor Conversion Utilities

- (torch::Tensor)pixelBufferToTensor:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        NSLog(@"[TorchBridge] ERROR: pixelBuffer is NULL");
        return torch::zeros({1, 3, 1, 1});
    }
    
    // Lock the pixel buffer for reading (caller owns the buffer, we just borrow it)
    CVReturn lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockResult != kCVReturnSuccess) {
        NSLog(@"[TorchBridge] ERROR: Failed to lock pixel buffer: %d", lockResult);
        return torch::zeros({1, 3, 1, 1});
    }
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    if (!baseAddress) {
        NSLog(@"[TorchBridge] ERROR: baseAddress is NULL");
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return torch::zeros({1, 3, 1, 1});
    }
    
    // Create tensor with shape [1, 3, height, width]
    torch::Tensor tensor = torch::zeros({1, 3, (long)height, (long)width});
    
    // Copy pixel data to tensor
    // Assuming BGRA format, convert to RGB and normalize to [0, 1]
    auto tensorAccessor = tensor.accessor<float, 4>();
    
    for (size_t y = 0; y < height; y++) {
        uint8_t *row = (uint8_t *)baseAddress + y * bytesPerRow;
        for (size_t x = 0; x < width; x++) {
            uint8_t *pixel = row + x * 4; // BGRA
            
            // Convert BGRA to RGB and normalize
            tensorAccessor[0][0][y][x] = pixel[2] / 255.0f; // R
            tensorAccessor[0][1][y][x] = pixel[1] / 255.0f; // G
            tensorAccessor[0][2][y][x] = pixel[0] / 255.0f; // B
        }
    }
    
    // Unlock the buffer (caller still owns it)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return tensor;
}

- (torch::Tensor)pointCoordinatesToTensor:(NSArray<NSValue *> *)coordinates {
    if (!coordinates || coordinates.count == 0) {
        NSLog(@"[TorchBridge] ERROR: coordinates array is nil or empty");
        return torch::zeros({1, 1, 2});
    }
    
    size_t numPoints = coordinates.count;
    NSLog(@"[TorchBridge] Converting %zu point coordinates to tensor", numPoints);
    
    // Create tensor with shape [1, numPoints, 2]
    torch::Tensor tensor = torch::zeros({1, (long)numPoints, 2});
    auto accessor = tensor.accessor<float, 3>();
    
    for (size_t i = 0; i < numPoints; i++) {
        @autoreleasepool {
            NSValue *value = coordinates[i];
            if (!value) {
                NSLog(@"[TorchBridge] ERROR: NSValue at index %zu is nil", i);
                continue;
            }
            
            // Use CGPointValue which is the proper way to extract CGPoint from NSValue
            CGPoint point = [value CGPointValue];
            
            NSLog(@"[TorchBridge] Point %zu: (%.2f, %.2f)", i, point.x, point.y);
            
            accessor[0][i][0] = point.x;
            accessor[0][i][1] = point.y;
        }
    }
    
    return tensor;
}

- (torch::Tensor)pointLabelsToTensor:(NSArray<NSNumber *> *)labels {
    size_t numLabels = labels.count;
    
    // Create tensor with shape [1, numLabels]
    torch::Tensor tensor = torch::zeros({1, (long)numLabels});
    auto accessor = tensor.accessor<float, 2>();
    
    for (size_t i = 0; i < numLabels; i++) {
        accessor[0][i] = [labels[i] floatValue];
    }
    
    return tensor;
}

- (CVPixelBufferRef)tensorToPixelBuffer:(torch::Tensor)tensor {
    // Assume tensor shape is [1, 1, height, width]
    // Values are in range [0, 1] or [-inf, inf] (logits)
    
    NSLog(@"[TorchBridge] Converting tensor to pixel buffer, shape: [%ld, %ld, %ld, %ld]", 
          tensor.size(0), tensor.size(1), tensor.size(2), tensor.size(3));
    
    // Apply sigmoid if needed (convert logits to probabilities)
    tensor = torch::sigmoid(tensor);
    
    // Get dimensions
    long height = tensor.size(2);
    long width = tensor.size(3);
    
    // Create pixel buffer (grayscale)
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *options = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferMetalCompatibilityKey: @YES
    };
    
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_OneComponent8,
                                         (__bridge CFDictionaryRef)options,
                                         &pixelBuffer);
    
    if (result != kCVReturnSuccess || !pixelBuffer) {
        NSLog(@"[TorchBridge] ERROR: Failed to create pixel buffer: %d", result);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    // Copy tensor data to pixel buffer
    auto accessor = tensor.accessor<float, 4>();
    
    for (long y = 0; y < height; y++) {
        uint8_t *row = baseAddress + y * bytesPerRow;
        for (long x = 0; x < width; x++) {
            float value = accessor[0][0][y][x];
            // Clamp to [0, 1] and convert to [0, 255]
            value = std::max(0.0f, std::min(1.0f, value));
            row[x] = (uint8_t)(value * 255.0f);
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    NSLog(@"[TorchBridge] Pixel buffer created successfully: %ldx%ld (retain count will be managed by caller)", width, height);
    
    // Return with +1 retain count (caller takes ownership)
    return pixelBuffer;
}

@end
