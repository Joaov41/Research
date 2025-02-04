import SwiftUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    let appState = AppState.shared
    
    var body: some View {
        VStack {
            HStack {
                Text("Swift Deep Research")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                        .accessibilityLabel("Settings")
                }
            }
            .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        ChatBubbleView(message: message)
                    }
                }
                .padding(.vertical)
            }
            
            if viewModel.isResearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Researching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(4) // Reduced padding for a more compact design.
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            HStack {
                TextField("Enter your prompt...", text: $viewModel.inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Research query input")
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .imageScale(.large)
                        .accessibilityLabel("Send message")
                }
                .disabled(viewModel.inputText.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(appState: appState)
        }
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView().environmentObject(ChatViewModel(
            searchService: SearchService(),
            webReaderService: WebReaderService(),
            llmProvider: AppState.shared.localLLMProvider
        ))
    }
}
