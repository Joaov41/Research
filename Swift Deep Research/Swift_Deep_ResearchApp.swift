import SwiftUI
import MLX

@main
struct SwiftDeepResearchApp: App {
    init() {
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ChatViewModel(
                    searchService: SearchService(),
                    webReaderService: WebReaderService(),
                    llmProvider: AppState.shared.activeLLMProvider
                ))
                .environmentObject(AppState.shared)
        }
    }
}
