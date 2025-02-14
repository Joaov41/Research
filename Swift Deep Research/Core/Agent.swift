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
    let stepSleep: UInt64
    let maxAttempts: Int
    let tokenBudget: Int
    let minAnswerLength: Int
    let maxSearchQueries: Int
    let minSources: Int
    
    static let `default` = AgentConfiguration(
        stepSleep: 1_000_000_000,  // 1 second
        maxAttempts: 8,            // Increased to allow more research iterations
        tokenBudget: 8_000_000,    // Increased for longer responses
        minAnswerLength: 4000,     // Minimum 4000 characters (about 800 words)
        maxSearchQueries: 10,      // More search queries for broader coverage
        minSources: 5              // Minimum number of sources to consult
    )
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
class Agent {
    
    // MARK: - Dependencies
    let searchService: SearchServiceProtocol
    let webReaderService: ContentExtractor 
    let llmProvider: LLMProviderProtocol
    
    // MARK: - Agent Config and State
    private let config: AgentConfiguration
    private var diary = AgentDiary()
    private var gaps: [String] = []
    var visitedURLs: Set<URL> = []
    
    private var tokenUsage = 0
    
    // Add properties to store last research context
    private(set) var lastAggregatedContent: String = ""
    private(set) var lastSearchResults: [SearchResult] = []
    
    init(searchService: SearchServiceProtocol,
         webReaderService: ContentExtractor,
         llmProvider: LLMProviderProtocol,
         config: AgentConfiguration = .default) {
        self.searchService = searchService
        self.webReaderService = webReaderService
        self.llmProvider = llmProvider
        self.config = config
    }
    
