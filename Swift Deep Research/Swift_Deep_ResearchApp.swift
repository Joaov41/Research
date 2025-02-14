import SwiftUI
import MLX

@main
struct SwiftDeepResearchApp: App {
    @StateObject private var appState = AppState.shared
    
    init() {
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(ChatViewModel(
                    searchService: appState.searchService,
                    webReaderService: WebContentExtractor.shared,
                    llmProvider: appState.activeLLMProvider
                ))
        }
    }
}

extension WebContentExtractor {
    static let shared = WebContentExtractor()
}
