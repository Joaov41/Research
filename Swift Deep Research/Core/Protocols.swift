import Foundation

// MARK: - Search Service Protocol

protocol SearchServiceProtocol {
    func search(query: String) async throws -> [SearchResult]
}

// MARK: - Web Reader Service Protocol

protocol WebReaderServiceProtocol {
    func fetchContent(from url: URL) async throws -> String
}

// MARK: - LLM Provider Protocol

protocol LLMProviderProtocol {
    var isProcessing: Bool { get }
    func processText(systemPrompt: String?, userPrompt: String,
                     streaming: Bool) async throws -> String
}