    // Main workflow method
    func getResponse(for question: String,
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
            self.lastAggregatedContent = aggregatedContent
            self.lastSearchResults = searchResults
            diary.add("Aggregated content from \(webpages.count) webpage(s)")
            
            
            // 4) Build the prompt including chain-of-thought context with enhanced instructions.
            let prompt = buildPrompt(
                for: currentQuestion,
                aggregatedContent: aggregatedContent,
                searchResults: searchResults,
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
                        if isDefinitive(answer: refinedAnswer, references: visitedURLs.map { $0.absoluteString }) || refinedAnswer.count > 50 {
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
    private func generateSearchQueries(for question: String) async throws -> [String] {
        let prompt = """
        You are a research query generator. Given the topic:
        "\(question)"
        Generate up to \(config.maxSearchQueries) distinct, targeted search queries that will help gather comprehensive information. Consider:
        
        1. Different aspects of the topic
        2. Technical and non-technical perspectives
        3. Historical context and current developments
        4. Specific examples or case studies
        5. Expert opinions and research findings
        
        Return the output in valid JSON format:
        {
          "queries": [
            "query1",
            "query2",
            "query3",
            "query4",
            "query5",
            "query6"
          ]
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
    private func fetchConcurrentSearchResults(for query: String) async throws -> [SearchResult] {
        var allResults: [SearchResult] = []
        
        // First try the original query
        do {
            let initialResults = try await searchService.search(query: query)
            allResults.append(contentsOf: initialResults)
            print("📊 Got \(initialResults.count) results from initial query")
        } catch {
            print("⚠️ Error with initial query: \(error)")
        }
        
        // If we don't have enough results, try generated queries
        if allResults.count < 30 {
            let searchQueries = try await generateSearchQueries(for: query)
            print("🔍 Generated additional queries: \(searchQueries)")
            
            for q in searchQueries {
                do {
                    let results = try await searchService.search(query: q)
                    allResults.append(contentsOf: results)
                    print("📊 Got \(results.count) results from query: \(q)")
                    
                    // If we have enough results, stop
                    if allResults.count >= 60 {
                        break
                    }
                    
                    // Add delay between queries
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                } catch {
                    print("⚠️ Error with query '\(q)': \(error)")
                    continue
                }
            }
        }
        
        // Convert to Set and back to Array for deduplication
        let uniqueResults = Array(Set(allResults))
        print("🎯 Total unique results: \(uniqueResults.count)")
        
        guard !uniqueResults.isEmpty else {
            throw SearchError.noResultsFound
        }
        
        // Sort by relevance
        return uniqueResults.sorted { result1, result2 in
            let title1Contains = result1.title.lowercased().contains(query.lowercased())
            let title2Contains = result2.title.lowercased().contains(query.lowercased())
            
            if title1Contains && !title2Contains {
                return true
            } else if !title1Contains && title2Contains {
                return false
            }
            
            let snippet1Contains = result1.snippet.lowercased().contains(query.lowercased())
            let snippet2Contains = result2.snippet.lowercased().contains(query.lowercased())
            
            return snippet1Contains && !snippet2Contains
        }
    }
    
    // Fetches webpage content concurrently from search results using a content extractor factory.
    private func fetchWebpagesContent(from results: [SearchResult]) async throws -> [String] {
        var contents: [String] = []
        var localDiary = self.diary // Create local copy
        var totalTokens = 0
        let maxTokens = 900_000 // Increased from 800,000 to allow more content
        
        print("📚 Starting content extraction for \(results.count) URLs")
        
        try await withThrowingTaskGroup(of: (String, Int).self) { group in
            for r in results {
                // Break if we're approaching token limit
                if totalTokens >= maxTokens {
                    print("⚠️ Approaching token limit (\(totalTokens)/\(maxTokens)). Stopping content extraction.")
                    break
                }
                
                // Resolve the final URL from the DuckDuckGo redirect
                let finalURL = ContentExtractionFactory.resolveRedirect(for: r.url)
                let extractor = ContentExtractionFactory.createExtractor(for: finalURL)
                
                group.addTask {
                    do {
                        let content = try await extractor.extractContent(from: finalURL)
                        // Rough estimate: 1 token ≈ 4 characters
                        let tokenEstimate = content.count / 4
                        return (content, tokenEstimate)
                    } catch {
                        localDiary.add("Failed to extract content from \(finalURL.absoluteString): \(error.localizedDescription)")
                        return ("", 0)
                    }
                }
            }
            
            // Process results in order of smallest to largest to maximize variety
            var pendingContents: [(content: String, tokens: Int)] = []
            for try await (content, tokens) in group {
                if !content.isEmpty {
                    pendingContents.append((content, tokens))
                }
            }
            
            // Sort by content length (shorter first) to maximize variety
            pendingContents.sort { $0.tokens < $1.tokens }
            
            // Add contents while respecting token limit
            for (content, tokens) in pendingContents {
                if totalTokens + tokens <= maxTokens {
                    contents.append(content)
                    totalTokens += tokens
                    print("📝 Added content with \(tokens) tokens. Total: \(totalTokens)/\(maxTokens)")
                } else {
                    print("⚠️ Skipping content with \(tokens) tokens to stay under limit")
                    break
                }
            }
        }
        
        print("✅ Finished content extraction. Total tokens: \(totalTokens)")
        return contents
    }
    
    // Builds the prompt for the LLM using the current query, aggregated content, and diary log.
    private func buildPrompt(for question: String, aggregatedContent: String, searchResults: [SearchResult], diaryLog: [String], references: [String]) -> String {
        let promptTemplate = """
        You are a research assistant providing comprehensive, well-structured answers. Format your response in clean markdown with clear section breaks:

        1. Use proper markdown headers (##) for each section
        2. Add line breaks between sections for clarity
        3. Use bullet points where appropriate
        4. Include clear paragraph breaks
        5. Format quotes with proper markdown

        Required sections:
        - Executive Summary (concise overview)
        - Background/Context (historical and foundational information)
        - Main Analysis (detailed examination with subsections as needed)
        - Conclusion (key findings and implications)

        Your response should be thorough and detailed, at least 4000 characters (approximately 800 words). 
        Use specific examples and evidence from the provided research.

        Structure your response like this:

        ## Executive Summary
        [Concise overview of the topic]

        ## Background/Context
        [Historical context and foundational information]

        ## Analysis
        [Detailed examination with subsections as needed]

        ## Conclusion
        [Key findings and implications]

        Question: \(question)

        Base your response on the following research:
        """
        
        // Estimate tokens (rough estimate: 4 characters ≈ 1 token)
        let templateTokens = promptTemplate.count / 4
        let questionTokens = question.count / 4
        let targetResponseTokens = 200_000 // Reserve space for response
        
        // Calculate remaining tokens for content
        let maxTokens = 1_000_000 // Total token limit
        let availableForContent = maxTokens - templateTokens - questionTokens - targetResponseTokens
        
        // Truncate aggregated content if needed while preserving complete sentences
        var truncatedContent = aggregatedContent
        if (truncatedContent.count / 4) > availableForContent {
            print("⚠️ Content exceeds available tokens, truncating...")
            let sentences = truncatedContent.components(separatedBy: ". ")
            truncatedContent = ""
            var currentTokens = 0
            
            for sentence in sentences {
                let sentenceTokens = sentence.count / 4
                if currentTokens + sentenceTokens > availableForContent {
                    break
                }
                truncatedContent += sentence + ". "
                currentTokens += sentenceTokens
            }
            print("📝 Truncated content to approximately \(currentTokens) tokens")
        }
        
        let prompt = """
        \(promptTemplate)
        \(truncatedContent)
        
        Remember to:
        1. Provide comprehensive coverage of the topic
        2. Include specific examples and evidence
        3. Maintain clear structure with proper sections
        4. Draw clear conclusions
        5. Write at least 4000 characters (approximately 800 words)
        """
        
        print("🎯 Final prompt tokens (estimate): \(prompt.count / 4)")
        return prompt
    }
    
    // Checks if the answer is definitive.
    private func isDefinitive(answer: String, references: [String]) -> Bool {
        let lower = answer.lowercased()
        
        // Check for uncertainty markers
        if lower.contains("i don't know") ||
           lower.contains("unsure") ||
           lower.contains("not available") ||
           lower.contains("insufficient information") {
            return false
        }
        
        // Check for minimum length and structure
        let minLength = config.minAnswerLength
        let hasRequiredSections = lower.contains("summary") &&
                                lower.contains("background") &&
                                lower.contains("analysis") &&
                                lower.contains("conclusion")
        
        let hasProperStructure = answer.contains("\n\n") && 
                                (answer.contains("First") || 
                                 answer.contains("Additionally") || 
                                 answer.contains("Furthermore") ||
                                 answer.contains("In conclusion"))
        
        // Count number of unique sources cited
        let sourceCount = references.count
        
        return answer.count >= minLength && 
               hasRequiredSections && 
               hasProperStructure && 
               sourceCount >= config.minSources
    }
    
    // Reflection step: if the answer is too short or ambiguous, request LLM to expand it.
    private func reflectionStepIfNeeded(_ answer: String) async throws -> String {
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
    private func beastModeAnswer(for question: String) async throws -> String {
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
    
    // Add method to clean up resources
    func cleanup() {
        visitedURLs.removeAll()
        gaps.removeAll()
        diary = AgentDiary()
        tokenUsage = 0
    }
}
