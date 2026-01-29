//
//  ArticleDetailView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import SwiftUI
import WebKit

/// View displaying the full content of a knowledge base article
@available(iOS 14.0, *)
public struct ArticleDetailView: View {
    let article: KnowledgeBaseArticle
    let onBack: () -> Void

    @ObservedObject private var conferBot = ConferBot.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var hasRated: Bool = false
    @State private var showRatingSuccess: Bool = false
    @State private var relatedArticles: [KnowledgeBaseArticle] = []
    @State private var tableOfContents: [TableOfContentsItem] = []
    @State private var showTableOfContents: Bool = true

    public init(
        article: KnowledgeBaseArticle,
        onBack: @escaping () -> Void
    ) {
        self.article = article
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Content
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        // Breadcrumb
                        breadcrumbView

                        // Article title and meta
                        articleHeaderView

                        // Table of contents (if applicable)
                        if tableOfContents.count >= 2 {
                            tableOfContentsView
                        }

                        // Cover image
                        if let coverImage = article.coverImage {
                            coverImageView(url: coverImage)
                        }

                        // Author info
                        authorInfoView

                        // Article content
                        articleContentView

                        // Rating section
                        ratingSection

                        // Related articles
                        if !relatedArticles.isEmpty {
                            relatedArticlesSection
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .coordinateSpace(name: "scroll")
        }
        .onAppear {
            trackArticleView()
            loadRelatedArticles()
            extractTableOfContents()
        }
        .onDisappear {
            sendEngagementData()
        }
    }

    // MARK: - Header View

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

