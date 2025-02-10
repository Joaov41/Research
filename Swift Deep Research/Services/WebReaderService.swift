import Foundation
import SwiftSoup

enum WebReaderError: Error {
    case invalidResponse
    case invalidData
}

// MARK: - ContentExtractor Protocol
protocol ContentExtractor {
    func extractContent(from url: URL) async throws -> String
}

// MARK: - RedditContentExtractor
struct RedditContentExtractor: ContentExtractor {
    private let api = RedditAPI()
    
    func extractContent(from url: URL) async throws -> String {
        print("📍 RedditContentExtractor - Starting extraction for URL: \(url)")
        return try await api.getContent(from: url)
    }
}

struct WebContentExtractor: ContentExtractor {
    func extractContent(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        
        // Use a full-document parser if possible; otherwise, fall back to parsing as a body fragment.
        let doc: Document
        if htmlString.lowercased().contains("<html") {
            doc = try SwiftSoup.parse(htmlString)
        } else {
            doc = try SwiftSoup.parseBodyFragment(htmlString)
        }
        
        // Remove unwanted elements that might add extraneous text.
        try doc.select("script, style, nav, footer, header, aside").remove()
        
        // For many pages a direct extraction of all text is more reliable:
        let textContent = try doc.text()
        let cleaned = cleanText(textContent)
        
        print(cleaned)
        return cleaned
    }
    
    private func cleanText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
// MARK: - ContentExtractionFactory
struct ContentExtractionFactory {
    static func createExtractor(for url: URL) -> ContentExtractor {
        // Resolve Redirect: if the URL is a DuckDuckGo redirect, extract the final URL.
        let resolvedURL = resolveRedirect(for: url)
        if resolvedURL.host?.contains("reddit.com") == true {
            return RedditContentExtractor()
        }
        return WebContentExtractor()
    }
    
     static func resolveRedirect(for url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, host.contains("duckduckgo.com"),
              let queryItems = components.queryItems,
              let uddgValue = queryItems.first(where: { $0.name == "uddg" })?.value,
              let finalURL = URL(string: uddgValue) else {
            return url
        }
        return finalURL
    }
}
