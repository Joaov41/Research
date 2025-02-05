import Foundation
import SwiftSoup

enum WebReaderError: Error {
    case invalidResponse
    case invalidData
}

class WebReaderService: WebReaderServiceProtocol {
    func fetchContent(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WebReaderError.invalidResponse
        }
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw WebReaderError.invalidData
        }
        
        do {
            let doc = try SwiftSoup.parse(htmlString)
            // Remove unwanted elements
            try doc.select("script, style, nav, footer, header, aside").remove()
            // Attempt to extract from <article> if available
            if let article = try doc.select("article").first() {
                let text = try article.text()
                if text.count > 100 { return text }
            }
            // Then try the <main> element
            if let main = try doc.select("main").first() {
                let text = try main.text()
                if text.count > 100 { return text }
            }
            // Otherwise, fall back to the body text
            if let body = try doc.body()?.text(), body.count > 100 {
                return body
            }
            // Fallback: use a simple HTML tag stripper
            return htmlString.strippingHTMLTags()
        } catch {
            // On error, return a simple stripped version
            return htmlString.strippingHTMLTags()
        }
    }
}

extension String {
    func strippingHTMLTags() -> String {
        let pattern = "<[^>]+>"
        return self.replacingOccurrences(of: pattern,
                                         with: "",
                                         options: .regularExpression,
                                         range: nil)
    }
}
