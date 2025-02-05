import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appState: AppState
    
    var body: some View {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.headline)
                
                // Picker to choose between Local LLM and Gemini.
                Picker("LLM Provider", selection: $appState.selectedLLMType) {
                    ForEach(LLMType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Show setting view based on provider selected.
                if appState.selectedLLMType == .local {
                    LocalLLMSettingsView(evaluator: appState.localLLMProvider)
                } else {
                    GeminiSettingsView(appState: appState)
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 400, minHeight: 300)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
}

struct GeminiSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedModel: GeminiModel = .twoflash
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Gemini Provider Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("API Key", text: $apiKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Model", selection: $selectedModel) {
                        ForEach(GeminiModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Button("Save Gemini Settings") {
                        // Update gemini configuration in app state.
                        appState.geminiConfig.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        appState.geminiConfig.modelName = selectedModel.rawValue
                        appState.updateGeminiProvider()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
        }
        .onAppear {
            // Preload the current values from appState.
            self.apiKey = appState.geminiConfig.apiKey
            if let currentModel = GeminiModel(rawValue: appState.geminiConfig.modelName) {
                self.selectedModel = currentModel
            }
        }
    }
}


struct LocalLLMSettingsView: View {
    @ObservedObject private var llmEvaluator: LocalLLMProvider
    @State private var showingDeleteAlert = false
    @State private var showingErrorAlert = false
    
    init(evaluator: LocalLLMProvider) {
        self.llmEvaluator = evaluator
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !llmEvaluator.modelInfo.isEmpty {
                Text(llmEvaluator.modelInfo)
                    .textFieldStyle(.roundedBorder)
            }
            GroupBox("Model Information") {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Model", value: "Mistral Small 24B (4-bit Quantized)")
                    InfoRow(label: "Size", value: "~13GB")
                    InfoRow(label: "Optimized", value: "Apple Silicon")
                }
                .padding(.vertical, 4)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if llmEvaluator.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Downloading model...")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { llmEvaluator.cancelDownload() }) {
                                    Text("Cancel")
                                        .foregroundColor(.red)
                                }
                            }
                            ProgressView(value: llmEvaluator.downloadProgress) {
                                Text("\(Int(llmEvaluator.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if llmEvaluator.running {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading model...")
                                .foregroundColor(.secondary)
                        }
                    } else if case .idle = llmEvaluator.loadState {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model needs to be downloaded before first use")
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Download Model") {
                                    llmEvaluator.startDownload()
                                }
                                .buttonStyle(.borderedProminent)
                                if llmEvaluator.lastError != nil {
                                    Button("Retry") {
                                        llmEvaluator.retryDownload()
                                    }
                                    .disabled(llmEvaluator.retryCount >= 3)
                                }
                            }
                            if let error = llmEvaluator.lastError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Model ready")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Delete Model") {
                                    showingDeleteAlert = true
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Delete Model", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do {
                    try llmEvaluator.deleteModel()
                } catch {
                    llmEvaluator.lastError = "Failed to delete model: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        } message: {
            Text("Are you sure you want to delete the downloaded model? You'll need to download it again to use local processing.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = llmEvaluator.lastError {
                Text(error)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
