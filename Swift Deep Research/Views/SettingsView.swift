import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var appState: AppState
    @State private var selectedProvider = UserDefaults.standard.string(forKey: "current_provider") ?? "gemini"
    
    // Gemini settings
    @State private var geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    @State private var selectedGeminiModel = GeminiModel(rawValue: UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash-latest") ?? .oneflash
    
    // Google settings
    @State private var googleApiKey = UserDefaults.standard.string(forKey: "google_api_key") ?? ""
    @State private var googleSearchEngineId = UserDefaults.standard.string(forKey: "google_search_engine_id") ?? ""
    
    var body: some View {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.headline)
                
                // Picker to choose between Local LLM, Gemini, and Google.
                Picker("Provider", selection: $selectedProvider) {
                    Text("Gemini AI").tag("gemini")
                    Text("Local LLM").tag("local")
                    Text("Google").tag("google")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Show setting view based on provider selected.
                if selectedProvider == "local" {
                    LocalLLMSettingsView(evaluator: appState.localLLMProvider)
                } else
                if selectedProvider == "gemini" {
                    Section("Gemini AI Settings") {
                        TextField("API Key", text: $geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Model", selection: $selectedGeminiModel) {
                            ForEach(GeminiModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        
                        Button("Get API Key") {
                            NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                        }
                    }
                } else
                if selectedProvider == "google" {
                    Section("Google Search Settings") {
                        TextField("API Key", text: $googleApiKey)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Search Engine ID", text: $googleSearchEngineId)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Get API Key") {
                            NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/")!)
                        }
                    }
                }
                
                Spacer()
                
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
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
    
    private func saveSettings() {
        // Save provider-specific settings
        if selectedProvider == "gemini" {
            appState.saveGeminiConfig(apiKey: geminiApiKey, model: selectedGeminiModel)
        } else if selectedProvider == "google" {
            appState.updateGoogleSearchConfig(
                apiKey: googleApiKey,
                searchEngineId: googleSearchEngineId
            )
        }
        
        // Set current provider
        appState.setCurrentProvider(selectedProvider)
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
                    InfoRow(label: "Model", value: "Qwen2.5-7B-Instruct-1M (4-bit Quantized)")
                    InfoRow(label: "Size", value: "~8GB")
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
