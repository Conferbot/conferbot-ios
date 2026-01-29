//
//  KnowledgeBaseView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Main container view for Knowledge Base
@available(iOS 14.0, *)
public struct KnowledgeBaseView: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @StateObject private var viewModel: KnowledgeBaseViewModel

    @State private var searchText = ""
    @State private var selectedCategory: KnowledgeBaseCategory?
    @State private var selectedArticle: KnowledgeBaseArticle?
    @State private var navigationPath: [KnowledgeBaseNavigationDestination] = []

    public init() {
        _viewModel = StateObject(wrappedValue: KnowledgeBaseViewModel())
    }

    public var body: some View {
        NavigationView {
            ZStack {
                mainContent

                if viewModel.isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Help Center")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadCategories()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.loadingState {
        case .error(let message):
            errorView(message: message)
        default:
            contentView
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // Search bar
            ArticleSearchBar(
                text: $searchText,
                onSearch: { query in
                    Task {
                        await viewModel.searchArticles(query: query)
                    }
                },
                onClear: {
                    viewModel.clearSearch()
                }
            )
            .padding(.horizontal)
            .padding(.top, 8)

            // Content
            if !searchText.isEmpty {
                searchResultsView
            } else if let category = selectedCategory {
                ArticleListView(
                    category: category,
                    onArticleSelected: { article in
                        selectedArticle = article
                    },
                    onBack: {
                        selectedCategory = nil
                    }
                )
            } else if let article = selectedArticle {
                ArticleDetailView(
                    article: article,
                    onBack: {
                        selectedArticle = nil
                    }
                )
            } else {
                CategoryListView(
                    categories: viewModel.categories,
                    onCategorySelected: { category in
                        selectedCategory = category
                    }
                )
            }
        }
    }

    private var searchResultsView: some View {
        ArticleSearchResultsView(
            searchText: searchText,
            results: viewModel.searchResults,
            isSearching: viewModel.isSearching,
            onArticleSelected: { article in
                selectedArticle = article
                searchText = ""
            }
        )
    }

    private var loadingOverlay: some View {
        Color.black.opacity(0.1)
            .ignoresSafeArea()
            .overlay(
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle())
            )
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Something went wrong")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                Task {
                    await viewModel.loadCategories()
                }
            }) {
                Text("Try Again")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

// MARK: - Navigation Destination

@available(iOS 14.0, *)
enum KnowledgeBaseNavigationDestination: Hashable {
    case category(KnowledgeBaseCategory)
    case article(KnowledgeBaseArticle)
    case search(String)
}

// MARK: - View Model

@available(iOS 14.0, *)
@MainActor
class KnowledgeBaseViewModel: ObservableObject {
    @Published var categories: [KnowledgeBaseCategory] = []
    @Published var searchResults: [KnowledgeBaseArticle] = []
    @Published var loadingState: KnowledgeBaseLoadingState = .idle
    @Published var isLoading: Bool = false
    @Published var isSearching: Bool = false

    private var knowledgeBaseService: KnowledgeBaseService? {
        return ConferBot.shared.knowledgeBaseService
    }

    func loadCategories() async {
        guard let service = knowledgeBaseService else {
            loadingState = .error("Knowledge base service not initialized")
            return
        }

        isLoading = true
        loadingState = .loading

        do {
            categories = try await service.fetchCategories()
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }

        isLoading = false
    }

    func searchArticles(query: String) async {
        guard let service = knowledgeBaseService else { return }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            searchResults = try await service.searchArticles(query: query)
        } catch {
            // Fallback to local search
            searchResults = service.searchArticlesLocally(query: query)
        }

        isSearching = false
    }

    func clearSearch() {
        searchResults = []
    }
}

// MARK: - Search Bar Component

@available(iOS 14.0, *)
struct ArticleSearchBar: View {
    @Binding var text: String
    var onSearch: (String) -> Void
    var onClear: () -> Void

    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)

                TextField("Search for articles...", text: $text, onCommit: {
                    onSearch(text)
                })
                .textFieldStyle(PlainTextFieldStyle())
                .onChange(of: text) { newValue in
                    if !newValue.isEmpty {
                        onSearch(newValue)
                    }
                }

                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        onClear()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            if isEditing {
                Button("Cancel") {
                    text = ""
                    isEditing = false
                    onClear()
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .onTapGesture {
            isEditing = true
        }
    }
}

// MARK: - Search Results View

@available(iOS 14.0, *)
struct ArticleSearchResultsView: View {
    let searchText: String
    let results: [KnowledgeBaseArticle]
    let isSearching: Bool
    let onArticleSelected: (KnowledgeBaseArticle) -> Void

    var body: some View {
        Group {
            if isSearching {
                VStack {
                    ProgressView()
                        .padding(.top, 40)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            } else if results.isEmpty {
                emptyResultsView
            } else {
                resultsList
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No articles found")
                .font(.headline)

            Text("Try searching with different keywords")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(results) { article in
                    ArticleSearchResultRow(article: article)
                        .onTapGesture {
                            onArticleSelected(article)
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Search Result Row

@available(iOS 14.0, *)
struct ArticleSearchResultRow: View {
    let article: KnowledgeBaseArticle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let categoryName = article.categoryName {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("*")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(article.readingTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct KnowledgeBaseView_Previews: PreviewProvider {
    static var previews: some View {
        KnowledgeBaseView()
    }
}
