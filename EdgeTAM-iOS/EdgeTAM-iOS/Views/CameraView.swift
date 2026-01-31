import SwiftUI
import AVFoundation
import CoreVideo

/// SwiftUI wrapper for camera preview layer
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.main.async {
            self.previewLayer = previewLayer
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.layer.bounds
        }
    }
}

/// Main camera view with live preview and controls
struct CameraView: View {
    @EnvironmentObject var dependencyContainer: DependencyContainer
    @StateObject private var viewModel = CameraViewModel()
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var showingSettings = false
    @State private var showingExport = false
    @State private var selectedPrompts: [Prompt] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraPreviewView(
                    session: viewModel.captureSession,
                    previewLayer: $previewLayer
                )
                .clipped()
                .onTapGesture { location in
                    handleTapGesture(at: location, in: geometry.size)
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            handleDragGesture(start: value.startLocation, end: value.location, in: geometry.size)
                        }
                )
                
                // Overlay for segmentation masks
                if viewModel.showMasks {
                    MaskOverlayView(
                        trackedObjects: viewModel.trackedObjects,
                        opacity: viewModel.maskOpacity
                    )
                }
                
                // Top controls
                VStack {
                    HStack {
                        // Camera switch button
                        Button(action: {
                            viewModel.switchCamera()
                        }) {
                            HStack {
                                if viewModel.isSwitchingCamera {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "camera.rotate")
                                        .font(.title2)
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                        }
                        .disabled(viewModel.isSwitchingCamera)
                        
                        Spacer()
                        
                        // Performance metrics
                        VStack(alignment: .trailing) {
                            Text("FPS: \(String(format: "%.1f", viewModel.currentFPS))")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            if viewModel.isSwitchingCamera {
                                Text("Switching Camera...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else if viewModel.isProcessing {
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // Settings button
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
                
                // Bottom controls
                VStack {
                    Spacer()
                    
                    HStack {
                        // Clear prompts button
                        Button(action: {
                            viewModel.clearAllPrompts()
                            selectedPrompts.removeAll()
                        }) {
                            VStack {
                                Image(systemName: "trash")
                                    .font(.title2)
                                Text("Clear")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(12)
                        }
                        .disabled(selectedPrompts.isEmpty)
                        
                        Spacer()
                        
                        // Recording/Processing toggle
                        Button(action: {
                            if viewModel.isProcessing {
                                viewModel.stopProcessing()
                            } else {
                                viewModel.startProcessing()
                            }
                        }) {
                            VStack {
                                Image(systemName: viewModel.isProcessing ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(viewModel.isProcessing ? .red : .white)
                                
                                Text(viewModel.isProcessing ? "Stop" : "Start")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        // Export button
                        Button(action: {
                            showingExport = true
                        }) {
                            VStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                Text("Export")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(12)
                        }
                        .disabled(!viewModel.hasProcessedFrames)
                    }
                    .padding()
                }
                
                // Prompt indicators
                ForEach(Array(selectedPrompts.enumerated()), id: \.offset) { index, prompt in
                    PromptIndicatorView(prompt: prompt, index: index)
                }
                
                // Error overlay
                if let error = viewModel.currentError {
                    VStack {
                        Spacer()
                        
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            
                            Text(error.localizedDescription)
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            viewModel.stopProcessing()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingExport) {
            ExportView(viewModel: viewModel)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        viewModel.setupDependencies(dependencyContainer)
        viewModel.requestCameraPermission { granted in
            if granted {
                viewModel.startCamera()
            }
        }
    }
    
    private func handleTapGesture(at location: CGPoint, in size: CGSize) {
        // Convert tap location to normalized coordinates
        let normalizedPoint = CGPoint(
            x: location.x / size.width,
            y: location.y / size.height
        )
        
        // Create point prompt
        let pointPrompt = Prompt.point(PointPrompt(
            location: location,
            modelCoordinates: normalizedPoint,
            isPositive: true
        ))
        
        selectedPrompts.append(pointPrompt)
        viewModel.addPrompt(pointPrompt)
    }
    
    private func handleDragGesture(start: CGPoint, end: CGPoint, in size: CGSize) {
        // Convert drag to normalized coordinates
        let normalizedStart = CGPoint(
            x: start.x / size.width,
            y: start.y / size.height
        )
        let normalizedEnd = CGPoint(
            x: end.x / size.width,
            y: end.y / size.height
        )
        
        // Create bounding box
        let minX = min(normalizedStart.x, normalizedEnd.x)
        let minY = min(normalizedStart.y, normalizedEnd.y)
        let maxX = max(normalizedStart.x, normalizedEnd.x)
        let maxY = max(normalizedStart.y, normalizedEnd.y)
        
        let boundingBox = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        
        // Only create box if it's large enough
        if boundingBox.width > 0.05 && boundingBox.height > 0.05 {
            let boxPrompt = Prompt.box(BoxPrompt(
                rect: CGRect(
                    x: start.x,
                    y: start.y,
                    width: end.x - start.x,
                    height: end.y - start.y
                ),
                modelCoordinates: boundingBox
            ))
            selectedPrompts.append(boxPrompt)
            viewModel.addPrompt(boxPrompt)
        }
    }
}

/// View for displaying prompt indicators on the camera preview
struct PromptIndicatorView: View {
    let prompt: Prompt
    let index: Int
    
    var body: some View {
        GeometryReader { geometry in
            switch prompt {
            case .point(let pointPrompt):
                Circle()
                    .fill(pointPrompt.isPositive ? Color.green : Color.red)
                    .frame(width: 20, height: 20)
                    .position(
                        x: pointPrompt.modelCoordinates.x * geometry.size.width,
                        y: pointPrompt.modelCoordinates.y * geometry.size.height
                    )
                
            case .box(let boxPrompt):
                Rectangle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(
                        width: boxPrompt.modelCoordinates.width * geometry.size.width,
                        height: boxPrompt.modelCoordinates.height * geometry.size.height
                    )
                    .position(
                        x: (boxPrompt.modelCoordinates.minX + boxPrompt.modelCoordinates.width / 2) * geometry.size.width,
                        y: (boxPrompt.modelCoordinates.minY + boxPrompt.modelCoordinates.height / 2) * geometry.size.height
                    )
                
            case .mask(_):
                EmptyView()
            }
        }
    }
}

/// View for displaying segmentation mask overlays
struct MaskOverlayView: View {
    let trackedObjects: [TrackedObject]
    let opacity: Double
    
    var body: some View {
        // This would be implemented with Metal or Core Graphics
        // For now, showing a placeholder
        Rectangle()
            .fill(Color.clear)
    }
}

#Preview {
    CameraView()
        .environmentObject(DependencyContainer())
}