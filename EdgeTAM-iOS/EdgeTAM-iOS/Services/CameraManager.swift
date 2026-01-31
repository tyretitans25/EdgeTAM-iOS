import Foundation
@preconcurrency import AVFoundation
import CoreVideo
import UIKit

/// Implementation of camera management operations for video capture
final class CameraManager: NSObject, CameraManagerProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "camera.output.queue", qos: .userInitiated)
    
    private var videoInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    
    // MARK: - CameraManagerProtocol Properties
    
    weak var delegate: CameraManagerDelegate?
    
    var isRunning: Bool {
        return captureSession.isRunning
    }
    
    var currentDevice: AVCaptureDevice? {
        return videoInput?.device
    }
    
    var currentPosition: AVCaptureDevice.Position {
        return currentCameraPosition
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        configureSession()
        setupSessionInterruptionHandling()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopSession()
    }
    
    // MARK: - CameraManagerProtocol Methods
    
    func startSession() async throws {
        // Check camera permissions first
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw EdgeTAMError.cameraPermissionDenied
            }
        case .denied, .restricted:
            throw EdgeTAMError.cameraPermissionDenied
        case .authorized:
            break
        @unknown default:
            throw EdgeTAMError.cameraPermissionDenied
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.cameraInitializationFailed("Camera manager deallocated"))
                    return
                }
                
                do {
                    try self.setupCameraInput()
                    self.captureSession.startRunning()
                    
                    DispatchQueue.main.async {
                        self.delegate?.cameraManagerDidStartSession(self)
                    }
                    
                    continuation.resume()
                } catch {
                    let cameraError = EdgeTAMError.from(error)
                    DispatchQueue.main.async {
                        self.delegate?.cameraManager(self, didFailWithError: cameraError)
                    }
                    continuation.resume(throwing: cameraError)
                }
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                
                DispatchQueue.main.async {
                    self.delegate?.cameraManagerDidStopSession(self)
                }
            }
        }
    }
    
    func switchCamera() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: EdgeTAMError.cameraSwitchingFailed("Camera manager deallocated"))
                    return
                }
                
                // Ensure session is running before attempting switch
                guard self.captureSession.isRunning else {
                    continuation.resume(throwing: EdgeTAMError.cameraSwitchingFailed("Camera session is not running"))
                    return
                }
                
                do {
                    // Notify delegate that camera switching is starting
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.cameraManagerWillSwitchCamera(self)
                    }
                    
                    // Determine the new camera position
                    let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .back ? .front : .back
                    
                    // Get the new camera device
                    guard let newDevice = self.getCameraDevice(for: newPosition) else {
                        throw EdgeTAMError.cameraDeviceNotAvailable
                    }
                    
                    // Create new input
                    let newInput = try AVCaptureDeviceInput(device: newDevice)
                    
                    // Store current input for rollback if needed
                    let previousInput = self.videoInput
                    let previousPosition = self.currentCameraPosition
                    
                    // Begin configuration - this pauses the session briefly
                    self.captureSession.beginConfiguration()
                    
                    // Remove old input
                    if let currentInput = self.videoInput {
                        self.captureSession.removeInput(currentInput)
                    }
                    
                    // Add new input
                    if self.captureSession.canAddInput(newInput) {
                        self.captureSession.addInput(newInput)
                        self.videoInput = newInput
                        self.currentCameraPosition = newPosition
                        
                        // Configure device settings for optimal performance
                        try self.configureDeviceSettings(newDevice)
                        
                        // Update video output connection settings for new camera
                        self.updateVideoOutputConnection()
                        
                    } else {
                        // Restore previous input if new one can't be added
                        if let previousInput = previousInput,
                           self.captureSession.canAddInput(previousInput) {
                            self.captureSession.addInput(previousInput)
                            self.videoInput = previousInput
                            self.currentCameraPosition = previousPosition
                        }
                        throw EdgeTAMError.cameraSwitchingFailed("Cannot add new camera input")
                    }
                    
                    // Commit configuration - this resumes the session
                    self.captureSession.commitConfiguration()
                    
                    // Notify delegate that camera switching completed successfully
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.cameraManagerDidSwitchCamera(self)
                    }
                    
                    continuation.resume()
                    
                } catch {
                    // Ensure configuration is committed even on error
                    self.captureSession.commitConfiguration()
                    
                    let cameraError = EdgeTAMError.from(error)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.cameraManager(self, didFailWithError: cameraError)
                    }
                    continuation.resume(throwing: cameraError)
                }
            }
        }
    }
    
    func setVideoOutput(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.videoOutput.setSampleBufferDelegate(delegate, queue: self.outputQueue)
        }
    }
    
    // MARK: - Private Methods
    
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Configure session preset for high quality video
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            } else if self.captureSession.canSetSessionPreset(.medium) {
                self.captureSession.sessionPreset = .medium
            }
            
            // Configure video output
            self.configureVideoOutput()
        }
    }
    
    private func configureVideoOutput() {
        // Set video settings for optimal CoreML processing
        let videoSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        videoOutput.videoSettings = videoSettings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Add video output to session
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            updateVideoOutputConnection()
        }
    }
    
    private func updateVideoOutputConnection() {
        // Configure video orientation and mirroring for current camera
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            
            // Mirror front camera output, don't mirror rear camera
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (currentCameraPosition == .front)
            }
            
            // Enable video stabilization if available
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
    }
    
    private func setupCameraInput() throws {
        guard let device = getCameraDevice(for: currentCameraPosition) else {
            throw EdgeTAMError.cameraDeviceNotAvailable
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            captureSession.beginConfiguration()
            
            // Remove existing input if any
            if let existingInput = videoInput {
                captureSession.removeInput(existingInput)
            }
            
            // Add new input
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
                
                // Configure device settings for optimal performance
                try configureDeviceSettings(device)
            } else {
                throw EdgeTAMError.cameraInitializationFailed("Cannot add camera input to session")
            }
            
            captureSession.commitConfiguration()
            
        } catch let error as EdgeTAMError {
            captureSession.commitConfiguration()
            throw error
        } catch {
            captureSession.commitConfiguration()
            throw EdgeTAMError.cameraInitializationFailed(error.localizedDescription)
        }
    }
    
    private func getCameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Try to get the best available camera for the position
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        
        return discoverySession.devices.first
    }
    
    private func configureDeviceSettings(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Set focus mode for better tracking
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        
        // Set exposure mode
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        
        // Set white balance mode
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        
        // Enable video stabilization if available
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        
        // Set frame rate for optimal performance (targeting 30fps for smooth processing)
        let targetFrameRate: Double = 30
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
            range.minFrameRate <= targetFrameRate && range.maxFrameRate >= targetFrameRate
        }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        }
    }
}

