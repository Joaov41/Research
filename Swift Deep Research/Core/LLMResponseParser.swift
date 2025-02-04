import Foundation

// The expected JSON response from the LLM.
struct LLMResponse: Codable {
    let action: String
    let thoughts: String
    let searchQuery: String?
    let questionsToAnswer: [String]?
    let answer: String?
    let references: [Reference]?
}

struct Reference: Codable {
    let exactQuote: String?
    let url: String
}

enum LLMResponseError: Error, LocalizedError {
    case parsing(String)
    
    var errorDescription: String? {
        switch self {
        case .parsing(let msg):
            return "Error parsing LLM response: \(msg)"
        }
    }
}

/// A helper to parse and fix JSON.
struct LLMResponseParser {
    
    static func parse(from jsonString: String) -> Result<LLMResponse, LLMResponseError> {
        // Try to decode the original string first.
        if let data = jsonString.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return .success(response)
        }
        // If that fails, apply our heuristics.
        let fixed = fixJSONIfNeeded(jsonString)
        if let data = fixed.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return .success(response)
        }
        return .failure(.parsing(jsonString))
    }
    
    /// Attempts to extract only the JSON content from a string and does some simple fixes.
    static func fixJSONIfNeeded(_ jsonString: String) -> String {
        // Trim leading/trailing whitespace and newlines.
        var fixed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract only the part between the first '{' and the last '}'.
        if let startIndex = fixed.firstIndex(of: "{"),
           let endIndex = fixed.lastIndex(of: "}") {
            fixed = String(fixed[startIndex...endIndex])
        }
        
        // Simple fixes to help enforce proper JSON formatting.
        fixed = fixed.replacingOccurrences(of: "\"\n\"", with: "\",\n\"")
        fixed = fixed.replacingOccurrences(of: ":\n\"", with: ": \"")
        return fixed
    }
}
