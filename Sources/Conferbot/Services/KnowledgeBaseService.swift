//
//  KnowledgeBaseService.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
import Combine

/// Service for managing Knowledge Base operations
public class KnowledgeBaseService: ObservableObject {
    // MARK: - Published Properties

    @Published public private(set) var categories: [KnowledgeBaseCategory] = []
    @Published public private(set) var articles: [KnowledgeBaseArticle] = []
    @Published public private(set) var searchResults: [KnowledgeBaseArticle] = []
    @Published public private(set) var loadingState: KnowledgeBaseLoadingState = .idle
    @Published public private(set) var currentArticle: KnowledgeBaseArticle?

    // MARK: - Private Properties

    private let apiKey: String
    private let botId: String
    private let baseURL: String
    private let session: URLSession
    private weak var socketClient: SocketClient?

    // Analytics tracking
    private var viewedArticlesInSession: Set<String> = []
    private var ratedArticlesInSession: Set<String> = []
    private var currentEngagement: ArticleEngagementTracker?

    // Cache
    private var categoriesCache: [KnowledgeBaseCategory]?
    private var articleCache: [String: KnowledgeBaseArticle] = [:]
    private var cacheExpiration: Date?
    private let cacheDuration: TimeInterval = 15 * 60 // 15 minutes

    private var headers: [String: String] {
        return [
            ConferBotConstants.headerApiKey: apiKey,
            ConferBotConstants.headerBotId: botId,
            ConferBotConstants.headerPlatform: ConferBotConstants.platformIdentifier,
            "Content-Type": "application/json"
        ]
    }

    // MARK: - Initialization

    public init(
        apiKey: String,
        botId: String,
        baseURL: String = ConferBotConstants.defaultApiBaseURL,
        socketClient: SocketClient? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.baseURL = baseURL
        self.socketClient = socketClient
        self.session = session
    }

    // MARK: - Public Methods

