import Foundation

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
        return htmlString.strippingHTMLTags()
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