// MARK: - Session Interruption Handling

extension CameraManager {
    
    func setupSessionInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
    }
    
    @MainActor
    @objc private func sessionWasInterrupted(notification: NSNotification) {
        guard let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
              let reasonIntegerValue = userInfoValue.integerValue,
              let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) else {
            return
        }
        
        DispatchQueue.main.async {
            switch reason {
            case .videoDeviceNotAvailableInBackground:
                // App moved to background, session will automatically stop
                break
            case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
                self.delegate?.cameraManager(self, didFailWithError: .cameraSessionInterrupted)
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                self.delegate?.cameraManager(self, didFailWithError: .cameraDeviceNotAvailable)
            case .videoDeviceNotAvailableDueToSystemPressure:
                self.delegate?.cameraManager(self, didFailWithError: .thermalThrottling)
            case .sensitiveContentMitigationActivated:
                self.delegate?.cameraManager(self, didFailWithError: .cameraSessionInterrupted)
            @unknown default:
                self.delegate?.cameraManager(self, didFailWithError: .cameraSessionInterrupted)
            }
        }
    }
    
    @MainActor
    @objc private func sessionInterruptionEnded(notification: NSNotification) {
        // Session will automatically resume, notify delegate
        self.delegate?.cameraManagerDidStartSession(self)
    }
    
    @MainActor
    @objc private func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            return
        }
        
        let edgeTAMError: EdgeTAMError
        switch error.code {
        case .deviceAlreadyUsedByAnotherSession:
            edgeTAMError = .cameraDeviceNotAvailable
        case .mediaServicesWereReset:
            edgeTAMError = .cameraSessionInterrupted
        default:
            edgeTAMError = .cameraInitializationFailed(error.localizedDescription)
        }
        
        self.delegate?.cameraManager(self, didFailWithError: edgeTAMError)
    }
}