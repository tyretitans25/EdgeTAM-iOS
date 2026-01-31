import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Mask Display") {
                    Toggle("Show Masks", isOn: $viewModel.showMasks)
                    
                    if viewModel.showMasks {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Opacity")
                                Spacer()
                                Text("\(Int(viewModel.maskOpacity * 100))%")
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(
                                value: $viewModel.maskOpacity,
                                in: 0.0...0.8,
                                step: 0.1
                            )
                        }
                    }
                }
                
                Section("Performance") {
                    HStack {
                        Text("Current FPS")
                        Spacer()
                        Text("\(String(format: "%.1f", viewModel.currentFPS))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Processing Status")
                        Spacer()
                        Text(viewModel.isProcessing ? "Active" : "Inactive")
                            .foregroundColor(viewModel.isProcessing ? .green : .secondary)
                    }
                    
                    HStack {
                        Text("Tracked Objects")
                        Spacer()
                        Text("\(viewModel.trackedObjects.count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Object Management") {
                    if viewModel.trackedObjects.isEmpty {
                        Text("No objects currently tracked")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(viewModel.trackedObjects.enumerated()), id: \.offset) { index, object in
                            HStack {
                                Circle()
                                    .fill(colorForObject(at: index))
                                    .frame(width: 20, height: 20)
                                
                                VStack(alignment: .leading) {
                                    Text("Object \(index + 1)")
                                        .font(.headline)
                                    Text("Confidence: \(String(format: "%.1f%%", object.confidence * 100))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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
    
    private func colorForObject(at index: Int) -> Color {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink]
        return colors[index % colors.count]
    }
}

#Preview {
    SettingsView(viewModel: CameraViewModel())
}