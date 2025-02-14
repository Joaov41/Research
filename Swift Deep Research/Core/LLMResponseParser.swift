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
        // First try direct decoding
        if let data = jsonString.data(using: .utf8),
           let response = try? JSONDecoder().decode(LLMResponse.self, from: data) {
            return .success(response)
        }
        
        // If that fails, try to extract the content as a plain answer
        let cleanedContent = cleanContent(jsonString)
        
        // Create a simple response with the cleaned content
        let response = LLMResponse(
            action: "answer",
            thoughts: "Extracted from response",
            searchQuery: nil,
            questionsToAnswer: nil,
            answer: cleanedContent,
            references: nil
        )
        
        return .success(response)
    }
    
    private static func cleanContent(_ content: String) -> String {
        var cleaned = content
        
        // 1. First clean JSON artifacts but preserve markdown structure
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // 2. Handle the essay structure markers
        cleaned = cleaned.replacingOccurrences(of: "\\essay:", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\title:", with: "# ")
        cleaned = cleaned.replacingOccurrences(of: "\\sections:", with: "\n\n")
        
        // 3. Remove JSON field markers
        let fieldsToRemove = [
            "{ action:", "action:", "thoughts:", "searchQuery:", 
            "questionsToAnswer:", "answer:", "references:",
            "introduction:", "body:", "heading:", "content:",
            "null", "[]", ","
        ]
        for field in fieldsToRemove {
            cleaned = cleaned.replacingOccurrences(of: field, with: "")
        }
        
        // 4. Clean up basic JSON syntax
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "{", with: "")
        cleaned = cleaned.replacingOccurrences(of: "}", with: "")
        
        // 5. Fix newlines and preserve markdown structure
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        // 6. Format section headers with proper markdown
        let headers = [
            "Executive Summary": "## Executive Summary",
            "Background": "## Background",
            "Analysis": "## Analysis",
            "Main Analysis": "## Main Analysis",
            "Conclusion": "## Conclusion",
            "Further Research": "## Further Research"
        ]
        
        for (header, markdown) in headers {
            cleaned = cleaned.replacingOccurrences(of: "\(header):", with: "\n\n\(markdown)\n")
        }
        
        // 7. Process the text line by line to preserve formatting
        let lines = cleaned.components(separatedBy: .newlines)
        cleaned = lines
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Preserve bullet points
                if trimmed.hasPrefix("•") {
                    return "- " + trimmed.dropFirst()
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        // 8. Ensure proper spacing between sections
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
