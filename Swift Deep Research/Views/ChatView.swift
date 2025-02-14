import SwiftUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            HStack {
                Spacer()
                Button {
                    viewModel.showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
            }
            .padding([.horizontal, .top])
            
            // Document-style content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            if viewModel.isResearching {
                ResearchingIndicator()
            }
            
            // Minimal input bar
            MessageInputBar(
                inputText: $viewModel.inputText,
                onSend: viewModel.sendMessage,
                isProcessing: viewModel.isResearching
            )
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(appState: appState)
        }
        .onChange(of: appState.currentProvider) { _ in
            // Update ChatViewModel's LLM provider when it changes
            viewModel.updateLLMProvider(appState.activeLLMProvider)
        }
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView().environmentObject(ChatViewModel(
            searchService: SearchService(),
            webReaderService: WebContentExtractor.shared,
            llmProvider: AppState.shared.localLLMProvider
        ))
    }
}

// Extract components for better organization
struct ResearchingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Researching...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
    }
}

// Improved input bar
struct MessageInputBar: View {
    @Binding var inputText: String
    let onSend: () -> Void
    let isProcessing: Bool
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 4) {
            if viewModel.isFollowUpMode {
                Text("Asking follow-up question about previous response")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                TextField(viewModel.isFollowUpMode ? "Ask your follow-up question..." : "Ask a question...",
                         text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .disabled(isProcessing)
                
                if viewModel.isFollowUpMode {
                    Button(action: {
                        viewModel.isFollowUpMode = false
                        viewModel.selectedMessageId = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.large)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(12)
        .background(Color(.windowBackgroundColor))
    }
}
