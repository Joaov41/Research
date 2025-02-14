import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let context: MessageContext
    
    // Add storage for research context
    let researchContext: ResearchContext?
    
    enum MessageContext: Equatable {
        case initial
        case followUp(originalMessageId: UUID)
        case answer
        
        // Custom Equatable implementation for MessageContext
        static func == (lhs: MessageContext, rhs: MessageContext) -> Bool {
            switch (lhs, rhs) {
            case (.initial, .initial):
                return true
            case (.answer, .answer):
                return true
            case let (.followUp(id1), .followUp(id2)):
                return id1 == id2
            default:
                return false
            }
        }
    }
    
    struct ResearchContext {
        let aggregatedContent: String
        let searchResults: [SearchResult]
        let references: [String]
    }
    
    init(text: String, 
         isUser: Bool, 
         context: MessageContext = .initial,
         researchContext: ResearchContext? = nil) {
        self.text = text
        self.isUser = isUser
        self.context = context
        self.researchContext = researchContext
    }
} 