            Text(truncatedTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // Placeholder for symmetry
            HStack(spacing: 4) {
                Text("Back")
                    .font(.subheadline)
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .opacity(0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }

    private var truncatedTitle: String {
        if article.title.count > 25 {
            return String(article.title.prefix(22)) + "..."
        }
        return article.title
    }

    // MARK: - Breadcrumb View

    private var breadcrumbView: some View {
        HStack(spacing: 4) {
            Image(systemName: "house")
                .font(.caption)
            Text("Help")
                .font(.caption)

            Image(systemName: "chevron.right")
                .font(.system(size: 8))

            if let categoryName = article.categoryName ?? article.category {
                Text(categoryName)
                    .font(.caption)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
            }

            Text(truncatedTitle)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
        .foregroundColor(.accentColor)
        .padding(.horizontal)
        .padding(.top, 16)
    }

    // MARK: - Article Header View

    private var articleHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.title)
                .font(.title)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            // Reading time and last updated
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(article.readingTime)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                Text("*")
                    .foregroundColor(.secondary)

                Text("Updated \(article.formattedDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 16)
    }

    // MARK: - Table of Contents View

    private var tableOfContentsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation {
                    showTableOfContents.toggle()
                }
            }) {
                HStack {
                    Text("In this article")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showTableOfContents ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if showTableOfContents {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tableOfContents) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 6, height: 6)

                            Text(item.text)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, CGFloat((item.level - 1) * 12))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 16)
    }

    // MARK: - Cover Image View

    private func coverImageView(url: String) -> some View {
        Group {
            if let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: 200)
                            .clipped()
                            .cornerRadius(12)
                    case .failure:
                        EmptyView()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 200)
                            .cornerRadius(12)
                            .overlay(ProgressView())
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    // MARK: - Author Info View

    private var authorInfoView: some View {
        Group {
            if let author = article.author {
                HStack(spacing: 12) {
                    // Author avatar
                    if let avatarUrl = author.avatar, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            authorInitialsView(name: author.name)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        authorInitialsView(name: author.name)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(author.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Published on \(article.formattedDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
        }
    }

    private func authorInitialsView(name: String) -> some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            )
    }

    // MARK: - Article Content View

    private var articleContentView: some View {
        HTMLContentView(htmlContent: article.content)
            .padding(.horizontal)
            .padding(.top, 20)
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.top, 24)

            if showRatingSuccess {
                Text("Thank you for your feedback!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    Text("Was this article helpful?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        ratingButton(helpful: true)
                        ratingButton(helpful: false)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .animation(.easeInOut, value: showRatingSuccess)
    }

    private func ratingButton(helpful: Bool) -> some View {
        Button(action: {
            rateArticle(helpful: helpful)
        }) {
            HStack(spacing: 6) {
                Image(systemName: helpful ? "hand.thumbsup" : "hand.thumbsdown")
                    .font(.subheadline)
                Text(helpful ? "Yes" : "No")
                    .font(.subheadline)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(hasRated ? Color.gray.opacity(0.3) : Color.accentColor.opacity(0.1))
            .foregroundColor(hasRated ? .gray : .accentColor)
            .cornerRadius(20)
        }
        .disabled(hasRated)
    }

    // MARK: - Related Articles Section

    private var relatedArticlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related Articles")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(Array(relatedArticles.enumerated()), id: \.element.id) { index, relatedArticle in
                    RelatedArticleRow(article: relatedArticle)
                        .onTapGesture {
                            // Navigate to related article
                            // This would typically update the parent's selected article
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Private Methods

    private func trackArticleView() {
        conferBot.knowledgeBaseService?.trackArticleView(
            articleId: article.id,
            visitorId: conferBot.currentSession?.visitorId,
            sessionId: conferBot.currentSession?.chatSessionId
        )

        conferBot.knowledgeBaseService?.startArticleEngagement(
            articleId: article.id,
            visitorId: conferBot.currentSession?.visitorId,
            sessionId: conferBot.currentSession?.chatSessionId
        )

        hasRated = conferBot.knowledgeBaseService?.hasRatedArticle(article.id) ?? false
    }

    private func sendEngagementData() {
        conferBot.knowledgeBaseService?.sendCurrentEngagement()
    }

    private func loadRelatedArticles() {
        if let service = conferBot.knowledgeBaseService {
            relatedArticles = service.getRelatedArticles(for: article, limit: 3)
        }
    }

    private func extractTableOfContents() {
        if let service = conferBot.knowledgeBaseService {
            tableOfContents = service.extractTableOfContents(from: article.content)
        }
    }

    private func rateArticle(helpful: Bool) {
        guard !hasRated else { return }

        conferBot.knowledgeBaseService?.rateArticle(
            articleId: article.id,
            helpful: helpful,
            visitorId: conferBot.currentSession?.visitorId,
            sessionId: conferBot.currentSession?.chatSessionId
        ) { success in
            if success {
                hasRated = true
                withAnimation {
                    showRatingSuccess = true
                }
            }
        }
    }
}

// MARK: - Related Article Row

@available(iOS 14.0, *)
struct RelatedArticleRow: View {
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

// MARK: - HTML Content View

@available(iOS 14.0, *)
struct HTMLContentView: View {
    let htmlContent: String

    @State private var contentHeight: CGFloat = 100

    var body: some View {
        HTMLWebView(htmlContent: styledHTMLContent, dynamicHeight: $contentHeight)
            .frame(height: contentHeight)
    }

    private var styledHTMLContent: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 16px;
                    line-height: 1.6;
                    color: #1c1c1e;
                    background-color: transparent;
                    padding: 0;
                }
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #f5f5f7;
                    }
                    a {
                        color: #0a84ff;
                    }
                    pre, code {
                        background-color: #2c2c2e;
                    }
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 12px;
                    font-weight: 600;
                }
                h1 { font-size: 24px; }
                h2 { font-size: 20px; }
                h3 { font-size: 18px; }
                p {
                    margin-bottom: 16px;
                }
                a {
                    color: #007aff;
                    text-decoration: none;
                }
                ul, ol {
                    margin-bottom: 16px;
                    padding-left: 24px;
                }
                li {
                    margin-bottom: 8px;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 12px 0;
                }
                pre {
                    background-color: #f5f5f7;
                    padding: 16px;
                    border-radius: 8px;
                    overflow-x: auto;
                    margin-bottom: 16px;
                }
                code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 14px;
                    background-color: #f5f5f7;
                    padding: 2px 6px;
                    border-radius: 4px;
                }
                pre code {
                    padding: 0;
                    background-color: transparent;
                }
                blockquote {
                    border-left: 4px solid #007aff;
                    padding-left: 16px;
                    margin: 16px 0;
                    color: #636366;
                    font-style: italic;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-bottom: 16px;
                }
                th, td {
                    border: 1px solid #e5e5e5;
                    padding: 12px;
                    text-align: left;
                }
                th {
                    background-color: #f5f5f7;
                    font-weight: 600;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
            <script>
                window.onload = function() {
                    window.webkit.messageHandlers.heightHandler.postMessage(document.body.scrollHeight);
                };
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - HTML WebView

@available(iOS 14.0, *)
struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    @Binding var dynamicHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        let configuration = webView.configuration
        configuration.userContentController.add(context.coordinator, name: "heightHandler")

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLWebView

        init(_ parent: HTMLWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self?.parent.dynamicHeight = height
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightHandler", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = height
                }
            }
        }
    }
}

// MARK: - Preview

@available(iOS 14.0, *)
struct ArticleDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleArticle = KnowledgeBaseArticle(
            id: "1",
            title: "Getting Started with Our Platform",
            content: """
            <h2>Introduction</h2>
            <p>Welcome to our platform! This guide will help you get started quickly.</p>
            <h2>Step 1: Create an Account</h2>
            <p>First, you'll need to create an account. Click the "Sign Up" button and fill in your details.</p>
            <h3>Required Information</h3>
            <ul>
                <li>Email address</li>
                <li>Password</li>
                <li>Full name</li>
            </ul>
            <h2>Step 2: Configure Your Settings</h2>
            <p>After creating your account, navigate to the Settings page to customize your experience.</p>
            """,
            category: "Getting Started",
            categoryName: "Getting Started",
            tags: ["beginner", "setup"],
            description: "Learn how to get started with our platform",
            author: KnowledgeBaseAuthor(name: "John Doe", email: "john@example.com")
        )

        ArticleDetailView(article: sampleArticle, onBack: {})
    }
}
