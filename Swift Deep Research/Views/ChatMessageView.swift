import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.isUser {
                Text(message.text)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            } else {
                ScrollView {
                    Text(LocalizedStringKey(message.text))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body))
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Preview provider for SwiftUI canvas
#Preview {
    ChatMessageView(message: ChatMessage(text: """
        ## Test Header
        Some test content with *markdown*
        - Bullet point 1
        - Bullet point 2
        """, isUser: false))
} 