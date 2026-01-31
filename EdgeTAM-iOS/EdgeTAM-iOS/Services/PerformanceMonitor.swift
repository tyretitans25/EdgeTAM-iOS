import Foundation
import UIKit
import os.log
import Combine

/// Implementation of performance monitoring system
@MainActor
final class PerformanceMonitor: NSObject, PerformanceMonitorProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Current frames per second
    private(set) var currentFPS: Double = 0.0
    
    /// Current memory usage in bytes
    private(set) var memoryUsage: UInt64 = 0
    
    /// Current CPU usage percentage
    private(set) var cpuUsage: Double = 0.0
    
    /// Current thermal state
    var thermalState: ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }
    
    /// Current battery level
    var batteryLevel: Float {
        return UIDevice.current.batteryLevel
    }
    
    /// Delegate for performance updates
    weak var delegate: PerformanceMonitorDelegate?
    
    /// Logger for performance monitoring
    private let logger = Logger(subsystem: "com.edgetam.ios", category: "PerformanceMonitor")
    
    /// Monitoring state
    private var isMonitoring = false
    
    /// Timer for periodic monitoring
    private var monitoringTimer: Timer?
    
    /// FPS calculation
    private var frameCount: Int = 0
    private var lastFPSUpdate: Date = Date()
    
    /// Performance metrics tracking
    private var frameDrops: Int = 0
    private var processingTimes: [TimeInterval] = []
    private var peakMemoryUsage: UInt64 = 0
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Performance thresholds
    private let memoryWarningThreshold: UInt64 = 500 * 1024 * 1024 // 500MB
    private let cpuThrottleThreshold: Double = 80.0 // 80%
    private let minAcceptableFPS: Double = 15.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupNotifications()
        logger.info("PerformanceMonitor initialized")
    }
    
    deinit {
        // Cancellables will be cleaned up automatically
        logger.info("PerformanceMonitor deinitialized")
    }
    
    // MARK: - PerformanceMonitorProtocol Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        resetMetrics()
        
        // Start periodic monitoring
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        
        logger.info("Performance monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        logger.info("Performance monitoring stopped")
    }
    
    func getPerformanceReport() -> PerformanceReport {
        let averageProcessingTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        return PerformanceReport(
            timestamp: Date(),
            fps: currentFPS,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            thermalState: thermalState,
            batteryLevel: batteryLevel,
            frameDrops: frameDrops,
            averageProcessingTime: averageProcessingTime,
            peakMemoryUsage: peakMemoryUsage
        )
    }
    
    // MARK: - Public Methods
    
    /// Record a frame for FPS calculation
    func recordFrame() {
        frameCount += 1
        
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastFPSUpdate)
        
        if timeSinceLastUpdate >= 1.0 {
            currentFPS = Double(frameCount) / timeSinceLastUpdate
            frameCount = 0
            lastFPSUpdate = now
            
            // Check for performance issues
            if currentFPS < minAcceptableFPS {
                logger.warning("Low FPS detected: \(self.currentFPS)")
            }
        }
    }
    
    /// Record a dropped frame
    func recordFrameDrop() {
        frameDrops += 1
        logger.debug("Frame drop recorded. Total drops: \(self.frameDrops)")
    }
    
    /// Record processing time for a frame
    func recordProcessingTime(_ time: TimeInterval) {
        processingTimes.append(time)
        
        // Keep only recent processing times
        if processingTimes.count > 30 {
            processingTimes.removeFirst()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Monitor battery state changes
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleBatteryStateChange()
            }
            .store(in: &cancellables)
    }
    
    private func resetMetrics() {
        frameCount = 0
        frameDrops = 0
        processingTimes.removeAll()
        peakMemoryUsage = 0
        lastFPSUpdate = Date()
        currentFPS = 0.0
    }
    
    private func updateMetrics() {
        // Update memory usage
        memoryUsage = getCurrentMemoryUsage()
        if memoryUsage > peakMemoryUsage {
            peakMemoryUsage = memoryUsage
        }
        
        // Update CPU usage
        cpuUsage = getCurrentCPUUsage()
        
        // Create performance metrics
        let memoryPressureValue = Float(Double(memoryUsage) / Double(memoryWarningThreshold))
        let cpuUsageValue = Float(cpuUsage)
        let metrics = PerformanceMetrics(
            currentFPS: currentFPS,
            averageInferenceTime: processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count),
            memoryPressure: memoryPressureValue,
            thermalState: thermalState,
            cpuUsage: cpuUsageValue,
            gpuUsage: 0.0, // GPU usage monitoring would require Metal performance shaders
            batteryDrain: 0.0, // Battery drain calculation would require historical data
            timestamp: Date()
        )
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.performanceMonitor(self, didUpdateMetrics: metrics)
        }
        
        // Check for performance issues
        checkPerformanceThresholds()
    }
    
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            logger.error("Failed to get memory usage")
            return 0
        }
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info: processor_info_array_t? = nil
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &numCpus,
                                       &info,
                                       &numCpuInfo)
        
        guard result == KERN_SUCCESS else {
            logger.error("Failed to get CPU usage")
            return 0.0
        }
        
        // Simplified CPU usage calculation
        // In a real implementation, this would track CPU ticks over time
        if let info = info {
            info.deallocate()
        }
        return 0.0 // Placeholder - actual CPU monitoring requires more complex implementation
    }
    
    private func checkPerformanceThresholds() {
        // Check memory pressure
        if memoryUsage > memoryWarningThreshold {
            logger.warning("High memory usage detected: \(self.memoryUsage) bytes")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.performanceMonitor(self, didDetectMemoryPressure: self.memoryUsage)
            }
        }
        
        // Check CPU usage
        if cpuUsage > cpuThrottleThreshold {
            logger.warning("High CPU usage detected: \(self.cpuUsage)%")
        }
        
        // Check thermal state
        if thermalState != .nominal {
            logger.warning("Thermal throttling detected: \(self.thermalState.rawValue)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.performanceMonitor(self, didDetectThermalThrottling: self.thermalState)
            }
        }
    }
    
    private func handleThermalStateChange() {
        let state = thermalState
        logger.info("Thermal state changed to: \(state.rawValue)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.performanceMonitor(self, didDetectThermalThrottling: state)
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("Memory warning received")
        
        // Clear processing history to free memory
        processingTimes.removeAll()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.performanceMonitor(self, didDetectMemoryPressure: self.memoryUsage)
        }
    }
    
    private func handleBatteryStateChange() {
        let level = batteryLevel
        logger.debug("Battery level changed to: \(level)")
        
        // Implement battery-based performance adjustments if needed
        if level < 0.2 && level > 0.0 { // Below 20% and not unknown
            logger.info("Low battery detected, consider reducing performance")
        }
    }
}

// MARK: - Extensions

