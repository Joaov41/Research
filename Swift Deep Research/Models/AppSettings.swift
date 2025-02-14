import Foundation

// A singleton for app-wide settings that wraps UserDefaults access
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Settings
    @Published var geminiApiKey: String {
        didSet { defaults.set(geminiApiKey, forKey: "gemini_api_key") }
    }
    
    @Published var geminiModel: GeminiModel {
        didSet { defaults.set(geminiModel.rawValue, forKey: "gemini_model") }
    }
    
    /*
    @Published var openAIApiKey: String {
        didSet { defaults.set(openAIApiKey, forKey: "openai_api_key") }
    }
    
    @Published var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: "openai_base_url") }
    }
    
    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: "openai_model") }
    }
    
    @Published var openAIOrganization: String? {
        didSet { defaults.set(openAIOrganization, forKey: "openai_organization") }
    }
    
    @Published var openAIProject: String? {
        didSet { defaults.set(openAIProject, forKey: "openai_project") }
    }*/
    
    @Published var currentProvider: String {
        didSet { defaults.set(currentProvider, forKey: "current_provider") }
    }
    
    /*
    @Published var mistralApiKey: String {
        didSet { defaults.set(mistralApiKey, forKey: "mistral_api_key") }
    }
    
    @Published var mistralBaseURL: String {
        didSet { defaults.set(mistralBaseURL, forKey: "mistral_base_url") }
    }
    
    @Published var mistralModel: String {
        didSet { defaults.set(mistralModel, forKey: "mistral_model") }
    }*/
    
    @Published var googleApiKey: String {
        didSet { defaults.set(googleApiKey, forKey: "google_api_key") }
    }
    
    @Published var googleSearchEngineId: String {
        didSet { defaults.set(googleSearchEngineId, forKey: "google_search_engine_id") }
    }
    
    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        // Load or set defaults
        self.geminiApiKey = defaults.string(forKey: "gemini_api_key") ?? ""
        let geminiModelStr = defaults.string(forKey: "gemini_model") ?? GeminiModel.oneflash.rawValue
        self.geminiModel = GeminiModel(rawValue: geminiModelStr) ?? .oneflash
        
        // Initialize Google Search settings
        self.googleApiKey = defaults.string(forKey: "google_api_key") ?? ""
        self.googleSearchEngineId = defaults.string(forKey: "google_search_engine_id") ?? ""
        
        // Current provider
        self.currentProvider = defaults.string(forKey: "current_provider") ?? "gemini"
        
        /*
        self.openAIApiKey = defaults.string(forKey: "openai_api_key") ?? ""
        self.openAIBaseURL = defaults.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
        self.openAIModel = defaults.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
        self.openAIOrganization = defaults.string(forKey: "openai_organization") ?? nil
        self.openAIProject = defaults.string(forKey: "openai_project") ?? nil
        
        self.mistralApiKey = defaults.string(forKey: "mistral_api_key") ?? ""
        self.mistralBaseURL = defaults.string(forKey: "mistral_base_url") ?? MistralConfig.defaultBaseURL
        self.mistralModel = defaults.string(forKey: "mistral_model") ?? MistralConfig.defaultModel
        
        self.shortcutText = defaults.string(forKey: "shortcut") ?? "⌥ Space"
        self.hasCompletedOnboarding = defaults.bool(forKey: "has_completed_onboarding")
        self.useGradientTheme = defaults.bool(forKey: "use_gradient_theme")
        
        // HotKey
        self.hotKeyCode = defaults.integer(forKey: "hotKey_keyCode")
        self.hotKeyModifiers = defaults.integer(forKey: "hotKey_modifiers")
         */
    }
    
    // MARK: - Convenience
    func resetAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }
}
