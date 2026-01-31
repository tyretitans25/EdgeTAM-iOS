import Foundation
import UIKit

/// Protocol for performance monitoring and system resource tracking
@MainActor
protocol PerformanceMonitorProtocol: AnyObject, Sendable {
    /// Current frames per second
    var currentFPS: Double { get }
    
    /// Current memory usage in bytes
    var memoryUsage: UInt64 { get }
    
    /// Current CPU usage percentage
    var cpuUsage: Double { get }
    
    /// Current thermal state
    var thermalState: ProcessInfo.ThermalState { get }
    
    /// Current battery level (0.0 to 1.0)
    var batteryLevel: Float { get }
    
    /// Delegate for performance updates
    var delegate: PerformanceMonitorDelegate? { get set }
    
    /// Start performance monitoring
    func startMonitoring()
    
    /// Stop performance monitoring
    func stopMonitoring()
    
    /// Get comprehensive performance report
    func getPerformanceReport() -> PerformanceReport
    
    /// Record a frame for FPS calculation
    func recordFrame()
    
    /// Record a dropped frame
    func recordFrameDrop()
    
    /// Record processing time for a frame
    func recordProcessingTime(_ time: TimeInterval)
}

/// Performance monitoring delegate for receiving performance updates
protocol PerformanceMonitorDelegate: AnyObject {
    /// Called when performance metrics are updated
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didUpdateMetrics metrics: PerformanceMetrics)
    
    /// Called when thermal throttling is detected
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectThermalThrottling state: ProcessInfo.ThermalState)
    
    /// Called when memory pressure is detected
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectMemoryPressure usage: UInt64)
}

/// Comprehensive performance report
struct PerformanceReport: Codable, Sendable {
    let timestamp: Date
    let fps: Double
    let memoryUsage: UInt64
    let cpuUsage: Double
    let thermalState: Int
    let batteryLevel: Float
    let frameDrops: Int
    let averageProcessingTime: TimeInterval
    let peakMemoryUsage: UInt64
    
    init(timestamp: Date = Date(),
         fps: Double,
         memoryUsage: UInt64,
         cpuUsage: Double,
         thermalState: ProcessInfo.ThermalState,
         batteryLevel: Float,
         frameDrops: Int,
         averageProcessingTime: TimeInterval,
         peakMemoryUsage: UInt64) {
        self.timestamp = timestamp
        self.fps = fps
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.thermalState = thermalState.rawValue
        self.batteryLevel = batteryLevel
        self.frameDrops = frameDrops
        self.averageProcessingTime = averageProcessingTime
        self.peakMemoryUsage = peakMemoryUsage
    }
}