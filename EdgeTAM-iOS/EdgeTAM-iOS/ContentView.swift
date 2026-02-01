import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @State private var isModelAvailable = false
    @State private var isCheckingModel = true
    
    var body: some View {
        Group {
            if isCheckingModel {
                // Show loading while checking for model
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Checking for EdgeTAM model...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
            } else if isModelAvailable {
                // Model found, show camera view
                CameraView()
                    .environmentObject(dependencyContainer)
            } else {
                // Model not found, show setup instructions
                ModelSetupView()
            }
        }
        .onAppear {
            checkModelAvailability()
        }
    }
    
    private func checkModelAvailability() {
        // Check if EdgeTAM model exists in bundle
        DispatchQueue.global(qos: .userInitiated).async {
            let modelExists = Bundle.main.url(forResource: "EdgeTAM", withExtension: "mlmodelc") != nil ||
                             Bundle.main.url(forResource: "EdgeTAM", withExtension: "mlmodel") != nil
            
            DispatchQueue.main.async {
                isModelAvailable = modelExists
                isCheckingModel = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer())
}