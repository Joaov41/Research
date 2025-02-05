import Foundation
import Combine
import SwiftSoup

struct SearchResult {
    let title: String
    let url: URL
}

enum SearchError: Error {
    case invalidQuery
    case invalidURL
    case invalidResponse
    case noResultsFound
}

class SearchService: SearchServiceProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    // Uses DuckDuckGo’s HTML page to extract results.
    func search(query: String) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw SearchError.invalidQuery
        }
        
        let queryForUrl = trimmedQuery
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "+")
        let urlString = "https://html.duckduckgo.com/html/?q=\(queryForUrl)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SearchError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }
        
        do {
            let doc = try SwiftSoup.parse(html)
            let linkElements = try doc.select("a.result__a")
            if linkElements.isEmpty() {
                throw SearchError.noResultsFound
            }
            
            var results: [SearchResult] = []
            for element in linkElements.array() {
                let title = try element.text()
                var href = try element.attr("href")
                // Some links may be relative or protocol relative; fix them.
                if href.hasPrefix("//") {
                    href = "https:" + href
                }
                if let resultURL = URL(string: href) {
                    results.append(SearchResult(title: title, url: resultURL))
                }
            }
            return results
        } catch {
            throw SearchError.invalidResponse
        }
    }
}
