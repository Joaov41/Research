import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isResearching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showSettings: Bool = false
    @Published var steps: [AgentStep] = []
    @Published var isFollowUpMode: Bool = false
    @Published var selectedMessageId: UUID? = nil

    let searchService: SearchServiceProtocol
    let webReaderService: ContentExtractor
    private var llmProvider: LLMProviderProtocol
    
    init(searchService: SearchServiceProtocol,
         webReaderService: ContentExtractor,
         llmProvider: LLMProviderProtocol) {
        self.searchService = searchService
        self.webReaderService = webReaderService
        self.llmProvider = llmProvider
    }
    
    /// Updates the LLM provider when the active provider changes
    func updateLLMProvider(_ newProvider: LLMProviderProtocol) {
        self.llmProvider = newProvider
        // Optionally notify user of provider change
        messages.append(ChatMessage(
            text: "Switched to \(newProvider is LocalLLMProvider ? "Local LLM" : "Gemini AI")",
            isUser: false
        ))
    }
    
    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let messageContext: ChatMessage.MessageContext = 
            if let selectedId = selectedMessageId {
                .followUp(originalMessageId: selectedId)
            } else {
                .initial
            }
        
        let userMessage = ChatMessage(text: trimmed, isUser: true, context: messageContext)
        messages.append(userMessage)
        inputText = ""
        isResearching = true
        errorMessage = nil
        
        Task {
            do {
                if case .followUp(let originalId) = messageContext,
                   let originalMessage = messages.first(where: { $0.id == originalId }) {
                    // Handle follow-up question using stored research
                    let answer = try await handleFollowUpQuestion(
                        question: trimmed,
                        originalContext: originalMessage.text,
                        messageContext: messageContext
                    )
                    messages.append(ChatMessage(
                        text: answer,
                        isUser: false,
                        context: .answer,
                        researchContext: originalMessage.researchContext
                    ))
                } else {
                    // Only do full research for initial questions
                    var agent = Agent(
                        searchService: searchService,
                        webReaderService: webReaderService,
                        llmProvider: llmProvider
                    )
                    let answer = try await agent.getResponse(for: trimmed)
                    messages.append(ChatMessage(
                        text: answer,
                        isUser: false,
                        context: .initial,
                        researchContext: ChatMessage.ResearchContext(
                            aggregatedContent: agent.lastAggregatedContent,
                            searchResults: agent.lastSearchResults,
                            references: agent.visitedURLs.map { $0.absoluteString }
                        )
                    ))
                }
            } catch {
                errorMessage = error.localizedDescription
                messages.append(ChatMessage(
                    text: "Error: \(error.localizedDescription)",
                    isUser: false,
                    context: .answer
                ))
            }
            isResearching = false
            isFollowUpMode = false
            selectedMessageId = nil
        }
    }
    
    private func handleFollowUpQuestion(
        question: String, 
        originalContext: String,
        messageContext: ChatMessage.MessageContext
    ) async throws -> String {
        if case .followUp(let originalId) = messageContext,
           let originalMessage = messages.first(where: { $0.id == originalId }),
           let researchContext = originalMessage.researchContext {
            
            let prompt = """
            You are analyzing previous research to answer a follow-up question.
            
            Original research content:
            \(researchContext.aggregatedContent)
            
            Previous answer:
            \(originalMessage.text)
            
            Follow-up question:
            \(question)
            
            Important instructions:
            1. Only use information from the original research content above
            2. DO NOT perform any new searches
            3. If asked to elaborate on a specific point, focus on that point from the research
            4. If the question cannot be answered using only this research, explicitly state that
            5. Maintain the same level of academic rigor as the original response
            
            Please provide your response:
            """
            
            return try await llmProvider.processText(
                systemPrompt: "You are a research assistant analyzing existing research only - do not seek new information.",
                userPrompt: prompt,
                streaming: true
            )
        } else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find original research context"])
        }
    }
    
    func addStep(description: String,
                 partialAnswer: String? = nil,
                 references: [String] = [],
                 isUserQuery: Bool = false) {
        let step = AgentStep(
            stepDescription: description,
            partialAnswer: partialAnswer,
            references: references,
            isUserQuery: isUserQuery
        )
        steps.append(step)
    }
    
    func restartResearch() {
        messages.removeAll()
        inputText = ""
        isResearching = false
        errorMessage = nil
        isFollowUpMode = false
        selectedMessageId = nil
        steps.removeAll()
    }
}
