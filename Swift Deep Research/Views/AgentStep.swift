import Foundation

/// Optional struct if you want to store each step for UI or logging
struct AgentStep: Identifiable {
    let id = UUID()
    /// Brief description of the step: "Search query", "Reflection", etc.
    let stepDescription: String
    /// Partial answer or content from LLM so far, if any
    let partialAnswer: String?
    /// Possibly store references or source URLs
    let references: [String]
    /// Indicate if it was the user's query or the agent's step
    let isUserQuery: Bool
    
    init(stepDescription: String,
         partialAnswer: String? = nil,
         references: [String] = [],
         isUserQuery: Bool = false) {
        self.stepDescription = stepDescription
        self.partialAnswer = partialAnswer
        self.references = references
        self.isUserQuery = isUserQuery
    }
}
