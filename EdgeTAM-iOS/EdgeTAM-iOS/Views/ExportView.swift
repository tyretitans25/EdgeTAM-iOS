import SwiftUI

struct ExportView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportError: String?
    @State private var exportCompleted = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Export Status
                if isExporting {
                    VStack(spacing: 16) {
                        ProgressView(value: exportProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text("Exporting video with segmentation masks...")
                            .font(.headline)
                        
                        Text("\(Int(exportProgress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if exportCompleted {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Export Complete!")
                            .font(.headline)
                        
                        Text("Your video has been saved to Photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    // Export Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Options")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Processed Frames:")
                                Spacer()
                                Text("\(viewModel.getProcessedFrames().count)")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Tracked Objects:")
                                Spacer()
                                Text("\(viewModel.trackedObjects.count)")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Mask Opacity:")
                                Spacer()
                                Text("\(Int(viewModel.maskOpacity * 100))%")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        Text("Export Settings")
                            .font(.headline)
                            .padding(.top)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Original resolution maintained")
                            Text("• Segmentation masks applied")
                            Text("• Saved to Photos app")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Error Display
                if let error = exportError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Action Buttons
                HStack(spacing: 20) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting)
                    
                    Button(exportCompleted ? "Done" : "Start Export") {
                        if exportCompleted {
                            dismiss()
                        } else {
                            startExport()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || viewModel.getProcessedFrames().isEmpty)
                }
                .padding()
            }
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }
            }
        }
    }
    
    private func startExport() {
        isExporting = true
        exportError = nil
        exportProgress = 0.0
        
        // Simulate export progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            exportProgress += 0.02
            
            if exportProgress >= 1.0 {
                timer.invalidate()
                isExporting = false
                exportCompleted = true
                exportProgress = 1.0
            }
        }
        
        // TODO: Integrate with actual ExportManager
        // This would call the ExportManager service to handle the actual export
        /*
        Task {
            do {
                let exportManager = viewModel.dependencyContainer.resolve(ExportManagerProtocol.self)
                try await exportManager.exportVideo(
                    frames: viewModel.getProcessedFrames(),
                    opacity: viewModel.maskOpacity
                ) { progress in
                    DispatchQueue.main.async {
                        exportProgress = progress
                    }
                }
                
                DispatchQueue.main.async {
                    isExporting = false
                    exportCompleted = true
                }
            } catch {
                DispatchQueue.main.async {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
        */
    }
}

#Preview {
    ExportView(viewModel: CameraViewModel())
}