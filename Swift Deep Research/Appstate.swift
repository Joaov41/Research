import SwiftUI

enum LLMType: String, CaseIterable, Identifiable {
    case local = "Local LLM"
    case gemini = "Gemini"
    
    var id: String { self.rawValue }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    
    // Local LLM provider.
    @Published var localLLMProvider: LocalLLMProvider
    
    @Published var geminiProvider: GeminiProvider

    // Current provider with UI binding support
    @Published private(set) var currentProvider: String
    
    // Other properties
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    
    private init() {
        // Read from AppSettings
        let asettings = AppSettings.shared
        self.currentProvider = asettings.currentProvider
        
        // Initialize Gemini
        let geminiConfig = GeminiConfig(apiKey: asettings.geminiApiKey,
                                        modelName: asettings.geminiModel.rawValue)
        self.geminiProvider = GeminiProvider(config: geminiConfig)
        
        /*
        // Initialize OpenAI
        let openAIConfig = OpenAIConfig(
            apiKey: asettings.openAIApiKey,
            baseURL: asettings.openAIBaseURL,
            organization: asettings.openAIOrganization,
            project: asettings.openAIProject,
            model: asettings.openAIModel
        )
        self.openAIProvider = OpenAIProvider(config: openAIConfig)
        
        // Initialize Mistral
        let mistralConfig = MistralConfig(
            apiKey: asettings.mistralApiKey,
            baseURL: asettings.mistralBaseURL,
            model: asettings.mistralModel
        )
        self.mistralProvider = MistralProvider(config: mistralConfig)
        
        if asettings.openAIApiKey.isEmpty && asettings.geminiApiKey.isEmpty && asettings.mistralApiKey.isEmpty {
            print("Warning: No API keys configured.")
        }*/
        
        // Initialize local LLM Provider
        self.localLLMProvider = LocalLLMProvider()
    }
    
    /// Returns the active LLMProvider based on current selection.
    /// ChatViewModel can use this property.
    var activeLLMProvider: LLMProviderProtocol {
            if currentProvider == "local" {
                return localLLMProvider
            }else {
                return geminiProvider
            }
    }
    
    func setCurrentProvider(_ provider: String) {
        currentProvider = provider
        AppSettings.shared.currentProvider = provider
        objectWillChange.send()  // Explicitly notify observers
    }
    
    /// Call when Gemini configuration is updated in settings.
    func saveGeminiConfig(apiKey: String, model: GeminiModel) {
        AppSettings.shared.geminiApiKey = apiKey
        AppSettings.shared.geminiModel = model
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
        geminiProvider = GeminiProvider(config: config)
    }
}
