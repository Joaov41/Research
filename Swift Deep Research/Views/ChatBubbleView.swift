import SwiftUI
import MarkdownUI

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Markdown(message.text)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .accessibilityLabel("User Message")
            } else {
                Markdown(message.text)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Assistant Message")
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

struct ChatBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        ChatBubbleView(message: ChatMessage(text: "Example message", isUser: false))
            .previewLayout(.sizeThatFits)
    }
}
