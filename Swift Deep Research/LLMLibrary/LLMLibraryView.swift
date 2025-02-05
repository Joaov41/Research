import SwiftUI

struct LLMLibraryView: View {
    @StateObject private var viewModel = LLMLibraryViewModel()
    
    // Define an adaptive grid layout.
    let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.cards) { cardVM in
                        LLMCardView(viewModel: cardVM)
                    }
                }
                .padding()
            }
            .navigationTitle("LLM Library")
        }
    }
}

struct LLMLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LLMLibraryView()
    }
}

struct LLMCardView: View {
    @ObservedObject var viewModel: LLMCardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.modelInfo.name)
                .font(.headline)
            Text(viewModel.modelInfo.size)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isDownloading {
                ProgressView(value: viewModel.downloadProgress)
                HStack {
                    Button("Cancel") {
                        viewModel.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                }
            } else if viewModel.isDownloaded {
                HStack {
                    Button("Delete") {
                        viewModel.deleteModel()
                    }
                    .buttonStyle(.bordered)
                    Button("Load") {
                        viewModel.loadModel()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Download") {
                    viewModel.startDownload()
                }
                .buttonStyle(.borderedProminent)
            }
            
            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(.windowBackground.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray, lineWidth: 1)
        )
    }
}
