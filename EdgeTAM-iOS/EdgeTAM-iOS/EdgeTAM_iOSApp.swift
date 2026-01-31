import SwiftUI

@main
struct EdgeTAM_iOSApp: App {
    let dependencyContainer = DependencyContainer()
    
    init() {
        // Register all default services
        dependencyContainer.registerDefaultServices()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencyContainer)
                .task {
                    // Initialize services when the app starts
                    do {
                        try await dependencyContainer.initializeServices()
                        
                        // Initialize privacy manager for app lifecycle handling
                        _ = try? dependencyContainer.resolve(PrivacyManagerProtocol.self)
                        // Privacy manager will automatically handle app lifecycle events
                        // through notification observers set up in its initializer
                    } catch {
                        print("Failed to initialize services: \(error)")
                    }
                }
        }
    }
}