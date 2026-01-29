//
//  ArticleSearchView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// Dedicated search view for knowledge base articles
@available(iOS 14.0, *)
public struct ArticleSearchView: View {
    @Binding var searchText: String
    @Binding var isPresented: Bool

    let categories: [KnowledgeBaseCategory]
    let onArticleSelected: (KnowledgeBaseArticle) -> Void

    @State private var searchResults: [KnowledgeBaseArticle] = []
    @State private var isSearching: Bool = false
    @State private var selectedIndex: Int = -1
    @FocusState private var isSearchFocused: Bool

    public init(
        searchText: Binding<String>,
        isPresented: Binding<Bool>,
        categories: [KnowledgeBaseCategory],
        onArticleSelected: @escaping (KnowledgeBaseArticle) -> Void
    ) {
        self._searchText = searchText
        self._isPresented = isPresented
        self.categories = categories
        self.onArticleSelected = onArticleSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider()

            // Content
            if searchText.isEmpty {
                recentSearchesView
            } else if isSearching {
                loadingView
            } else if searchResults.isEmpty {
                emptyResultsView
            } else {
                searchResultsListView
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { newValue in
            performSearch(query: newValue)
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))

                TextField("Search for articles...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if !searchText.isEmpty {
                            performSearch(query: searchText)
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Recent Searches View

    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Popular categories
            if !categories.isEmpty {
                popularCategoriesSection
            }

            // Quick suggestions
            quickSuggestionsSection

            Spacer()
        }
        .padding()
    }

    private var popularCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories.prefix(5)) { category in
                        CategoryChip(category: category)
                            .onTapGesture {
                                // Could filter by category
                                searchText = category.name
                            }
                    }
                }
            }
        }
    }

    private var quickSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Searches")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(popularSearchTerms, id: \.self) { term in
                    Button(action: {
                        searchText = term
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.gray)

                            Text(term)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var popularSearchTerms: [String] {
        // These could be fetched from analytics or configured
        return [
            "Getting started",
            "Account settings",
            "Billing",
            "Integration",
            "Troubleshooting"
        ]
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)

            Text("Searching...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Results View

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No articles found")
                .font(.headline)

            Text("Try searching with different keywords")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Suggestions
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggestions:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    suggestionItem("Check your spelling")
                    suggestionItem("Try more general terms")
                    suggestionItem("Browse categories instead")
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestionItem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Search Results List View

    private var searchResultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Results count
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Results
                ForEach(Array(searchResults.prefix(10).enumerated()), id: \.element.id) { index, article in
                    SearchResultRow(
                        article: article,
                        searchQuery: searchText,
                        isSelected: selectedIndex == index
                    )
                    .onTapGesture {
                        onArticleSelected(article)
                        isPresented = false
                    }

                    if index < min(searchResults.count, 10) - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }

                // View all results
                if searchResults.count > 10 {
                    viewAllResultsButton
                }
            }
        }
    }

    private var viewAllResultsButton: some View {
        Button(action: {
            // Show all results
        }) {
            HStack {
                Text("View all \(searchResults.count) results")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .foregroundColor(.accentColor)
            .padding()
        }
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        // Perform local search through all articles
        let lowercasedQuery = query.lowercased()
        var allArticles: [KnowledgeBaseArticle] = []

        for category in categories {
            if let categoryArticles = category.articles {
                allArticles.append(contentsOf: categoryArticles)
            }
        }

        let results = allArticles.filter { article in
            article.title.lowercased().contains(lowercasedQuery) ||
            (article.description?.lowercased().contains(lowercasedQuery) ?? false) ||
            article.content.lowercased().contains(lowercasedQuery) ||
            article.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }

        // Sort by relevance (title matches first)
        let sortedResults = results.sorted { a, b in
            let aTitle = a.title.lowercased()
            let bTitle = b.title.lowercased()

            // Title starts with query
            let aStartsWith = aTitle.hasPrefix(lowercasedQuery)
            let bStartsWith = bTitle.hasPrefix(lowercasedQuery)
            if aStartsWith != bStartsWith {
                return aStartsWith
            }

            // Title contains query
            let aContains = aTitle.contains(lowercasedQuery)
            let bContains = bTitle.contains(lowercasedQuery)
            if aContains != bContains {
                return aContains
            }

            return false
        }

        searchResults = sortedResults
        selectedIndex = -1
        isSearching = false
    }
}

// MARK: - Category Chip

@available(iOS 14.0, *)
struct CategoryChip: View {
    let category: KnowledgeBaseCategory

    var body: some View {
        HStack(spacing: 6) {
            CategoryIconView(categoryName: category.name, icon: category.icon)
                .frame(width: 24, height: 24)

            Text(category.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .foregroundColor(.accentColor)
        .cornerRadius(20)
    }
}

// MARK: - Search Result Row

@available(iOS 14.0, *)
struct SearchResultRow: View {
    let article: KnowledgeBaseArticle
    let searchQuery: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Highlighted title
                highlightedText(article.title, query: searchQuery)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                // Meta info
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
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    @ViewBuilder
    private func highlightedText(_ text: String, query: String) -> some View {
        if query.isEmpty {
            Text(text)
        } else {
            let lowercasedText = text.lowercased()
            let lowercasedQuery = query.lowercased()

            if let range = lowercasedText.range(of: lowercasedQuery) {
                let startIndex = text.index(text.startIndex, offsetBy: lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound))
                let endIndex = text.index(startIndex, offsetBy: query.count)

                let before = String(text[..<startIndex])
                let match = String(text[startIndex..<endIndex])
                let after = String(text[endIndex...])

                Text(before) +
                Text(match).foregroundColor(.accentColor).bold() +
                Text(after)
            } else {
                Text(text)
            }
        }
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct ArticleSearchView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleSearchView(
            searchText: .constant(""),
            isPresented: .constant(true),
            categories: [
                KnowledgeBaseCategory(
                    id: "1",
                    name: "Getting Started",
                    articleCount: 5,
                    articles: [
                        KnowledgeBaseArticle(
                            id: "a1",
                            title: "Quick Start Guide",
                            content: "Content here...",
                            category: "Getting Started",
                            categoryName: "Getting Started",
                            tags: []
                        )
                    ]
                )
            ],
            onArticleSelected: { _ in }
        )
    }
}
