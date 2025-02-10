import Foundation

// Error definitions for the research process.
enum ResearchError: LocalizedError {
    case noSearchResults
    case tokenBudgetExceeded(currentUsage: Int, budget: Int)
    case invalidLLMResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .noSearchResults:
            return "No search results found. Please try a different or more specific query."
        case .tokenBudgetExceeded(let current, let budget):
            return "Token budget would be exceeded: \(current) > \(budget)"
        case .invalidLLMResponse(let message):
            return "LLM response could not be parsed: \(message)"
        }
    }
}

// Agent configuration for tuning parameters.
struct AgentConfiguration {
    let stepSleep: UInt64  // in nanoseconds
    let maxAttempts: Int
    let tokenBudget: Int
}

// The Agent state logs internal diary events.
struct AgentDiary {
    private(set) var entries: [String] = []
    
    mutating func add(_ entry: String) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let timestamp = formatter.string(from: Date())
        entries.append("[\(timestamp)] " + entry)
    }
    
    func log() -> String {
        entries.joined(separator: "\n")
    }
}

// The Agent orchestrates web search, content extraction, LLM reasoning, and iterative research.
@MainActor
struct Agent {
    
    // MARK: - Dependencies
    let searchService: SearchServiceProtocol
    let webReaderService: ContentExtractor 
    let llmProvider: LLMProviderProtocol
    
    // MARK: - Agent Config and State
    private let config: AgentConfiguration
    private var diary = AgentDiary()
    private var gaps: [String] = []
    private var visitedURLs: Set<URL> = []
    
    private var tokenUsage = 0
    
    init(searchService: SearchServiceProtocol,
         webReaderService: ContentExtractor,
         llmProvider: LLMProviderProtocol,
         config: AgentConfiguration = AgentConfiguration(
            stepSleep: 1_000_000_000,  // 1 second
            maxAttempts: 3,
            tokenBudget: 1_000_000
         )
    ) {
        self.searchService = searchService
        self.webReaderService = webReaderService
        self.llmProvider = llmProvider
        self.config = config
    }
    
