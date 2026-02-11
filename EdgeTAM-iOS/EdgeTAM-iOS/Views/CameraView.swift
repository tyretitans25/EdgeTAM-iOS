import SwiftUI
import AVFoundation
import CoreVideo

/// SwiftUI wrapper for camera preview layer
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        
        DispatchQueue.main.async {
            self.previewLayer = previewLayer
        }
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        DispatchQueue.main.async {
            uiView.previewLayer?.frame = uiView.bounds
        }
    }
}

/// Custom UIView that properly handles layout for the preview layer
class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
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
                if viewModel.isCameraReady {
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
                } else {
                    // Show loading state while camera initializes
                    ZStack {
                        Color.black
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Initializing camera...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                    }
                }
                
                // Overlay for segmentation masks
                if viewModel.showMasks, viewModel.currentMaskImage != nil {
                    MaskOverlayView(
                        maskImage: viewModel.currentMaskImage,
                        opacity: viewModel.maskOpacity
                    )
                    .clipped()
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
                        .disabled(!viewModel.isCameraReady || selectedPrompts.isEmpty)
                        
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
            Task { @MainActor in
                if granted {
                    viewModel.startCamera()
                }
            }
        }
    }
    
    private func handleTapGesture(at location: CGPoint, in size: CGSize) {
        // Convert screen tap to camera-space normalized coordinates using the preview layer.
        // This accounts for .resizeAspectFill cropping and any orientation transforms.
        let normalizedPoint: CGPoint
        if let layer = previewLayer {
            // captureDevicePointConverted returns (0,0)-(1,1) in camera sensor space
            let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: location)
            normalizedPoint = devicePoint
        } else {
            // Fallback: simple normalization (won't account for aspect fill crop)
            normalizedPoint = CGPoint(
                x: location.x / size.width,
                y: location.y / size.height
            )
        }

        // Create point prompt
        let pointPrompt = Prompt.point(PointPrompt(
            location: location,
            modelCoordinates: normalizedPoint,
            isPositive: true
        ))
        
        selectedPrompts.append(pointPrompt)
        viewModel.addPrompt(pointPrompt)
        
        // Auto-start processing if not already running
        if !viewModel.isProcessing {
            viewModel.startProcessing()
        }
    }
    
    private func handleDragGesture(start: CGPoint, end: CGPoint, in size: CGSize) {
        // Convert drag to camera-space normalized coordinates
        let normalizedStart: CGPoint
        let normalizedEnd: CGPoint
        if let layer = previewLayer {
            normalizedStart = layer.captureDevicePointConverted(fromLayerPoint: start)
            normalizedEnd = layer.captureDevicePointConverted(fromLayerPoint: end)
        } else {
            normalizedStart = CGPoint(x: start.x / size.width, y: start.y / size.height)
            normalizedEnd = CGPoint(x: end.x / size.width, y: end.y / size.height)
        }
        
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
            
            // Auto-start processing if not already running
            if !viewModel.isProcessing {
                viewModel.startProcessing()
            }
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
                // Use the original screen tap location for the dot so it
                // appears exactly where the user tapped, regardless of
                // camera aspect-fill cropping.
                Circle()
                    .fill(pointPrompt.isPositive ? Color.green : Color.red)
                    .frame(width: 20, height: 20)
                    .position(
                        x: pointPrompt.location.x,
                        y: pointPrompt.location.y
                    )

            case .box(let boxPrompt):
                // Use the original screen rect for the box indicator
                Rectangle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(
                        width: boxPrompt.rect.width,
                        height: boxPrompt.rect.height
                    )
                    .position(
                        x: boxPrompt.rect.midX,
                        y: boxPrompt.rect.midY
                    )

            case .mask(_):
                EmptyView()
            }
        }
    }
}

/// View for displaying segmentation mask overlays
struct MaskOverlayView: View {
    let maskImage: UIImage?
    let opacity: Double

    var body: some View {
        if let image = maskImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .opacity(opacity)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    CameraView()
        .environmentObject(DependencyContainer())
}