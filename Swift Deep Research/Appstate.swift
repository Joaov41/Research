import SwiftUI

enum LLMType: String, CaseIterable, Identifiable {
    case local = "Local LLM"
    case gemini = "Gemini"
    
    var id: String { self.rawValue }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // Currently active provider type.
    @Published var selectedLLMType: LLMType = .local
    
    // Local LLM provider.
    @Published var localLLMProvider: LocalLLMProvider
    
    // Gemini configuration defaults.
    @Published var geminiConfig = GeminiConfig(apiKey: "", modelName: GeminiModel.twoflash.rawValue)
    // Gemini provider (initialized only when needed)
    @Published var geminiProvider: GeminiProvider?
    
    // Other properties
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    
    private init() {
        self.localLLMProvider = LocalLLMProvider()
        // Initialize Gemini provider
        self.geminiProvider = GeminiProvider(config: geminiConfig)
    }
    
    /// Returns the active LLMProvider based on current selection.
    /// ChatViewModel can use this property.
    var activeLLMProvider: LLMProviderProtocol {
        switch selectedLLMType {
        case .local:
            return localLLMProvider
        case .gemini:
            // If geminiProvider is nil, instantiate it with current config.
            if geminiProvider == nil {
                geminiProvider = GeminiProvider(config: geminiConfig)
            }
            return geminiProvider!
        }
    }
    
    /// Call when Gemini configuration is updated in settings.
    func updateGeminiProvider() {
        self.geminiProvider = GeminiProvider(config: geminiConfig)
    }
}
