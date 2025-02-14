import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @EnvironmentObject var viewModel: ChatViewModel
    
    private func formatMarkdown(_ text: String) -> String {
        var formatted = text
            .replacingOccurrences(of: "\\", with: "")
            // Ensure proper spacing between sections
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Ensure proper markdown headers and spacing
        let sections = ["Executive Summary", "Background", "Context", "Analysis", "Conclusion"]
        for section in sections {
            // Replace plain text headers with markdown headers
            formatted = formatted.replacingOccurrences(
                of: "(?m)^\\s*\(section):?\\s*$",
                with: "\n\n## \(section)\n",
                options: .regularExpression
            )
        }
        
        // Clean up any markdown artifacts
        formatted = formatted
            .replacingOccurrences(of: "##{2,}", with: "##") // Fix multiple header markers
            .replacingOccurrences(of: "\\s*\n\\s*\n\\s*\n+", with: "\n\n", options: .regularExpression) // Fix multiple line breaks
        
        // Ensure proper list formatting
        formatted = formatted.replacingOccurrences(
            of: "(?m)^\\s*[•\\-]\\s*",
            with: "\n- ",
            options: .regularExpression
        )
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        if message.isUser {
            // User messages can stay compact
            HStack {
                Spacer()
                Text(message.text)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        } else {
            // Assistant messages with new controls
            VStack(alignment: .leading) {
                // Top row with buttons
                HStack {
                    Spacer()
                    // Export button
                    Button(action: {
                        exportToPDF()
                    }) {
                        Label("Export to PDF", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Export conversation to PDF")
                    
                    // New research button
                    Button(action: {
                        viewModel.restartResearch()
                    }) {
                        Label("New Research", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Start new research")
                }
                .padding(.bottom, 4)
                
                // Content
                Markdown(formatMarkdown(message.text))
                    .markdownTheme(.docStyle)
                    .textSelection(.enabled)
                
                // Follow-up button if applicable
                if case .initial = message.context {
                    Button(action: {
                        viewModel.isFollowUpMode = true
                        viewModel.selectedMessageId = message.id
                    }) {
                        Label("Ask follow-up question", systemImage: "questionmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.windowBackgroundColor))
                    .opacity(viewModel.selectedMessageId == message.id ? 0.2 : 0)
            )
        }
    }
    
    // Add PDF export functionality
    private func exportToPDF() {
        print("Starting PDF export")
        print("Current message context: \(message.context)")
        print("Total messages in viewModel: \(viewModel.messages.count)")
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Research_\(Date().formatted(.iso8601)).pdf"
        
        if savePanel.runModal() == .OK {
            guard let url = savePanel.url else { return }
            
            let conversation = NSMutableAttributedString()
            conversation.append(NSAttributedString(
                string: "Research Report\n\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]
            ))
            
            // Get all related messages in chronological order
            var messagesToInclude: [ChatMessage] = []
            
            // First, find the initial question and answer
            let initialQuestion = viewModel.messages.first { $0.isUser && $0.context == .initial }
            let initialAnswer = viewModel.messages.first { !$0.isUser && $0.context == .initial }
            
            if let q = initialQuestion, let a = initialAnswer {
                print("Found initial Q&A")
                messagesToInclude.append(q)
                messagesToInclude.append(a)
            }
            
            // Then find all follow-ups and their answers
            let followUpPairs = viewModel.messages.reduce(into: [(question: ChatMessage, answer: ChatMessage)]()) { pairs, msg in
                if case .followUp(let originalId) = msg.context, msg.isUser {
                    // For each follow-up question, find its answer
                    if let answer = viewModel.messages.first(where: { !$0.isUser && $0.context == .answer }) {
                        pairs.append((question: msg, answer: answer))
                    }
                }
            }
            
            print("Found \(followUpPairs.count) follow-up Q&A pairs")
            for pair in followUpPairs {
                messagesToInclude.append(pair.question)
                messagesToInclude.append(pair.answer)
            }
            
            // Add all messages in order
            for msg in messagesToInclude {
                print("Adding message: \(msg.isUser ? "User" : "Assistant") - \(msg.context)")
                
                // Add header
                let headerText = if msg.isUser {
                    msg.context == .initial ? "Initial Research Question:" : "Follow-up Question:"
                } else {
                    "Research Findings:"
                }
                
                conversation.append(NSAttributedString(
                    string: "\n\(headerText)\n",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]
                ))
                
                // Add content
                conversation.append(NSAttributedString(
                    string: "\(msg.text)\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 14)]
                ))
                
                // Add sources if it's an answer
                if !msg.isUser, let context = msg.researchContext {
                    conversation.append(NSAttributedString(
                        string: "\nSources:\n",
                        attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
                    ))
                    
                    for ref in context.references {
                        conversation.append(NSAttributedString(
                            string: "• \(ref)\n",
                            attributes: [.font: NSFont.systemFont(ofSize: 12)]
                        ))
                    }
                    
                    conversation.append(NSAttributedString(string: "\n---\n"))
                }
            }
            
            // Create and save PDF
            let pdfData = conversation.createPDF()
            try? pdfData.write(to: url)
            print("PDF saved with \(messagesToInclude.count) messages")
        }
    }
}

private extension Theme {
    static let docStyle = Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(.secondary)
        }
        .heading1 { content in
            VStack(alignment: .leading, spacing: 8) {
                content
                    .font(.title)
                    .fontWeight(.bold)
                Divider()
            }
        }
        .heading2 { content in
            content
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 16)
        }
        .heading3 { content in
            content
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 12)
        }
        .paragraph { content in
            content
                .lineSpacing(8)
                .padding(.vertical, 8)
        }
}

struct ChatBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        ChatBubbleView(message: ChatMessage(text: "Example message", isUser: false))
    }
}
