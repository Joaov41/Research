import Foundation
import Combine
import SwiftSoup

struct SearchResult: Hashable {
    let title: String
    let url: URL
    let snippet: String
    
    init(title: String, url: URL, snippet: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)  // URL is unique enough for our purposes
    }
    
    // Implement Equatable
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        return lhs.url == rhs.url  // Consider two results equal if they have the same URL
    }
}

enum SearchError: Error {
    case invalidQuery
    case invalidURL
    case invalidResponse
    case noResultsFound
}

class SearchService: SearchServiceProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    // Uses DuckDuckGo's HTML page to extract results.
    func search(query: String) async throws -> [SearchResult] {
        var allResults: [SearchResult] = []
        print("🔍 Starting DuckDuckGo search for: \(query)")
        
        // Try different variations of the search query to get more diverse results
        let queryVariations = [
            query,
            "\(query) overview",
            "\(query) explained",
            "\(query) guide",
            "\(query) tutorial"
        ]
        
        for variation in queryVariations {
            let queryForUrl = variation
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .joined(separator: "+")
            
            let urlString = "https://html.duckduckgo.com/html/?q=\(queryForUrl)"
            guard let url = URL(string: urlString) else {
                continue
            }
            
            print("📊 Fetching results for query variation: \(variation)")
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    continue
                }
                
                let doc = try SwiftSoup.parse(html)
                let linkElements = try doc.select("a.result__a")
                let snippetElements = try doc.select("div.result__snippet")
                
                print("📝 Found \(linkElements.array().count) raw results for variation")
                
                let results = linkElements.array().enumerated().compactMap { index, element -> SearchResult? in
                    do {
                        let title = try element.text()
                        var href = try element.attr("href")
                        if href.hasPrefix("//") {
                            href = "https:" + href
                        }
                        guard let resultURL = URL(string: href) else { return nil }
                        
                        let snippet = index < snippetElements.array().count ? 
                            try snippetElements.array()[index].text() : ""
                        
                        return SearchResult(title: title, url: resultURL, snippet: snippet)
                    } catch {
                        print("⚠️ Error parsing result at index \(index): \(error)")
                        return nil
                    }
                }
                
                print("✅ Successfully parsed \(results.count) results")
                allResults.append(contentsOf: results)
                
                // Add delay between variations
                if variation != queryVariations.last {
                    print("⏳ Waiting before next query variation...")
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                }
                
            } catch {
                print("❌ Error fetching results for variation '\(variation)': \(error)")
                continue
            }
        }
        
        // Remove duplicates and return
        let uniqueResults = Array(Set(allResults))
        print("🎯 Final unique results count: \(uniqueResults.count)")
        return uniqueResults
    }
}