    /// Fetch all articles from the knowledge base
    @MainActor
    public func fetchArticles() async throws -> [KnowledgeBaseArticle] {
        loadingState = .loading

        do {
            let url = URL(string: "\(baseURL)/knowledge-base/articles")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = ConferBotConstants.apiTimeout
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConferBotError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let apiResponse = try decoder.decode(KnowledgeBaseArticlesResponse.self, from: data)
            let fetchedArticles = apiResponse.data ?? []

            articles = fetchedArticles
            loadingState = .loaded

            // Cache articles
            for article in fetchedArticles {
                articleCache[article.id] = article
            }

            return fetchedArticles
        } catch {
            loadingState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Fetch all categories with their articles
    @MainActor
    public func fetchCategories() async throws -> [KnowledgeBaseCategory] {
        // Check cache first
        if let cached = categoriesCache,
           let expiration = cacheExpiration,
           Date() < expiration {
            categories = cached
            return cached
        }

        loadingState = .loading

        do {
            let url = URL(string: "\(baseURL)/knowledge-base/categories")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = ConferBotConstants.apiTimeout
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConferBotError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let apiResponse = try decoder.decode(KnowledgeBaseCategoriesResponse.self, from: data)
            let fetchedCategories = apiResponse.data ?? []

            categories = fetchedCategories
            loadingState = .loaded

            // Update cache
            categoriesCache = fetchedCategories
            cacheExpiration = Date().addingTimeInterval(cacheDuration)

            // Cache articles from categories
            for category in fetchedCategories {
                if let categoryArticles = category.articles {
                    for article in categoryArticles {
                        articleCache[article.id] = article
                    }
                }
            }

            return fetchedCategories
        } catch {
            loadingState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Search articles by query string
    @MainActor
    public func searchArticles(query: String) async throws -> [KnowledgeBaseArticle] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return []
        }

        loadingState = .loading

        do {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = URL(string: "\(baseURL)/knowledge-base/search?q=\(encodedQuery)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = ConferBotConstants.apiTimeout
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConferBotError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let apiResponse = try decoder.decode(KnowledgeBaseArticlesResponse.self, from: data)
            let results = apiResponse.data ?? []

            searchResults = results
            loadingState = .loaded

            return results
        } catch {
            loadingState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Local search through cached articles
    public func searchArticlesLocally(query: String) -> [KnowledgeBaseArticle] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lowercasedQuery = query.lowercased()

        // Get all articles from categories
        var allArticles: [KnowledgeBaseArticle] = []
        for category in categories {
            if let categoryArticles = category.articles {
                allArticles.append(contentsOf: categoryArticles)
            }
        }

        // Filter articles matching query
        let results = allArticles.filter { article in
            article.title.lowercased().contains(lowercasedQuery) ||
            (article.description?.lowercased().contains(lowercasedQuery) ?? false) ||
            article.content.lowercased().contains(lowercasedQuery) ||
            article.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }

        return results
    }

    /// Get a specific article by ID
    @MainActor
    public func getArticle(id: String) async throws -> KnowledgeBaseArticle {
        // Check cache first
        if let cached = articleCache[id] {
            currentArticle = cached
            return cached
        }

        loadingState = .loading

        do {
            let url = URL(string: "\(baseURL)/knowledge-base/articles/\(id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = ConferBotConstants.apiTimeout
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ConferBotError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let apiResponse = try decoder.decode(KnowledgeBaseArticleResponse.self, from: data)

            guard let article = apiResponse.data else {
                throw ConferBotError.noData
            }

            currentArticle = article
            articleCache[id] = article
            loadingState = .loaded

            return article
        } catch {
            loadingState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Track article view (only once per session per article)
    public func trackArticleView(articleId: String, visitorId: String? = nil, sessionId: String? = nil) {
        // Check if article was already viewed in this session
        guard !viewedArticlesInSession.contains(articleId) else {
            return
        }

        viewedArticlesInSession.insert(articleId)

        let viewData: [String: Any] = [
            "articleId": articleId,
            "visitorId": visitorId ?? "",
            "sessionId": sessionId ?? "",
            "referrer": "",
            "device": "iOS"
        ]

        socketClient?.emit(SocketEvents.trackArticleView, viewData)

        debugPrint("[KnowledgeBase] Tracked article view: \(articleId)")
    }

    /// Start tracking engagement for an article
    public func startArticleEngagement(articleId: String, visitorId: String? = nil, sessionId: String? = nil) {
        // Send previous engagement data if exists
        sendCurrentEngagement()

        // Start new engagement tracking
        currentEngagement = ArticleEngagementTracker(
            articleId: articleId,
            visitorId: visitorId,
            sessionId: sessionId,
            startTime: Date()
        )

        debugPrint("[KnowledgeBase] Started engagement tracking for: \(articleId)")
    }

    /// Update scroll depth during article reading
    public func updateScrollDepth(_ scrollDepth: Double) {
        guard var engagement = currentEngagement else { return }

        let depth = Int(scrollDepth)
        if depth > engagement.maxScrollDepth {
            engagement.maxScrollDepth = depth
            if depth >= 90 {
                engagement.isCompleted = true
            }
            currentEngagement = engagement
        }
    }

    /// Send article engagement data to server
    public func sendCurrentEngagement() {
        guard let engagement = currentEngagement else { return }

        let timeSpent = Int(Date().timeIntervalSince(engagement.startTime))

        // Only send if user spent at least 2 seconds
        guard timeSpent >= 2 else {
            currentEngagement = nil
            return
        }

        let engagementData: [String: Any] = [
            "articleId": engagement.articleId,
            "visitorId": engagement.visitorId ?? "",
            "sessionId": engagement.sessionId ?? "",
            "timeSpent": timeSpent,
            "scrollDepth": engagement.maxScrollDepth,
            "isCompleted": engagement.isCompleted,
            "device": "iOS"
        ]

        socketClient?.emit(SocketEvents.trackArticleEngagement, engagementData)

        debugPrint("[KnowledgeBase] Sent engagement data for: \(engagement.articleId)")
        currentEngagement = nil
    }

    /// Rate article (helpful/not helpful) - only once per session per article
    public func rateArticle(
        articleId: String,
        helpful: Bool,
        visitorId: String? = nil,
        sessionId: String? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        // Check if article was already rated in this session
        guard !ratedArticlesInSession.contains(articleId) else {
            completion?(false)
            return
        }

        ratedArticlesInSession.insert(articleId)

        let ratingData: [String: Any] = [
            "articleId": articleId,
            "visitorId": visitorId ?? "",
            "sessionId": sessionId ?? "",
            "helpful": helpful,
            "rating": helpful ? 5 : 1
        ]

        socketClient?.emit(SocketEvents.rateArticle, ratingData)

        debugPrint("[KnowledgeBase] Rated article \(articleId): \(helpful ? "helpful" : "not helpful")")
        completion?(true)
    }

    /// Check if article has been rated in this session
    public func hasRatedArticle(_ articleId: String) -> Bool {
        return ratedArticlesInSession.contains(articleId)
    }

    /// Get related articles based on same category
    public func getRelatedArticles(for article: KnowledgeBaseArticle, limit: Int = 3) -> [KnowledgeBaseArticle] {
        var allArticles: [KnowledgeBaseArticle] = []

        for category in categories {
            if let categoryArticles = category.articles {
                allArticles.append(contentsOf: categoryArticles)
            }
        }

        // Filter out current article and prioritize same category
        let related = allArticles
            .filter { $0.id != article.id }
            .sorted { a, b in
                let aInCategory = a.categoryId == article.categoryId
                let bInCategory = b.categoryId == article.categoryId
                if aInCategory != bInCategory {
                    return aInCategory
                }
                return false
            }
            .prefix(limit)

        return Array(related)
    }

    /// Extract table of contents headings from article content
    public func extractTableOfContents(from content: String) -> [TableOfContentsItem] {
        var items: [TableOfContentsItem] = []

        // Simple regex to find h1, h2, h3 tags
        let patterns = [
            (pattern: "<h1[^>]*>([^<]+)</h1>", level: 1),
            (pattern: "<h2[^>]*>([^<]+)</h2>", level: 2),
            (pattern: "<h3[^>]*>([^<]+)</h3>", level: 3)
        ]

        for (pattern, level) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                let matches = regex.matches(in: content, options: [], range: range)

                for (index, match) in matches.enumerated() {
                    if let textRange = Range(match.range(at: 1), in: content) {
                        let text = String(content[textRange])
                        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let id = "heading-\(level)-\(index)-\(cleanText.lowercased().replacingOccurrences(of: " ", with: "-"))"
                        items.append(TableOfContentsItem(id: id, text: cleanText, level: level))
                    }
                }
            }
        }

        return items.sorted { $0.level < $1.level }
    }

    /// Clear cache
    public func clearCache() {
        categoriesCache = nil
        articleCache.removeAll()
        cacheExpiration = nil
    }

    /// Reset session tracking
    public func resetSessionTracking() {
        viewedArticlesInSession.removeAll()
        ratedArticlesInSession.removeAll()
        currentEngagement = nil
    }

    // MARK: - Private Methods

    private func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - API Response Types

private struct KnowledgeBaseArticlesResponse: Codable {
    let success: Bool
    let data: [KnowledgeBaseArticle]?
    let error: String?
    let message: String?
}

private struct KnowledgeBaseCategoriesResponse: Codable {
    let success: Bool
    let data: [KnowledgeBaseCategory]?
    let error: String?
    let message: String?
}

private struct KnowledgeBaseArticleResponse: Codable {
    let success: Bool
    let data: KnowledgeBaseArticle?
    let error: String?
    let message: String?
}

// MARK: - Engagement Tracker

private struct ArticleEngagementTracker {
    let articleId: String
    let visitorId: String?
    let sessionId: String?
    let startTime: Date
    var maxScrollDepth: Int = 0
    var isCompleted: Bool = false
}
