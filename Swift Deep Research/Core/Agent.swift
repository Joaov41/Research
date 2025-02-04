import Foundation

/// Error definitions for the research process.
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

/// Agent configuration for tuning parameters.
struct AgentConfiguration {
    let stepSleep: UInt64         // in nanoseconds
    let maxAttempts: Int
    let tokenBudget: Int
}

/// The Agent state logs internal diary events.
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

/// The Agent orchestrates web search, content extraction, LLM reasoning, and iterative research.
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
    
    /// Keep track of token usage (as an example, this counter should be updated based on your LLM metrics)
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
    
    /// Main workflow method.
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
                // If no more unvisited, continue with next query.
                continue
            }
            
            // Mark these URLs as visited.
            unvisitedResults.forEach { visitedURLs.insert($0.url) }
            diary.add("Collected \(unvisitedResults.count) new URL(s)")
            
            // STEP 3: Concurrently fetch webpage contents.
            let webpages = try await fetchWebpagesContent(from: unvisitedResults)
            // Use aggregated content from all pages.
            let aggregatedContent = webpages.joined(separator: "\n\n")
            diary.add("Aggregated content from \(webpages.count) webpage(s)")
            
            // STEP 4: Build prompt with aggregated content and diary log.
            // Note: We add the full diary log so that context and previous iterations are passed along.
            let prompt = buildPrompt(
                for: currentQuestion,
                aggregatedContent: aggregatedContent,
                withDiary: diary.entries
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
            // Increase token usage counter (using the character count as a proxy for tokens)
            tokenUsage += rawResponse.count
            
            let parseResult = LLMResponseParser.parse(from: rawResponse)
            switch parseResult {
            case .failure(let error):
                diary.add("Parsing error: \(error.localizedDescription)")
                throw ResearchError.invalidLLMResponse(rawResponse)
            case .success(let response):
                diary.add("LLM action: \(response.action), Thoughts: \(response.thoughts)")
                
                // Dispatch based on action:
                switch response.action.lowercased() {
                case "answer":
                    // Updated: if answer is nonempty we allow slight ambiguity.
                    if let finalAnswer = response.answer, !finalAnswer.isEmpty {
                        diary.add("Answer action received. Evaluating definitiveness...")
                        // Evaluate answer decisiveness based on our new heuristic (see isDefinitive below).
                        if isDefinitive(answer: finalAnswer) || finalAnswer.count > 20 {
                            diary.add("Answer is considered definitive enough.")
                            return finalAnswer
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
            
            // If too many unsuccessful attempts, trigger beast mode.
            if badAttempts >= maxBadAttempts {
                diary.add("Exceeded max bad attempts; triggering beast mode.")
                let beastAnswer = try await beastModeAnswer(for: question)
                return beastAnswer
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Ask the LLM to generate multiple distinct search queries based on the original topic.
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
            return queryResponse.queries
        } else {
            diary.add("Falling back to original question as search query.")
            return [question]
        }
    }
    
    /// Concurrently fetch search results for a given query.
    private mutating func fetchConcurrentSearchResults(for query: String) async throws -> [SearchResult] {
        var aggregatedResults: [SearchResult] = []
        
        let searchQueries = [query] // Can be extended if needed.
        
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
        
        // Deduplicate results by URL.
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
    
    /// Concurrently fetch webpage content from the given search results.
    private mutating func fetchWebpagesContent(from results: [SearchResult]) async throws -> [String] {
        var webpages: [String] = []
        try await withThrowingTaskGroup(of: (URL, String).self) { group in
            for result in results {
                group.addTask { [webReaderService] in
                    // Try to fetch content. If the stripped content is too short, return the raw HTML.
                    let content = try await webReaderService.fetchContent(from: result.url)
                    let minContentLength = 30
                    return (result.url, content.count < minContentLength ? String(data: try await Data(contentsOf: result.url), encoding: .utf8) ?? content : content)
                }
            }
            for try await (url, content) in group {
                diary.add("Fetched content from \(url.absoluteString)")
                webpages.append(content)
            }
        }
        return webpages
    }
    
    /// Build a combined prompt for the LLM using current question, aggregated webpage content, and diary log.
    private func buildPrompt(for question: String,
                             aggregatedContent: String,
                             withDiary diaryLog: [String]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let currentDate = dateFormatter.string(from: Date())
        
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
    
    /// Checks whether the given answer is definitive.
    /// (Now: consider answers longer than a threshold or that avoid common hedge phrases as definitive.)
    private func isDefinitive(answer: String) -> Bool {
        let lower = answer.lowercased()
        if lower.contains("i don't know") ||
            lower.contains("unsure") ||
            lower.contains("not available") {
            return false
        }
        // If the answer is sufficiently long, consider it definitive
        return answer.count > 30
    }
    
    /// A heuristic to decide if the answer is concrete and not just a referral to click a link.
    private func isExtractedAnswer(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        // Accept if it does not simply instruct to "visit a website"
        return !lowerText.contains("visit") && !lowerText.contains("go to")
    }
    
    /// In beast mode, use full accumulated context to generate a final answer.
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
