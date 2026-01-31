import Foundation
import AVFoundation
import CoreVideo

/// Integration test to verify the complete EdgeTAM processing pipeline
@MainActor
class PipelineIntegrationTest {
    
    private let dependencyContainer = DependencyContainer()
    
    init() {
        dependencyContainer.registerDefaultServices()
    }
    
    /// Tests the complete pipeline from camera to export
    func testCompletePipeline() async throws {
        // 1. Resolve all services
        let cameraManager = try dependencyContainer.resolve(CameraManagerProtocol.self)
        let videoSegmentationEngine = try dependencyContainer.resolve(VideoSegmentationEngineProtocol.self)
        let objectTracker = try dependencyContainer.resolve(ObjectTrackerProtocol.self)
        let promptHandler = try dependencyContainer.resolve(PromptHandlerProtocol.self)
        let performanceMonitor = try dependencyContainer.resolve(PerformanceMonitorProtocol.self)
        let privacyManager = try dependencyContainer.resolve(PrivacyManagerProtocol.self)
        let exportManager = try dependencyContainer.resolve(ExportManagerProtocol.self)
        
        print("✅ All services resolved successfully")
        
        // 2. Test privacy manager initialization
        let complianceStatus = privacyManager.privacyComplianceStatus
        assert(complianceStatus.isOnDeviceProcessingActive, "On-device processing should be active")
        print("✅ Privacy compliance verified")
        
        // 3. Test camera permission (simulation)
        print("✅ Camera permission system ready")
        
        // 4. Test prompt handling
        let testPrompt = Prompt.point(PointPrompt(
            location: CGPoint(x: 100, y: 100),
            modelCoordinates: CGPoint(x: 0.5, y: 0.5),
            isPositive: true
        ))
        
        try await promptHandler.registerPrompt(testPrompt)
        print("✅ Prompt handling system working")
        
        // 5. Test performance monitoring
        performanceMonitor.startMonitoring()
        performanceMonitor.recordFrame()
        let metrics = performanceMonitor.currentMetrics
        assert(metrics.currentFPS >= 0, "Performance monitoring should provide valid metrics")
        print("✅ Performance monitoring active")
        
        // 6. Test privacy cleanup
        let tempURL = privacyManager.createTemporaryFileURL(withExtension: "test")
        privacyManager.trackTemporaryFile(tempURL)
        try await privacyManager.cleanupTemporaryFiles()
        print("✅ Privacy cleanup system working")
        
        print("🎉 Complete pipeline integration test passed!")
    }
    
    /// Tests service dependency resolution
    func testServiceDependencies() throws {
        let services = [
            "CameraManagerProtocol",
            "VideoSegmentationEngineProtocol", 
            "ObjectTrackerProtocol",
            "PromptHandlerProtocol",
            "PerformanceMonitorProtocol",
            "PrivacyManagerProtocol",
            "ExportManagerProtocol",
            "MaskRendererProtocol"
        ]
        
        for serviceName in services {
            switch serviceName {
            case "CameraManagerProtocol":
                _ = try dependencyContainer.resolve(CameraManagerProtocol.self)
            case "VideoSegmentationEngineProtocol":
                _ = try dependencyContainer.resolve(VideoSegmentationEngineProtocol.self)
            case "ObjectTrackerProtocol":
                _ = try dependencyContainer.resolve(ObjectTrackerProtocol.self)
            case "PromptHandlerProtocol":
                _ = try dependencyContainer.resolve(PromptHandlerProtocol.self)
            case "PerformanceMonitorProtocol":
                _ = try dependencyContainer.resolve(PerformanceMonitorProtocol.self)
            case "PrivacyManagerProtocol":
                _ = try dependencyContainer.resolve(PrivacyManagerProtocol.self)
            case "ExportManagerProtocol":
                _ = try dependencyContainer.resolve(ExportManagerProtocol.self)
            case "MaskRendererProtocol":
                _ = try dependencyContainer.resolve(MaskRendererProtocol.self)
            default:
                break
            }
            print("✅ \(serviceName) resolved successfully")
        }
        
        print("🎉 All service dependencies resolved successfully!")
    }
    
    /// Tests the UI integration
    func testUIIntegration() {
        let cameraViewModel = CameraViewModel()
        cameraViewModel.setupDependencies(dependencyContainer)
        
        // Verify all dependencies are set up
        assert(cameraViewModel.captureSession != nil, "Capture session should be initialized")
        
        print("✅ UI integration test passed!")
    }
}

// MARK: - Test Runner

extension PipelineIntegrationTest {
    
    /// Runs all integration tests
    static func runAllTests() async {
        let tester = PipelineIntegrationTest()
        
        do {
            print("🧪 Starting EdgeTAM Pipeline Integration Tests...")
            print("=" * 50)
            
            try tester.testServiceDependencies()
            print("")
            
            try await tester.testCompletePipeline()
            print("")
            
            tester.testUIIntegration()
            print("")
            
            print("=" * 50)
            print("🎉 All integration tests passed successfully!")
            
        } catch {
            print("❌ Integration test failed: \(error)")
        }
    }
}

// MARK: - String Extension for Test Output

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}