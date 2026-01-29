//
//  KnowledgeBase.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

// MARK: - Knowledge Base Article

/// Represents a knowledge base article
public struct KnowledgeBaseArticle: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let content: String
    public let category: String
    public let categoryId: String?
    public let categoryName: String?
    public let tags: [String]
    public let createdAt: Date
    public let updatedAt: Date?
    public let publishedDate: Date?
    public let description: String?
    public let coverImage: String?
    public let author: KnowledgeBaseAuthor?
    public let viewCount: Int?
    public let helpfulCount: Int?
    public let notHelpfulCount: Int?

    public init(
        id: String,
        title: String,
        content: String,
        category: String,
        categoryId: String? = nil,
        categoryName: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        publishedDate: Date? = nil,
        description: String? = nil,
        coverImage: String? = nil,
        author: KnowledgeBaseAuthor? = nil,
        viewCount: Int? = nil,
        helpfulCount: Int? = nil,
        notHelpfulCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.publishedDate = publishedDate
        self.description = description
        self.coverImage = coverImage
        self.author = author
        self.viewCount = viewCount
        self.helpfulCount = helpfulCount
        self.notHelpfulCount = notHelpfulCount
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title
        case content
        case category
        case categoryId
        case categoryName
        case tags
        case createdAt
        case updatedAt
        case publishedDate
        case description
        case coverImage
        case author
        case viewCount
        case helpfulCount
        case notHelpfulCount
    }

    public static func == (lhs: KnowledgeBaseArticle, rhs: KnowledgeBaseArticle) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Calculate estimated reading time based on content length
    public var readingTime: String {
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let minutes = max(1, Int(ceil(Double(wordCount) / 200.0)))
        return minutes == 1 ? "1 min read" : "\(minutes) min read"
    }

    /// Formatted published date string
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: publishedDate ?? createdAt)
    }
}

// MARK: - Knowledge Base Category

/// Represents a knowledge base category
public struct KnowledgeBaseCategory: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let articleCount: Int
    public let icon: String?
    public let articles: [KnowledgeBaseArticle]?
    public let order: Int?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        articleCount: Int = 0,
        icon: String? = nil,
        articles: [KnowledgeBaseArticle]? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.articleCount = articleCount
        self.icon = icon
        self.articles = articles
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case description
        case articleCount
        case icon
        case articles
        case order
    }

    public static func == (lhs: KnowledgeBaseCategory, rhs: KnowledgeBaseCategory) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Knowledge Base Author

/// Represents an article author
public struct KnowledgeBaseAuthor: Codable, Equatable, Hashable {
    public let id: String?
    public let name: String
    public let email: String?
    public let avatar: String?

    public init(
        id: String? = nil,
        name: String,
        email: String? = nil,
        avatar: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case email
        case avatar
    }
}

// MARK: - Article Rating

/// Represents a user's rating of an article
public struct ArticleRating: Codable {
    public let articleId: String
    public let rating: Int
    public let helpful: Bool
    public let visitorId: String?
    public let sessionId: String?

    public init(
        articleId: String,
        rating: Int,
        helpful: Bool,
        visitorId: String? = nil,
        sessionId: String? = nil
    ) {
        self.articleId = articleId
        self.rating = rating
        self.helpful = helpful
        self.visitorId = visitorId
        self.sessionId = sessionId
    }
}

// MARK: - Article Engagement

/// Tracks user engagement with an article
public struct ArticleEngagement: Codable {
    public let articleId: String
    public let visitorId: String?
    public let sessionId: String?
    public let timeSpent: Int // in seconds
    public let scrollDepth: Int // percentage
    public let isCompleted: Bool
    public let device: String

    public init(
        articleId: String,
        visitorId: String? = nil,
        sessionId: String? = nil,
        timeSpent: Int = 0,
        scrollDepth: Int = 0,
        isCompleted: Bool = false,
        device: String = "iOS"
    ) {
        self.articleId = articleId
        self.visitorId = visitorId
        self.sessionId = sessionId
        self.timeSpent = timeSpent
        self.scrollDepth = scrollDepth
        self.isCompleted = isCompleted
        self.device = device
    }
}

// MARK: - Article View

/// Tracks an article view event
public struct ArticleView: Codable {
    public let articleId: String
    public let visitorId: String?
    public let sessionId: String?
    public let referrer: String?
    public let device: String

    public init(
        articleId: String,
        visitorId: String? = nil,
        sessionId: String? = nil,
        referrer: String? = nil,
        device: String = "iOS"
    ) {
        self.articleId = articleId
        self.visitorId = visitorId
        self.sessionId = sessionId
        self.referrer = referrer
        self.device = device
    }
}

// MARK: - Knowledge Base Search Result

/// Represents a search result from the knowledge base
public struct KnowledgeBaseSearchResult {
    public let article: KnowledgeBaseArticle
    public let score: Double
    public let matchedFields: [String]

    public init(
        article: KnowledgeBaseArticle,
        score: Double = 0,
        matchedFields: [String] = []
    ) {
        self.article = article
        self.score = score
        self.matchedFields = matchedFields
    }
}

// MARK: - Knowledge Base State

/// Represents the current state of the knowledge base
public enum KnowledgeBaseLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Table of Contents

/// Represents a heading in the table of contents
public struct TableOfContentsItem: Identifiable, Hashable {
    public let id: String
    public let text: String
    public let level: Int // 1 = h1, 2 = h2, 3 = h3

    public init(id: String, text: String, level: Int) {
        self.id = id
        self.text = text
        self.level = level
    }
}
