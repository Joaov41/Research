import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isResearching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showSettings: Bool = false

    let searchService: SearchServiceProtocol
    let webReaderService: WebReaderServiceProtocol
    let llmProvider: LLMProviderProtocol
    
    init(searchService: SearchServiceProtocol,
         webReaderService: WebReaderServiceProtocol,
         llmProvider: LLMProviderProtocol) {
        self.searchService = searchService
        self.webReaderService = webReaderService
        self.llmProvider = llmProvider
    }
    
    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        messages.append(ChatMessage(text: trimmed, isUser: true))
        inputText = ""
        isResearching = true
        errorMessage = nil
        messages.append(ChatMessage(text: "Researching...", isUser: false))
        
        Task {
            do {
                // Create a new agent instance with dependencies.
                var agent = Agent(
                    searchService: searchService,
                    webReaderService: webReaderService,
                    llmProvider: llmProvider
                )
                let answer = try await agent.getResponse(for: trimmed, maxBadAttempts: 3)
                // Remove the temporary "Researching..." message.
                if let last = messages.last, last.text == "Researching..." {
                    messages.removeLast()
                }
                messages.append(ChatMessage(text: answer, isUser: false))
            } catch {
                if let last = messages.last, last.text == "Researching..." {
                    messages.removeLast()
                }
                errorMessage = error.localizedDescription
                messages.append(ChatMessage(text: "Error: \(error.localizedDescription)", isUser: false))
            }
            isResearching = false
        }
    }
}
