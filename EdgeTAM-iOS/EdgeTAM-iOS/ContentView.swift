import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    
    var body: some View {
        CameraView()
            .environmentObject(dependencyContainer)
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer())
}