    // Main workflow method
    mutating func getResponse(for question: String,
                              maxBadAttempts: Int = 5) async throws -> String {
        // Reset state
        gaps = [question]
        diary = AgentDiary()
        diary.add("Starting research for: \(question)")
        visitedURLs = []
        tokenUsage = 0
        
        var badAttempts = 0
        
        // Generate initial search queries using LLM
        let initialQueries = try await generateSearchQueries(for: question)
        if !initialQueries.isEmpty, !initialQueries.contains(question) {
            gaps.insert(contentsOf: initialQueries, at: 0)
            diary.add("Generated initial search queries: \(initialQueries)")
        }
        
        // answers
        var candidateAnswers: [String] = []
        
        while true {
            try await Task.sleep(nanoseconds: config.stepSleep)
            if Task.isCancelled { throw CancellationError() }
            
            // If no pending gaps, re-add the original question.
            let currentQuestion = gaps.isEmpty ? question : gaps.removeFirst()
            diary.add("Processing query: \(currentQuestion)")
            
            // 1) Perform search
            let searchResults = try await fetchConcurrentSearchResults(for: currentQuestion)
            guard !searchResults.isEmpty else {
                diary.add("No search results for query: \(currentQuestion)")
                throw ResearchError.noSearchResults
            }
            
            // 2) Filter out already visited URLs
            let unvisitedResults = searchResults.filter { !visitedURLs.contains($0.url) }
            if unvisitedResults.isEmpty {
                diary.add("All URLs already visited for query: \(currentQuestion)")
                gaps.append(currentQuestion)
                continue
            }
            unvisitedResults.forEach { visitedURLs.insert($0.url) }
            diary.add("Collected \(unvisitedResults.count) new URL(s) for query: \(currentQuestion)")
            
            // 3) Fetch webpage contents concurrently using your content extractor factory.
            let webpages = try await fetchWebpagesContent(from: unvisitedResults)
            
            let aggregatedContent = webpages.joined(separator: "\n\n")
            diary.add("Aggregated content from \(webpages.count) webpage(s)")
            
            
            // 4) Build the prompt including chain-of-thought context with enhanced instructions.
            let prompt = buildPrompt(
                for: currentQuestion,
                aggregatedContent: aggregatedContent,
                diaryLog: diary.entries,
                references: visitedURLs.map { $0.absoluteString }
            )
            diary.add("Built prompt for LLM.")
            
            // 5) Token usage check
            tokenUsage += prompt.count
            if tokenUsage > config.tokenBudget {
                diary.add("Token budget exceeded: \(tokenUsage) > \(config.tokenBudget)")
                throw ResearchError.tokenBudgetExceeded(currentUsage: tokenUsage, budget: config.tokenBudget)
            }
            
            // 6) Invoke LLM with the constructed prompt
            let rawResponse = try await llmProvider.processText(
                systemPrompt: "You are an advanced research assistant with deep chain-of-thought reasoning.",
                userPrompt: prompt,
                streaming: true
            )
            
            // Print the AI response to the console for debugging.
            print("AI response: \(rawResponse)")
            
            diary.add("Received LLM response.")
            tokenUsage += rawResponse.count  // simplistic token usage addition
            
            // Parse LLM response.
            let parseResult = LLMResponseParser.parse(from: rawResponse)
            switch parseResult {
            case .failure(let error):
                diary.add("Parsing error: \(error.localizedDescription)")
                throw ResearchError.invalidLLMResponse(rawResponse)
                
            case .success(let response):
                diary.add("LLM response action: \(response.action), Thoughts: \(response.thoughts)")
                
                switch response.action.lowercased() {
                case "answer":
                    if let finalAnswer = response.answer, !finalAnswer.isEmpty {
                        diary.add("Answer received: \(finalAnswer)")
                        let refinedAnswer = try await reflectionStepIfNeeded(finalAnswer)
                        if isDefinitive(answer: refinedAnswer) || refinedAnswer.count > 50 {
                            diary.add("Definitive answer found: \(refinedAnswer)")
                            print("Definitive answer found: \(refinedAnswer)")
                            // Append to candidate answers
                            candidateAnswers.append(refinedAnswer)
                            // Instead of returning here, do NOT break out of the loop immediately.
                        } else {
                            diary.add("Answer was ambiguous or too short, increasing badAttempts.")
                            badAttempts += 1
                        }
                    } else {
                        diary.add("Empty answer received, increasing badAttempts.")
                        badAttempts += 1
                    }
                    
                case "reflect":
                    if let subQuestions = response.questionsToAnswer, !subQuestions.isEmpty {
                        diary.add("Reflection action received with sub-questions: \(subQuestions)")
                        gaps.append(contentsOf: subQuestions)
                    } else {
                        diary.add("Reflection action but no sub-questions provided; reusing current query.")
                        gaps.append(currentQuestion)
                    }
                    badAttempts += 1
                    
                case "search":
                    if let query = response.searchQuery, !query.isEmpty {
                        diary.add("LLM requested new search query: \(query)")
                        gaps.insert(query, at: 0)
                    } else {
                        diary.add("Empty search query received; reusing current query.")
                        gaps.append(currentQuestion)
                    }
                    badAttempts += 1
                    
                default:
                    diary.add("Unknown action '\(response.action)'; counting as bad attempt.")
                    badAttempts += 1
                }
                
                if gaps.isEmpty {
                    print("All URLs processed. Candidate answers so far: \(candidateAnswers)")
                    // Choose the best candidate (for example, the last one or by some ranking)
                    if let bestAnswer = candidateAnswers.last, !bestAnswer.isEmpty {
                        let referencesText = visitedURLs.isEmpty ? "" :
                        "\n\nSources:\n" + visitedURLs.map { $0.absoluteString }.joined(separator: "\n")
                        return bestAnswer + referencesText
                    } else {
                        diary.add("No definitive candidate found; triggering Beast Mode.")
                        let beastAnswer = try await beastModeAnswer(for: question)
                        let referencesText = visitedURLs.isEmpty ? "" :
                        "\n\nSources:\n" + visitedURLs.map { $0.absoluteString }.joined(separator: "\n")
                        return beastAnswer + referencesText
                    }
                }
            }
            
            // For debugging: print out the current candidate answers so far.
            print("Candidate answers so far: \(candidateAnswers)")
            
            // If the loop has run for a set number of iterations (or if gaps become empty)
            // you might decide to break out and return the best candidate.
            if badAttempts >= maxBadAttempts || gaps.isEmpty {
                if let bestAnswer = candidateAnswers.last, !bestAnswer.isEmpty {
                    let referencesText = visitedURLs.isEmpty ? "" :
                    "\n\nSources:\n" + visitedURLs.map { $0.absoluteString }.joined(separator: "\n")
                    return bestAnswer + referencesText
                } else {
                    diary.add("Exceeded maximum bad attempts; triggering Beast Mode.")
                    let beastAnswer = try await beastModeAnswer(for: question)
                    let referencesText = visitedURLs.isEmpty ? "" :
                    "\n\nSources:\n" + visitedURLs.map { $0.absoluteString }.joined(separator: "\n")
                    return beastAnswer + referencesText
                }
            }
        }
    }
    
    // Generates initial search queries using LLM
    private mutating func generateSearchQueries(for question: String) async throws -> [String] {
        let prompt = """
        You are a research query generator. Given the topic:
        "\(question)"
        Generate up to four distinct, non-redundant search queries that can be used to gather more information. Return the output in valid JSON format:
        {
          "queries": ["query1", "query2", "query3", "query4"]
        }
        """
        let rawResponse = try await llmProvider.processText(
            systemPrompt: "You are a research query generator.",
            userPrompt: prompt,
            streaming: false
        )
        struct QueryResponse: Codable { let queries: [String] }
        if let data = rawResponse.data(using: .utf8),
           let queryResponse = try? JSONDecoder().decode(QueryResponse.self, from: data) {
            return queryResponse.queries.filter { !$0.isEmpty }
        } else {
            diary.add("Failed to generate search queries via LLM; defaulting to original question.")
            return [question]
        }
    }
    
