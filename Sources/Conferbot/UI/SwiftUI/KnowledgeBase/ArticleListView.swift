//
//  ArticleListView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI

/// View displaying a list of articles within a category
@available(iOS 14.0, *)
public struct ArticleListView: View {
    let category: KnowledgeBaseCategory
    let onArticleSelected: (KnowledgeBaseArticle) -> Void
    let onBack: () -> Void

    @State private var animateItems = false

    public init(
        category: KnowledgeBaseCategory,
        onArticleSelected: @escaping (KnowledgeBaseArticle) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.category = category
        self.onArticleSelected = onArticleSelected
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            headerView

            // Category info
            categoryInfoView

            // Articles list
            if let articles = category.articles, !articles.isEmpty {
                articlesScrollView(articles: articles)
            } else {
                emptyStateView
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animateItems = true
            }
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundColor(.accentColor)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }

    private var categoryInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category icon and name
            HStack(spacing: 12) {
                CategoryIconView(categoryName: category.name, icon: category.icon)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(articleCountText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let description = category.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var articleCountText: String {
        let count = category.articles?.count ?? category.articleCount
        return count == 1 ? "1 article" : "\(count) articles"
    }

    private func articlesScrollView(articles: [KnowledgeBaseArticle]) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    ArticleCardView(article: article)
                        .onTapGesture {
                            onArticleSelected(article)
                        }
                        .opacity(animateItems ? 1 : 0)
                        .offset(y: animateItems ? 0 : 20)
                        .animation(
                            .easeOut(duration: 0.3).delay(Double(index) * 0.05),
                            value: animateItems
                        )
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No articles yet")
                .font(.headline)

            Text("Check back later for new content")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Article Card View

@available(iOS 14.0, *)
struct ArticleCardView: View {
    let article: KnowledgeBaseArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image or placeholder
            coverImageView

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)

                if let description = article.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Meta info (author, date, reading time)
                metaInfoView
            }
            .padding()
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var coverImageView: some View {
        if let coverImage = article.coverImage, let url = URL(string: coverImage) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                case .failure:
                    placeholderImage
                case .empty:
                    placeholderImage
                        .overlay(ProgressView())
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 140)
            .overlay(
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor.opacity(0.5))
            )
    }

    private var metaInfoView: some View {
        HStack(spacing: 8) {
            // Author avatar
            if let author = article.author {
                authorView(author: author)
            }

            Spacer()

            // Date and reading time
            HStack(spacing: 4) {
                Text(article.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("*")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(article.readingTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func authorView(author: KnowledgeBaseAuthor) -> some View {
        HStack(spacing: 6) {
            if let avatarUrl = author.avatar, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    authorInitialsView(name: author.name)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            } else {
                authorInitialsView(name: author.name)
            }

            Text(author.name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func authorInitialsView(name: String) -> some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 24, height: 24)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
            )
    }
}

// MARK: - Category Icon View

@available(iOS 14.0, *)
struct CategoryIconView: View {
    let categoryName: String
    let icon: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))

            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
        }
    }

    private var iconName: String {
        if let icon = icon, !icon.isEmpty {
            return icon
        }

        let name = categoryName.lowercased()

        if name.contains("start") || name.contains("begin") || name.contains("intro") {
            return "play.circle"
        }
        if name.contains("setting") || name.contains("config") || name.contains("setup") {
            return "gearshape"
        }
        if name.contains("faq") || name.contains("question") || name.contains("help") {
            return "questionmark.circle"
        }
        if name.contains("guide") || name.contains("tutorial") || name.contains("how") {
            return "book"
        }
        if name.contains("account") || name.contains("profile") || name.contains("user") {
            return "person.circle"
        }
        if name.contains("billing") || name.contains("payment") || name.contains("price") {
            return "creditcard"
        }
        if name.contains("security") || name.contains("privacy") || name.contains("safe") {
            return "lock.shield"
        }
        if name.contains("integrat") || name.contains("connect") || name.contains("api") {
            return "link"
        }
        if name.contains("troubleshoot") || name.contains("issue") || name.contains("problem") {
            return "wrench.and.screwdriver"
        }

        return "doc.text"
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct ArticleListView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleCategory = KnowledgeBaseCategory(
            id: "1",
            name: "Getting Started",
            description: "Learn the basics of using our platform",
            articleCount: 3,
            articles: [
                KnowledgeBaseArticle(
                    id: "a1",
                    title: "Quick Start Guide",
                    content: "This is a quick start guide...",
                    category: "Getting Started",
                    tags: ["beginner", "tutorial"],
                    description: "Get up and running in minutes",
                    author: KnowledgeBaseAuthor(name: "John Doe")
                ),
                KnowledgeBaseArticle(
                    id: "a2",
                    title: "Understanding the Dashboard",
                    content: "The dashboard provides...",
                    category: "Getting Started",
                    tags: ["dashboard", "overview"],
                    description: "Learn about the main dashboard features",
                    author: KnowledgeBaseAuthor(name: "Jane Smith")
                )
            ]
        )

        ArticleListView(
            category: sampleCategory,
            onArticleSelected: { _ in },
            onBack: { }
        )
    }
}
