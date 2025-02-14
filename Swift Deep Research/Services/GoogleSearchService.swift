import Foundation

class GoogleSearchService: SearchServiceProtocol {
    private let apiKey: String
    private let searchEngineId: String
    private var rateLimiter = RateLimiter(requestsPerMinute: 60)
    
    init(apiKey: String, searchEngineId: String) {
        self.apiKey = apiKey
        self.searchEngineId = searchEngineId
    }
    
    func search(query: String) async throws -> [SearchResult] {
        try await rateLimiter.waitForSlot()
        var allResults: [SearchResult] = []
        
        // Reduce the range to get approximately 60 results (6 pages of 10 results each)
        for startIndex in stride(from: 1, to: 61, by: 10) {  // 6 pages of 10 results each
            let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSearchId = searchEngineId.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
            
            // Fix the query encoding
            let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            
            components.queryItems = [
                URLQueryItem(name: "key", value: cleanApiKey),
                URLQueryItem(name: "cx", value: cleanSearchId),
                URLQueryItem(name: "q", value: cleanQuery),
                URLQueryItem(name: "num", value: "10"),
                URLQueryItem(name: "start", value: String(startIndex))
            ]
            
            guard let url = components.url else {
                print("Failed to create URL with components")
                throw SearchError.invalidURL
            }
            
            print("Making Google Search API request with start index: \(startIndex)")
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response type")
                    throw SearchError.invalidResponse
                }
                
                if httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Google Search API error response: \(errorString)")
                    }
                    throw SearchError.invalidResponse
                }
                
                let decoder = JSONDecoder()
                struct GoogleSearchResponse: Codable {
                    struct Item: Codable {
                        let title: String
                        let link: String
                        let snippet: String
                    }
                    let items: [Item]?
                    let searchInformation: SearchInformation?
                    
                    struct SearchInformation: Codable {
                        let totalResults: String
                    }
                }
                
                let searchResponse = try decoder.decode(GoogleSearchResponse.self, from: data)
                
                if let totalResults = searchResponse.searchInformation?.totalResults {
                    print("Total available results: \(totalResults)")
                }
                
                if let items = searchResponse.items {
                    print("Found \(items.count) items in batch \(startIndex)")
                    let results = items.compactMap { item -> SearchResult? in
                        guard let url = URL(string: item.link) else { return nil }
                        return SearchResult(
                            title: item.title,
                            url: url,
                            snippet: item.snippet
                        )
                    }
                    allResults.append(contentsOf: results)
                    
                    // Add early exit if we have enough results
                    let uniqueCount = Set(allResults).count
                    if uniqueCount >= 60 {
                        print("Reached target number of unique results (60)")
                        break
                    }
                } else {
                    print("No more results available starting at index \(startIndex)")
                    break
                }
                
                // Only delay if we got results and there might be more
                if searchResponse.items != nil && startIndex < 61 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch {
                print("Error in Google Search request: \(error)")
                throw error
            }
        }
        
        let uniqueResults = Array(Set(allResults))
        print("Found \(uniqueResults.count) unique results from Google")
        return uniqueResults
    }
} 