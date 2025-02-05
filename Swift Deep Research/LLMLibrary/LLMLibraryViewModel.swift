import Foundation
import MLXLLM
import MLXLMCommon
import SwiftUI

// A simple model struct that holds display information and the associated configuration.
struct LLMModelInfo: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let configuration: ModelConfiguration
    
    // Derive the download path from the configuration id.
    var modelPath: String {
        "huggingface/models/\(configuration.id)"
    }
    
    // The directory where the model will be stored.
    var directoryURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(modelPath)
    }
}

// This view model holds the state for a single model card.
class LLMCardViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let modelInfo: LLMModelInfo
    
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloaded: Bool = false
    @Published var lastError: String?
    
    private var downloadTask: Task<Void, Never>? = nil
    private var isCancelled: Bool = false
    
    init(modelInfo: LLMModelInfo) {
        self.modelInfo = modelInfo
        // Check if the model has already been downloaded.
        self.isDownloaded = FileManager.default.fileExists(atPath: modelInfo.directoryURL.path)
    }
    
    // Starts the download using the MLX LLM loading logic.
    func startDownload() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.0
        lastError = nil
        isCancelled = false
        
        downloadTask = Task {
            do {
                let _ = try await LLMModelFactory.shared.loadContainer(configuration: modelInfo.configuration) { [weak self] progress in
                    // Update progress on the main thread.
                    Task { @MainActor in
                        guard let self = self, !self.isCancelled else { return }
                        self.downloadProgress = progress.fractionCompleted
                    }
                }
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                    self.isDownloaded = true
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadProgress = 0.0
                    self.lastError = error.localizedDescription
                }
            }
        }
    }
    
    // Cancels the current download.
    func cancelDownload() {
        isCancelled = true
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        lastError = "Download cancelled"
    }
    
    // Deletes the downloaded model from disk.
    func deleteModel() {
        let directory = modelInfo.directoryURL
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
                DispatchQueue.main.async {
                    self.isDownloaded = false
                    self.lastError = nil
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = "Failed to delete model: \(error.localizedDescription)"
            }
        }
    }
    
    func loadModel() {
        DispatchQueue.main.async {
            AppState.shared.localLLMProvider.modelInfo = "Loaded model: \(self.modelInfo.name)"
        }
    }
}

// A view model that keeps an array of all available LLM cards.
class LLMLibraryViewModel: ObservableObject {
    @Published var cards: [LLMCardViewModel] = []
    
    init() {
        cards = [
            LLMCardViewModel(modelInfo: LLMModelInfo(
                                name: "Mistral Small 24B (4-bit Quantized)",
                                size: "~13GB",
                                configuration: .mistralSmall24B)),
            LLMCardViewModel(modelInfo: LLMModelInfo(
                                name: "Qwen 2.5-7B Instruct (4-bit)",
                                size: "~7GB",
                                configuration: .qwen2_5_7b_1M_4bit))
        ]
    }
}
