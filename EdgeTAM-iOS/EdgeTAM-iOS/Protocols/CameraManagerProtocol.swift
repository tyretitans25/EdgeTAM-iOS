import Foundation
import AVFoundation
import CoreVideo

/// Protocol defining camera management operations for video capture
protocol CameraManagerProtocol: AnyObject, Sendable {
    /// Starts the camera capture session
    /// - Throws: EdgeTAMError if camera initialization fails
    func startSession() async throws
    
    /// Stops the camera capture session
    func stopSession()
    
    /// Switches between front and rear cameras
    /// - Throws: EdgeTAMError if camera switching fails
    func switchCamera() async throws
    
    /// Sets the video output delegate for frame processing
    /// - Parameter delegate: The delegate to receive video frames
    func setVideoOutput(delegate: AVCaptureVideoDataOutputSampleBufferDelegate)
    
    /// Indicates if the capture session is currently running
    var isRunning: Bool { get }
    
    /// The currently active camera device
    var currentDevice: AVCaptureDevice? { get }
    
    /// The current camera position (front/back)
    var currentPosition: AVCaptureDevice.Position { get }
    
    /// Delegate for camera state changes
    var delegate: CameraManagerDelegate? { get set }
}

/// Delegate protocol for camera manager events
protocol CameraManagerDelegate: AnyObject {
    /// Called when camera session starts successfully
    func cameraManagerDidStartSession(_ manager: CameraManagerProtocol)
    
    /// Called when camera session stops
    func cameraManagerDidStopSession(_ manager: CameraManagerProtocol)
    
    /// Called when camera switching is about to begin (optional)
    func cameraManagerWillSwitchCamera(_ manager: CameraManagerProtocol)
    
    /// Called when camera switching completes successfully
    func cameraManagerDidSwitchCamera(_ manager: CameraManagerProtocol)
    
    /// Called when an error occurs
    func cameraManager(_ manager: CameraManagerProtocol, didFailWithError error: EdgeTAMError)
}

// MARK: - Optional delegate methods extension
extension CameraManagerDelegate {
    func cameraManagerWillSwitchCamera(_ manager: CameraManagerProtocol) {
        // Default empty implementation for optional method
    }
}