import SwiftUI

enum LLMType: String, CaseIterable, Identifiable {
    case local = "Local LLM"
    case gemini = "Gemini"
    
    var id: String { self.rawValue }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // LLM Providers
    @Published var localLLMProvider: LocalLLMProvider
    @Published var geminiProvider: GeminiProvider
    
    // Search Services
    private var googleSearchService: GoogleSearchService?
    var searchService: SearchServiceProtocol
    
    // Current provider with UI binding support
    @Published private(set) var currentProvider: String
    
    // UI State
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    
    private init() {
        let asettings = AppSettings.shared
        self.currentProvider = asettings.currentProvider
        
        // Initialize search services
        if !asettings.googleApiKey.isEmpty && !asettings.googleSearchEngineId.isEmpty {
            do {
                self.googleSearchService = try GoogleSearchService(
                    apiKey: asettings.googleApiKey,
                    searchEngineId: asettings.googleSearchEngineId
                )
                self.searchService = CompositeSearchService(services: [
                    googleSearchService!,
                    SearchService() // DuckDuckGo fallback
                ])
            } catch {
                print("Failed to initialize Google Search: \(error)")
                self.searchService = SearchService() // Fallback to DuckDuckGo
            }
        } else {
            print("No Google Search credentials found - using DuckDuckGo only")
            self.searchService = SearchService() // Default to DuckDuckGo
        }
        
        // Initialize Gemini
        let geminiConfig = GeminiConfig(
            apiKey: asettings.geminiApiKey,
            modelName: asettings.geminiModel.rawValue
        )
        self.geminiProvider = GeminiProvider(config: geminiConfig)
        
        // Initialize local LLM Provider
        self.localLLMProvider = LocalLLMProvider()
    }
    
    /// Returns the active LLMProvider based on current selection
    var activeLLMProvider: LLMProviderProtocol {
        switch currentProvider {
            case "local": return localLLMProvider
            case "gemini": return geminiProvider
            default: return geminiProvider // Default to Gemini if unknown
        }
    }
    
    func setCurrentProvider(_ provider: String) {
        currentProvider = provider
        AppSettings.shared.currentProvider = provider
        objectWillChange.send()
    }
    
    /// Updates Gemini configuration when settings change
    func saveGeminiConfig(apiKey: String, model: GeminiModel) {
        AppSettings.shared.geminiApiKey = apiKey
        AppSettings.shared.geminiModel = model
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
        geminiProvider = GeminiProvider(config: config)
    }
    
    func updateGoogleSearchConfig(apiKey: String, searchEngineId: String) {
        AppSettings.shared.googleApiKey = apiKey
        AppSettings.shared.googleSearchEngineId = searchEngineId
        
        if !apiKey.isEmpty && !searchEngineId.isEmpty {
            self.googleSearchService = GoogleSearchService(
                apiKey: apiKey,
                searchEngineId: searchEngineId
            )
            self.searchService = CompositeSearchService(services: [
                googleSearchService!,
                SearchService() // DuckDuckGo fallback
            ])
        } else {
            self.searchService = SearchService() // Fallback to DuckDuckGo
        }
    }
}
