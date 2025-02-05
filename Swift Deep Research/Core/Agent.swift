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
    let stepSleep: UInt64         // in nanoseconds
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
    let webReaderService: WebReaderServiceProtocol
    let llmProvider: LLMProviderProtocol
    
    // MARK: - Agent Config and State
    private let config: AgentConfiguration
    private var diary = AgentDiary()
    private var gaps: [String] = []              // pending questions/subqueries
    private var visitedURLs: Set<URL> = []         // to avoid re-visiting pages
    
    // Keep track of token usage
    private var tokenUsage = 0
    
    init(searchService: SearchServiceProtocol,
         webReaderService: WebReaderServiceProtocol,
         llmProvider: LLMProviderProtocol,
         config: AgentConfiguration = AgentConfiguration(
            stepSleep: 1_000_000_000,  // 1 sec pause between iterations
            maxAttempts: 3,
            tokenBudget: 1_000_000
         )
    ) {
        self.searchService = searchService
        self.webReaderService = webReaderService
        self.llmProvider = llmProvider
        self.config = config
    }
    
    // Main workflow method.
    mutating func getResponse(for question: String, maxBadAttempts: Int = 3) async throws -> String {
        // RESET state
        gaps = [question]
        diary = AgentDiary()
        diary.add("Starting research for: \(question)")
        visitedURLs = []
        tokenUsage = 0
        var badAttempts = 0
        
        // INITIAL: Generate multiple search queries from the original question.
        let initialQueries = try await generateSearchQueries(for: question)
        if !initialQueries.contains(question) { gaps.insert(contentsOf: initialQueries, at: 0) }
        
        while true {
            try await Task.sleep(nanoseconds: config.stepSleep)
            if Task.isCancelled { throw CancellationError() }
            
            // If no pending gaps, re-add the original question.
            let currentQuestion = gaps.isEmpty ? question : gaps.removeFirst()
            diary.add("Processing: \(currentQuestion)")
            
            // STEP 1: Concurrently search for all queries in this round.
            let searchResults = try await fetchConcurrentSearchResults(for: currentQuestion)
            guard !searchResults.isEmpty else {
                throw ResearchError.noSearchResults
            }
            
            // STEP 2: Filter out already visited URLs.
            let unvisitedResults = searchResults.filter { !visitedURLs.contains($0.url) }
            if unvisitedResults.isEmpty {
                diary.add("All URLs already processed for query: \(currentQuestion)")
                continue
            }
            
            // Mark these URLs as visited.
            unvisitedResults.forEach { visitedURLs.insert($0.url) }
            diary.add("Collected \(unvisitedResults.count) new URL(s)")
            
            // STEP 3: Concurrently fetch and extract webpage contents using improved approach.
            let webpages = try await fetchWebpagesContent(from: unvisitedResults)
            // Use aggregated content from all pages.
            let aggregatedContent = webpages.joined(separator: "\n\n")
            diary.add("Aggregated content from \(webpages.count) webpage(s)")
            
            // STEP 4: Build prompt with aggregated content and diary log.
            let prompt = buildPrompt(
                for: currentQuestion,
                aggregatedContent: aggregatedContent,
                diaryLog: diary.entries,
                references: visitedURLs.map { $0.absoluteString }
            )
            diary.add("Built comprehensive prompt for LLM.")
            
            // STEP 5: Check token usage before invoking LLM.
            if tokenUsage > config.tokenBudget {
                throw ResearchError.tokenBudgetExceeded(currentUsage: tokenUsage, budget: config.tokenBudget)
            }
            
            // STEP 6: Invoke LLM with the prompt.
            let rawResponse = try await llmProvider.processText(
                systemPrompt: "You are an advanced research assistant.",
                userPrompt: prompt,
                streaming: true
            )
            diary.add("Received response from LLM.")
            tokenUsage += rawResponse.count
            
            let parseResult = LLMResponseParser.parse(from: rawResponse)
            switch parseResult {
            case .failure(let error):
                diary.add("Parsing error: \(error.localizedDescription)")
                throw ResearchError.invalidLLMResponse(rawResponse)
            case .success(let response):
                diary.add("LLM action: \(response.action), Thoughts: \(response.thoughts)")
                
                switch response.action.lowercased() {
                case "answer":
                    if let finalAnswer = response.answer, !finalAnswer.isEmpty {
                        diary.add("Answer action received. Evaluating definitiveness...")
                        if isDefinitive(answer: finalAnswer) || finalAnswer.count > 20 {
                            diary.add("Answer is considered definitive enough.")
                            // Append references (the list of visited URLs) as citations.
                            let references = visitedURLs.map { $0.absoluteString }
                            let citationText = references.isEmpty ? "" : "\n\nSources:\n" + references.joined(separator: "\n")
                            return finalAnswer + citationText
                        } else {
                            diary.add("Answer short/ambiguous; continuing research.")
                            badAttempts += 1
                        }
                    } else {
                        diary.add("Answer action returned empty answer.")
                        badAttempts += 1
                    }
                case "reflect":
                    if let subQuestions = response.questionsToAnswer, !subQuestions.isEmpty {
                        diary.add("LLM requested reflection, adding sub-questions: \(subQuestions)")
                        gaps.append(contentsOf: subQuestions)
                    } else {
                        diary.add("LLM reflection did not yield sub-questions; reusing current question.")
                        gaps.append(currentQuestion)
                    }
                    badAttempts += 1
                case "search":
                    if let query = response.searchQuery, !query.isEmpty {
                        diary.add("LLM requested a new search: \(query)")
                        gaps.insert(query, at: 0)
                    } else {
                        diary.add("LLM returned empty search query; reusing current question.")
                        gaps.append(currentQuestion)
                    }
                    badAttempts += 1
                default:
                    diary.add("Received unknown action: \(response.action).")
                    badAttempts += 1
                }
            }
            
            if badAttempts >= maxBadAttempts {
                diary.add("Exceeded max bad attempts; triggering beast mode.")
                let beastAnswer = try await beastModeAnswer(for: question)
                let references = visitedURLs.map { $0.absoluteString }
                let citationText = references.isEmpty ? "" : "\n\nSources:\n" + references.joined(separator: "\n")
                return beastAnswer + citationText
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private mutating func generateSearchQueries(for question: String) async throws -> [String] {
        let prompt = """
        Given the research topic:
        "\(question)"
        Generate up to four distinct and specific search queries that could help gather evidence and details to answer the question.
        Respond in valid JSON format as:
        {
          "queries": ["query one", "query two", "query three", "query four"]
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
            diary.add("Generated \(queryResponse.queries.count) search query(ies) from LLM.")
            return queryResponse.queries.filter { !$0.isEmpty }
        } else {
            diary.add("Falling back to original question as search query.")
            return [question]
        }
    }
    
    private mutating func fetchConcurrentSearchResults(for query: String) async throws -> [SearchResult] {
        var aggregatedResults: [SearchResult] = []
        let searchQueries = [query]
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for query in searchQueries {
                group.addTask { [searchService] in
                    return try await searchService.search(query: query)
                }
            }
            for try await results in group {
                aggregatedResults.append(contentsOf: results)
            }
        }
        // Deduplicate by URL.
        var uniqueResults: [SearchResult] = []
        var seenURLs = Set<URL>()
        for result in aggregatedResults {
            if !seenURLs.contains(result.url) {
                seenURLs.insert(result.url)
                uniqueResults.append(result)
            }
        }
        diary.add("Fetched and deduplicated \(uniqueResults.count) search result(s).")
        return uniqueResults
    }
    
    // Uses the enhanced web scraping that first parses the HTML with SwiftSoup,
    // removes unwanted tags, and then extracts content from <article> or <main> (falling back to the body).
    private mutating func fetchWebpagesContent(from results: [SearchResult]) async throws -> [String] {
        var webpages: [String] = []
        try await withThrowingTaskGroup(of: String.self) { group in
            for result in results {
                group.addTask { [webReaderService] in
                    // First, try to extract content via our improved extraction.
                    let stripped = try await webReaderService.fetchContent(from: result.url)
                    let minContentLength = 100
                    if stripped.count < minContentLength {
                        // if too short, try to fetch raw HTML and then strip tags.
                        let data = try Data(contentsOf: result.url)
                        let html = String(data: data, encoding: .utf8) ?? stripped
                        return html.strippingHTMLTags()
                    }
                    return stripped
                }
            }
            for try await content in group {
                diary.add("Fetched content from one webpage.")
                webpages.append(content)
            }
        }
        return webpages
    }
    
    private func buildPrompt(for question: String,
                             aggregatedContent: String,
                             diaryLog: [String],
                             references: [String]) -> String {
        let currentDate = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        let jsonExample = """
        {
          "action": "answer",
          "thoughts": "Explain your reasoning and extract necessary details.",
          "searchQuery": "",
          "questionsToAnswer": [],
          "answer": "Your final answer here. Provide concrete details.",
          "references": [
            {"exactQuote": "A relevant quote if any", "url": "https://example.com"}
          ]
        }
        """
        let prompt = """
        Current date: \(currentDate)
        
        You are an advanced research assistant with multi-step reasoning. Your goal is to answer the question definitively based solely on the provided content. Extract relevant information and provide a clear, concise answer with a short explanation. Always include the extracted answer rather than referring to external sources.
        
        ## Question:
        \(question)
        
        ## Aggregated Webpage Content:
        \(aggregatedContent)
        
        ## Research Diary:
        \(diaryLog.joined(separator: "\n"))
        
        ## References:
        \(references.joined(separator: "\n"))
        
        ## Instructions:
        Based on the above, please provide one of the following actions:
          - "search": Provide a new search query if additional information is required.
          - "reflect": Provide sub-questions if further reasoning is needed.
          - "answer": Provide a definitive answer with the extracted information.
        
        Respond strictly in valid JSON matching the schema:
        \(jsonExample)
        """
        return prompt
    }
    
    private func isDefinitive(answer: String) -> Bool {
        let lower = answer.lowercased()
        if lower.contains("i don't know") ||
            lower.contains("unsure") ||
            lower.contains("not available") {
            return false
        }
        return answer.count > 30
    }
    
    private mutating func beastModeAnswer(for question: String) async throws -> String {
        let accumulatedDiary = diary.log()
        let prompt = """
        **Beast Mode Activated**
        
        You have attempted multiple iterations without producing a definitive answer. Based on the accumulated research context below, please provide your best educated, final answer to the question:
        
        \(question)
        
        ## Accumulated Context:
        \(accumulatedDiary)
        
        Your answer must be definitive and succinct.
        """
        let finalAnswer = try await llmProvider.processText(
            systemPrompt: "You are a research assistant (beast mode).",
            userPrompt: prompt,
            streaming: true
        )
        diary.add("Beast mode answer generated.")
        return finalAnswer
    }
}

