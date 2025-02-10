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

/// A helper to parse and fix JSON responses from the LLM.
struct LLMResponseParser {
    
    static func parse(from jsonString: String) -> Result<LLMResponse, LLMResponseError> {
        // First try to decode the original string.
        if let data = jsonString.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return .success(response)
        }
        // If that fails, attempt to fix the JSON.
        let fixed = fixJSONIfNeeded(jsonString)
        if let data = fixed.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return .success(response)
        }
        // As a last resort, check for a "FINAL ANSWER:" marker and extract its content.
        if let range = jsonString.range(of: "FINAL ANSWER:") {
            let answer = String(jsonString[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let response = LLMResponse(action: "answer", thoughts: "", searchQuery: nil, questionsToAnswer: nil, answer: answer, references: nil)
            return .success(response)
        }
        return .failure(.parsing(jsonString))
    }
    
    /// Attempts to fix JSON formatting issues that the LLM output might have.
    static func fixJSONIfNeeded(_ jsonString: String) -> String {
        var fixed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove extraneous LLM formatting tokens that are not valid in JSON.
        fixed = fixed.replacingOccurrences(of: "<|im_start|>", with: "")
        fixed = fixed.replacingOccurrences(of: "<|im_end|>", with: "")
        
        // If after removing tokens the string is empty, return a minimal valid JSON response.
        if fixed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "{\"action\": \"answer\", \"thoughts\": \"\", \"searchQuery\": null, \"questionsToAnswer\": null, \"answer\": \"\", \"references\": []}"
        }
        
        // Extract only the portion between the first '{' and the last '}'.
        if let startIndex = fixed.firstIndex(of: "{"),
           let endIndex = fixed.lastIndex(of: "}") {
            fixed = String(fixed[startIndex...endIndex])
        }
        
        // Apply additional simple fixes for formatting issues.
        fixed = fixed.replacingOccurrences(of: "\"\n\"", with: "\",\n\"")
        fixed = fixed.replacingOccurrences(of: ":\n\"", with: ": \"")
        return fixed
    }
}
