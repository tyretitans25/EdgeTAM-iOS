import SwiftUI

/// View displayed when EdgeTAM CoreML model is not found in the app bundle
struct ModelSetupView: View {
    @State private var showingDetailedInstructions = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                    
                    // Title
                    Text("EdgeTAM Model Required")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    // Subtitle
                    Text("To use this app, you need to add the EdgeTAM CoreML model")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Quick steps card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Setup")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        SetupStepView(
                            number: "1",
                            title: "Convert Model",
                            description: "Convert EdgeTAM PyTorch model to CoreML format using Python"
                        )
                        
                        SetupStepView(
                            number: "2",
                            title: "Add to Xcode",
                            description: "Drag EdgeTAM.mlpackage into your Xcode project"
                        )
                        
                        SetupStepView(
                            number: "3",
                            title: "Verify Target",
                            description: "Ensure model is added to EdgeTAM-iOS target"
                        )
                        
                        SetupStepView(
                            number: "4",
                            title: "Rebuild",
                            description: "Clean build folder and rebuild the app"
                        )
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .padding(.horizontal)
                    
                    // Detailed instructions button
                    Button(action: {
                        showingDetailedInstructions = true
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("View Detailed Instructions")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Info box
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("What is EdgeTAM?")
                                .font(.headline)
                        }
                        
                        Text("EdgeTAM (Edge Track Anything Model) is Meta's efficient video segmentation model optimized for mobile devices. It enables real-time object tracking with on-device processing.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .sheet(isPresented: $showingDetailedInstructions) {
            DetailedInstructionsView()
        }
    }
}

/// Individual setup step view
struct SetupStepView: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number circle
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

/// Detailed instructions view with conversion steps
struct DetailedInstructionsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Prerequisites section
                    InstructionSection(
                        title: "Prerequisites",
                        icon: "checkmark.circle.fill",
                        color: .green
                    ) {
                        Text("Install required Python packages:")
                            .font(.subheadline)
                        
                        CodeBlockView(code: "pip install torch torchvision coremltools numpy pillow")
                    }
                    
                    // Download model section
                    InstructionSection(
                        title: "1. Download EdgeTAM Model",
                        icon: "arrow.down.circle.fill",
                        color: .blue
                    ) {
                        Text("Clone the Segment Anything repository:")
                            .font(.subheadline)
                        
                        CodeBlockView(code: """
                        git clone https://github.com/facebookresearch/segment-anything.git
                        cd segment-anything
                        wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
                        """)
                    }
                    
                    // Convert to CoreML section
                    InstructionSection(
                        title: "2. Convert to CoreML",
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        color: .orange
                    ) {
                        Text("Create a Python script to convert the model:")
                            .font(.subheadline)
                        
                        Text("See README.md for complete conversion code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    // Add to Xcode section
                    InstructionSection(
                        title: "3. Add to Xcode Project",
                        icon: "plus.circle.fill",
                        color: .purple
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Drag EdgeTAM.mlpackage into Xcode")
                            Text("• Check 'Copy items if needed'")
                            Text("• Add to EdgeTAM-iOS target")
                            Text("• Verify in Project Navigator")
                        }
                        .font(.subheadline)
                    }
                    
                    // Rebuild section
                    InstructionSection(
                        title: "4. Rebuild App",
                        icon: "hammer.circle.fill",
                        color: .red
                    ) {
                        Text("Clean and rebuild:")
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Product > Clean Build Folder (⇧⌘K)")
                            Text("• Product > Build (⌘B)")
                            Text("• Run on device or simulator")
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }
                    
                    // Help section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.blue)
                            Text("Need Help?")
                                .font(.headline)
                        }
                        
                        Text("For complete instructions with code examples, see the README.md file in the project repository.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Link("View on GitHub", destination: URL(string: "https://github.com/tyretitans25/EdgeTAM-iOS")!)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Setup Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Reusable instruction section with icon and title
struct InstructionSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Code block view with monospaced font
struct CodeBlockView: View {
    let code: String
    
    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
    }
}

#Preview {
    ModelSetupView()
}