    // Fetches search results concurrently for a given query.
    private mutating func fetchConcurrentSearchResults(for query: String) async throws -> [SearchResult] {
        var allResults: [SearchResult] = []
        let searchQueries = [query]
        
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for q in searchQueries {
                group.addTask { [localSearchService = self.searchService] in
                    return try await localSearchService.search(query: q)
                }
            }
            for try await partial in group {
                allResults.append(contentsOf: partial)
            }
        }
        
        // Deduplicate results
        var unique: [SearchResult] = []
        var seen = Set<URL>()
        for res in allResults {
            if !seen.contains(res.url) {
                seen.insert(res.url)
                unique.append(res)
            }
        }
        return unique
    }
    
    // Fetches webpage content concurrently from search results using a content extractor factory.
    private mutating func fetchWebpagesContent(from results: [SearchResult]) async throws -> [String] {
        var contents: [String] = []
        var localDiary = self.diary // Create local copy
        try await withThrowingTaskGroup(of: String.self) { group in
            for r in results {
                // Resolve the final URL from the DuckDuckGo redirect.
                let finalURL = ContentExtractionFactory.resolveRedirect(for: r.url)
                // Create extractor based on the resolved URL.
                let extractor = ContentExtractionFactory.createExtractor(for: finalURL)
                group.addTask {
                    do {
                        return try await extractor.extractContent(from: finalURL)
                    } catch {
                        localDiary.add("Failed to extract content from \(finalURL.absoluteString): \(error.localizedDescription)")
                        return ""
                    }
                }
            }
            for try await content in group {
                if !content.isEmpty {
                    contents.append(content)
                }
            }
        }
        return contents
    }
    
    // Builds the prompt for the LLM using the current query, aggregated content, and diary log.
    private func buildPrompt(for question: String,
                             aggregatedContent: String,
                             diaryLog: [String],
                             references: [String]) -> String {
        let currentDate = DateFormatter.localizedString(from: Date(),
                                                        dateStyle: .medium,
                                                        timeStyle: .medium)
        
        let prompt = """
        Current date: \(currentDate)
        
        You are an advanced research assistant with expertise in deep, multi-step research and analysis. Your task is to answer the following question using **only** the aggregated content provided below and your internal research diary. Provide a detailed, step-by-step chain-of-thought explanation of how you arrived at your answer, including specific evidence (exact quotes when appropriate) from the content. Do not add any information that is not supported by the data.
        
        ## Question:
        \(question)
        
        ## Aggregated Content:
        \(aggregatedContent)
        
        ## Research Diary:
        \(diaryLog.joined(separator: "\n"))
        
        ## References:
        \(references.joined(separator: "\n"))
        
        Provide your output in valid JSON format strictly following the schema below. Do not include any additional commentary.
        
        Schema:
        {
          "action": "answer" | "search" | "reflect",
          "thoughts": "Your internal chain-of-thought reasoning process.",
          "searchQuery": "If action is search, provide a new query to search for missing information.",
          "questionsToAnswer": ["If action is reflect, list sub-questions to explore."],
          "answer": "Final, detailed answer if action is answer.",
          "references": [{"exactQuote": "Relevant snippet", "url": "URL of the source"}]
        }
        """
        return prompt
    }
    
    // Checks if the answer is definitive.
    private func isDefinitive(answer: String) -> Bool {
        let lower = answer.lowercased()
        if lower.contains("i don't know") ||
            lower.contains("unsure") ||
            lower.contains("not available") {
            return false
        }
        return answer.count > 30
    }
    
    // Reflection step: if the answer is too short or ambiguous, request LLM to expand it.
    private mutating func reflectionStepIfNeeded(_ answer: String) async throws -> String {
        guard answer.count < 40 else { return answer }
        diary.add("Triggering reflection due to short or ambiguous answer.")
        
        let reflectPrompt = """
        The current answer is: \(answer)
        
        Review the aggregated content and the research diary below.
        Use the provided content to expand your answer with detailed, step-by-step reasoning and supporting evidence. Your final answer must be comprehensive and based solely on the available data.
        
        Research Diary:
        \(diary.entries.joined(separator: "\n"))
        """
        
        let improved = try await llmProvider.processText(
            systemPrompt: "You are a thorough and accurate research assistant.",
            userPrompt: reflectPrompt,
            streaming: false
        )
        diary.add("Reflection step produced an expanded answer.")
        return improved
    }
    
    // Beast mode: if multiple attempts have failed, provide a best-effort answer.
    private mutating func beastModeAnswer(for question: String) async throws -> String {
        let logs = diary.log()
        let prompt = """
        Beast Mode Activated:
        Despite multiple attempts, a definitive answer has not been reached.
        
        Based on the following research diary and aggregated content, provide your best final answer. Ensure your answer is detailed, includes step-by-step reasoning, and cites specific evidence from the data.
        
        Question: \(question)
        
        Research Diary:
        \(logs)
        """
        let finalAnswer = try await llmProvider.processText(
            systemPrompt: "You are in Beast Mode. Provide your best possible answer now with full supporting details.",
            userPrompt: prompt,
            streaming: true
        )
        diary.add("Beast mode produced a final answer.")
        return finalAnswer
    }
}
