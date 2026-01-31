import XCTest
import CoreVideo
@testable import EdgeTAM_iOS

final class PerformanceMonitorTests: XCTestCase {
    
    var performanceMonitor: PerformanceMonitor!
    var mockDelegate: MockPerformanceMonitorDelegate!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create performance monitor with test configuration
        let configuration = PerformanceConfiguration(
            targetFPS: 15.0,
            memoryPressureThreshold: 0.8,
            cpuUsageThreshold: 0.8,
            thermalThrottlingThreshold: .serious,
            updateInterval: 0.1, // Faster updates for testing
            maxFPSSamples: 10,
            maxInferenceSamples: 20,
            automaticOptimizationEnabled: false, // Disable for controlled testing
            diagnosticsEnabled: true
        )
        
        performanceMonitor = PerformanceMonitor(configuration: configuration)
        mockDelegate = MockPerformanceMonitorDelegate()
        performanceMonitor.delegate = mockDelegate
    }
    
    override func tearDownWithError() throws {
        performanceMonitor.stopMonitoring()
        performanceMonitor = nil
        mockDelegate = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Initialization Tests
    
    func testPerformanceMonitorInitialization() {
        XCTAssertNotNil(performanceMonitor)
        XCTAssertFalse(performanceMonitor.isMonitoring)
        XCTAssertEqual(performanceMonitor.currentFPS, 0)
        XCTAssertEqual(performanceMonitor.memoryPressure, 0)
        XCTAssertEqual(performanceMonitor.cpuUsage, 0)
        XCTAssertEqual(performanceMonitor.configuration.targetFPS, 15.0)
    }
    
    func testConfigurationUpdate() {
        let newConfiguration = PerformanceConfiguration(
            targetFPS: 30.0,
            memoryPressureThreshold: 0.9,
            automaticOptimizationEnabled: true
        )
        
        performanceMonitor.configuration = newConfiguration
        
        XCTAssertEqual(performanceMonitor.configuration.targetFPS, 30.0)
        XCTAssertEqual(performanceMonitor.configuration.memoryPressureThreshold, 0.9)
        XCTAssertTrue(performanceMonitor.configuration.automaticOptimizationEnabled)
    }
    
    // MARK: - Monitoring Lifecycle Tests
    
    func testStartMonitoring() async {
        XCTAssertFalse(performanceMonitor.isMonitoring)
        
        do {
            try await performanceMonitor.startMonitoring()
            XCTAssertTrue(performanceMonitor.isMonitoring)
            XCTAssertTrue(mockDelegate.didStartMonitoringCalled)
        } catch {
            XCTFail("Failed to start monitoring: \(error)")
        }
    }
    
    func testStopMonitoring() async {
        // Start monitoring first
        do {
            try await performanceMonitor.startMonitoring()
            XCTAssertTrue(performanceMonitor.isMonitoring)
            
            // Stop monitoring
            performanceMonitor.stopMonitoring()
            
            // Give it a moment to process
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            XCTAssertFalse(performanceMonitor.isMonitoring)
            XCTAssertTrue(mockDelegate.didStopMonitoringCalled)
        } catch {
            XCTFail("Failed during monitoring lifecycle: \(error)")
        }
    }
    
    func testStartMonitoringTwice() async {
        do {
            try await performanceMonitor.startMonitoring()
            XCTAssertTrue(performanceMonitor.isMonitoring)
            
            // Starting again should not fail
            try await performanceMonitor.startMonitoring()
            XCTAssertTrue(performanceMonitor.isMonitoring)
        } catch {
            XCTFail("Failed to handle double start: \(error)")
        }
    }
    
    // MARK: - FPS Tracking Tests
    
    func testFrameProcessingRecording() async {
        do {
            try await performanceMonitor.startMonitoring()
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Record several frames at ~15 FPS
            for i in 0..<10 {
                let timestamp = startTime + Double(i) * (1.0 / 15.0)
                performanceMonitor.recordFrameProcessed(at: timestamp)
            }
            
            // Give it a moment to process
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // FPS should be approximately 15
            let fps = performanceMonitor.currentFPS
            XCTAssertGreaterThan(fps, 10.0)
            XCTAssertLessThan(fps, 20.0)
        } catch {
            XCTFail("Failed during FPS tracking test: \(error)")
        }
    }
    
    func testFPSCalculationWithSingleFrame() async {
        do {
            try await performanceMonitor.startMonitoring()
            
            // Record single frame
            performanceMonitor.recordFrameProcessed(at: CFAbsoluteTimeGetCurrent())
            
            // Give it a moment to process
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // FPS should be 0 with only one frame
            XCTAssertEqual(performanceMonitor.currentFPS, 0)
        } catch {
            XCTFail("Failed during single frame FPS test: \(error)")
        }
    }
    
    // MARK: - Inference Recording Tests
    
    func testInferenceRecording() async {
        do {
            try await performanceMonitor.startMonitoring()
            
            // Record several inference operations
            for _ in 0..<5 {
                let duration = TimeInterval.random(in: 0.02...0.08) // 20-80ms
                let memoryUsed = UInt64.random(in: 100_000_000...500_000_000) // 100-500MB
                performanceMonitor.recordInference(duration: duration, memoryUsed: memoryUsed)
            }
            
            // Give it a moment to process
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check that metrics are updated
            let metrics = performanceMonitor.currentMetrics
            XCTAssertGreaterThan(metrics.averageInferenceTime, 0)
            XCTAssertGreaterThan(performanceMonitor.memoryPressure, 0)
        } catch {
            XCTFail("Failed during inference recording test: \(error)")
        }
    }
    
    // MARK: - Optimization Tests
    
    func testOptimizationWithNormalConditions() async {
        let strategy = await performanceMonitor.triggerOptimization()
        XCTAssertEqual(strategy, .none)
    }
    
    func testOptimizationDetermination() async {
        // Create a testable performance monitor to control conditions
        let testMonitor = TestablePerformanceMonitor()
        
        // Test memory pressure optimization
        testMonitor.setMemoryPressure(0.9)
        let memoryStrategy = await testMonitor.triggerOptimization()
        XCTAssertEqual(memoryStrategy, .clearCaches)
        
        // Test critical memory pressure
        testMonitor.setMemoryPressure(0.96)
        let criticalMemoryStrategy = await testMonitor.triggerOptimization()
        XCTAssertEqual(criticalMemoryStrategy, .unloadUnusedModels)
        
        // Test CPU usage optimization
        testMonitor.setMemoryPressure(0.5) // Reset memory pressure
        testMonitor.setCPUUsage(0.9)
        let cpuStrategy = await testMonitor.triggerOptimization()
        XCTAssertEqual(cpuStrategy, .reduceFrameRate)
        
        // Test thermal throttling
        testMonitor.setCPUUsage(0.5) // Reset CPU usage
        testMonitor.setThermalState(.critical)
        let thermalStrategy = await testMonitor.triggerOptimization()
        XCTAssertEqual(thermalStrategy, .emergencyShutdown)
    }
    
    func testOptimizationThrottling() async {
        let testMonitor = TestablePerformanceMonitor()
        testMonitor.setMemoryPressure(0.9)
        
        // First optimization should work
        let firstStrategy = await testMonitor.triggerOptimization()
        XCTAssertNotEqual(firstStrategy, .none)
        
        // Second optimization immediately after should be throttled
        let secondStrategy = await testMonitor.triggerOptimization()
        XCTAssertEqual(secondStrategy, .none)
    }
    
    // MARK: - Diagnostics Tests
    
    func testDiagnosticsCollection() async {
        do {
            try await performanceMonitor.startMonitoring()
            
            // Record some data
            performanceMonitor.recordFrameProcessed(at: CFAbsoluteTimeGetCurrent())
            performanceMonitor.recordInference(duration: 0.05, memoryUsed: 200_000_000)
            
            let diagnostics = await performanceMonitor.collectDiagnostics()
            
            XCTAssertNotNil(diagnostics.systemInfo)
            XCTAssertNotNil(diagnostics.performanceHistory)
            XCTAssertNotNil(diagnostics.memoryBreakdown)
            XCTAssertGreaterThan(diagnostics.systemInfo.totalMemory, 0)
            XCTAssertGreaterThan(diagnostics.systemInfo.processorCount, 0)
        } catch {
            XCTFail("Failed during diagnostics collection test: \(error)")
        }
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateAssignment() {
        XCTAssertNotNil(performanceMonitor.delegate)
        XCTAssertTrue(performanceMonitor.delegate === mockDelegate)
    }
    
    func testDelegateCallbacks() async {
        do {
            try await performanceMonitor.startMonitoring()
            
            // Give it time for periodic updates
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            XCTAssertTrue(mockDelegate.didStartMonitoringCalled)
            
            performanceMonitor.stopMonitoring()
            
            // Give it time to process stop
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            XCTAssertTrue(mockDelegate.didStopMonitoringCalled)
        } catch {
            XCTFail("Failed during delegate callback test: \(error)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testRecordingWithoutMonitoring() {
        // Recording without monitoring should not crash
        performanceMonitor.recordFrameProcessed(at: CFAbsoluteTimeGetCurrent())
        performanceMonitor.recordInference(duration: 0.05, memoryUsed: 200_000_000)
        
        // Should still have zero metrics
        XCTAssertEqual(performanceMonitor.currentFPS, 0)
    }
    
    // MARK: - Performance Configuration Tests
    
    func testPerformanceConfigurationDefaults() {
        let defaultConfig = PerformanceConfiguration()
        
        XCTAssertEqual(defaultConfig.targetFPS, 15.0)
        XCTAssertEqual(defaultConfig.memoryPressureThreshold, 0.8)
        XCTAssertEqual(defaultConfig.cpuUsageThreshold, 0.8)
        XCTAssertEqual(defaultConfig.thermalThrottlingThreshold, .serious)
        XCTAssertEqual(defaultConfig.updateInterval, 1.0)
        XCTAssertEqual(defaultConfig.maxFPSSamples, 30)
        XCTAssertEqual(defaultConfig.maxInferenceSamples, 100)
        XCTAssertTrue(defaultConfig.automaticOptimizationEnabled)
        XCTAssertTrue(defaultConfig.diagnosticsEnabled)
    }
    
    func testOptimizationStrategyPriority() {
        XCTAssertEqual(OptimizationStrategy.none.priority, 0)
        XCTAssertEqual(OptimizationStrategy.clearCaches.priority, 1)
        XCTAssertEqual(OptimizationStrategy.emergencyShutdown.priority, 7)
        
        // Test that emergency shutdown has highest priority
        let strategies = OptimizationStrategy.allCases
        let maxPriority = strategies.map { $0.priority }.max()
        XCTAssertEqual(maxPriority, OptimizationStrategy.emergencyShutdown.priority)
    }
}

// MARK: - Mock Delegate

class MockPerformanceMonitorDelegate: PerformanceMonitorDelegate {
    var didStartMonitoringCalled = false
    var didStopMonitoringCalled = false
    var didUpdateMetricsCalled = false
    var didDetectMemoryPressureCalled = false
    var didDetectThermalThrottlingCalled = false
    var didTriggerOptimizationCalled = false
    var didFailWithErrorCalled = false
    
    var lastMetrics: PerformanceMetrics?
    var lastMemoryPressure: Float?
    var lastThermalState: ProcessInfo.ThermalState?
    var lastOptimizationStrategy: OptimizationStrategy?
    var lastError: EdgeTAMError?
    
    func performanceMonitorDidStartMonitoring(_ monitor: PerformanceMonitorProtocol) {
        didStartMonitoringCalled = true
    }
    
    func performanceMonitorDidStopMonitoring(_ monitor: PerformanceMonitorProtocol) {
        didStopMonitoringCalled = true
    }
    
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didUpdateMetrics metrics: PerformanceMetrics) {
        didUpdateMetricsCalled = true
        lastMetrics = metrics
    }
    
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectMemoryPressure level: Float) {
        didDetectMemoryPressureCalled = true
        lastMemoryPressure = level
    }
    
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didDetectThermalThrottling state: ProcessInfo.ThermalState) {
        didDetectThermalThrottlingCalled = true
        lastThermalState = state
    }
    
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didTriggerOptimization strategy: OptimizationStrategy) {
        didTriggerOptimizationCalled = true
        lastOptimizationStrategy = strategy
    }
    
    func performanceMonitor(_ monitor: PerformanceMonitorProtocol, didFailWithError error: EdgeTAMError) {
        didFailWithErrorCalled = true
        lastError = error
    }
}

// MARK: - Testable PerformanceMonitor

class TestablePerformanceMonitor: PerformanceMonitor {
    private var mockMemoryPressure: Float = 0
    private var mockCPUUsage: Float = 0
    private var mockThermalState: ProcessInfo.ThermalState = .nominal
    private var mockFPS: Double = 15.0
    
    override var memoryPressure: Float {
        return mockMemoryPressure
    }
    
    override var cpuUsage: Float {
        return mockCPUUsage
    }
    
    override var thermalState: ProcessInfo.ThermalState {
        return mockThermalState
    }
    
    override var currentFPS: Double {
        return mockFPS
    }
    
    func setMemoryPressure(_ pressure: Float) {
        mockMemoryPressure = pressure
    }
    
    func setCPUUsage(_ usage: Float) {
        mockCPUUsage = usage
    }
    
    func setThermalState(_ state: ProcessInfo.ThermalState) {
        mockThermalState = state
    }
    
    func setFPS(_ fps: Double) {
        mockFPS = fps
    }
}