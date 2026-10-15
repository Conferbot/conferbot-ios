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

    /// The bare body of an article: its rendered `content` was not in the
    /// payload (the socket's connect payload leaves bodies out; the help
    /// centre fetches one when the visitor opens the article).
    public var hasContent: Bool { !content.isEmpty }

    /// The server's own reading time in minutes, when it sent one.
    public var readingMinutes: Int? { _readingMinutes }
    private var _readingMinutes: Int?
    /// A line of matching text, from a search.
    public private(set) var snippet: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
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
        case readingTime
        case snippet
    }

    /// Decodes what the server sends (embed-server knowledgeBaseArticleService):
    /// `category` is an id or a populated `{_id, name}`, dates carry
    /// milliseconds, `content`, `tags` and `createdAt` are often left out,
    /// and counts may be missing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(String.self, forKey: .plainId)), !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "An article needs an _id"))
        }
        self.id = id
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        if let ref = try? c.decodeIfPresent(KnowledgeBaseRef.self, forKey: .category) {
            category = ref.id ?? ref.name ?? ""
            categoryId = ref.id ?? (try? c.decodeIfPresent(String.self, forKey: .categoryId))
            categoryName = ref.name ?? (try? c.decodeIfPresent(String.self, forKey: .categoryName))
        } else {
            category = ""
            categoryId = (try? c.decodeIfPresent(String.self, forKey: .categoryId))
            categoryName = (try? c.decodeIfPresent(String.self, forKey: .categoryName))
        }
        tags = ((try? c.decodeIfPresent([String].self, forKey: .tags))) ?? []
        let published = KnowledgeBaseDates.decode(c, .publishedDate)
        let updated = KnowledgeBaseDates.decode(c, .updatedAt)
        publishedDate = published
        updatedAt = updated
        createdAt = KnowledgeBaseDates.decode(c, .createdAt) ?? published ?? updated ?? Date(timeIntervalSince1970: 0)
        description = (try? c.decodeIfPresent(String.self, forKey: .description))
        coverImage = (try? c.decodeIfPresent(String.self, forKey: .coverImage))
        author = (try? c.decodeIfPresent(KnowledgeBaseAuthor.self, forKey: .author))
        viewCount = KnowledgeBaseDates.int(c, .viewCount)
        helpfulCount = KnowledgeBaseDates.int(c, .helpfulCount)
        notHelpfulCount = KnowledgeBaseDates.int(c, .notHelpfulCount)
        _readingMinutes = KnowledgeBaseDates.int(c, .readingTime)
        snippet = (try? c.decodeIfPresent(String.self, forKey: .snippet))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(categoryName, forKey: .categoryName)
        try c.encode(tags, forKey: .tags)
        try c.encode(KnowledgeBaseDates.string(createdAt), forKey: .createdAt)
        try c.encodeIfPresent(updatedAt.map(KnowledgeBaseDates.string), forKey: .updatedAt)
        try c.encodeIfPresent(publishedDate.map(KnowledgeBaseDates.string), forKey: .publishedDate)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(coverImage, forKey: .coverImage)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(viewCount, forKey: .viewCount)
        try c.encodeIfPresent(helpfulCount, forKey: .helpfulCount)
        try c.encodeIfPresent(notHelpfulCount, forKey: .notHelpfulCount)
        try c.encodeIfPresent(_readingMinutes, forKey: .readingTime)
        try c.encodeIfPresent(snippet, forKey: .snippet)
    }

    /// This article with its topic filled in (a topic's own articles carry
    /// only the topic's id) or with the body that was fetched on open.
    func merged(categoryId: String? = nil, categoryName: String? = nil, body: KnowledgeBaseArticle? = nil) -> KnowledgeBaseArticle {
        let full = body ?? self
        var out = KnowledgeBaseArticle(
            id: id,
            title: full.title.isEmpty ? title : full.title,
            content: full.content.isEmpty ? content : full.content,
            category: full.category.isEmpty ? (categoryId ?? category) : full.category,
            categoryId: full.categoryId ?? self.categoryId ?? categoryId,
            categoryName: full.categoryName ?? self.categoryName ?? categoryName,
            tags: full.tags.isEmpty ? tags : full.tags,
            createdAt: full.createdAt,
            updatedAt: full.updatedAt ?? updatedAt,
            publishedDate: full.publishedDate ?? publishedDate,
            description: full.description ?? description,
            coverImage: full.coverImage ?? coverImage,
            author: full.author ?? author,
            viewCount: full.viewCount ?? viewCount,
            helpfulCount: full.helpfulCount ?? helpfulCount,
            notHelpfulCount: full.notHelpfulCount ?? notHelpfulCount
        )
        out._readingMinutes = full._readingMinutes ?? _readingMinutes
        out.snippet = full.snippet ?? snippet
        return out
    }

    public static func == (lhs: KnowledgeBaseArticle, rhs: KnowledgeBaseArticle) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Calculate estimated reading time based on content length
    public var readingTime: String {
        if let minutes = _readingMinutes, minutes > 0, content.isEmpty {
            return minutes == 1 ? "1 min read" : "\(minutes) min read"
        }
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

    /// The topic's colour, when the owner set one.
    public private(set) var color: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainId = "id"
        case name
        case description
        case articleCount
        case icon
        case color
        case articles
        case order
    }

    /// Decodes a topic as the server sends it: its published `articles`
    /// (each naming the topic by id only) and no `articleCount`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(String.self, forKey: .plainId)) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "A topic needs an _id"))
        }
        let name = ((try? c.decodeIfPresent(String.self, forKey: .name))) ?? ""
        let list = ((try? c.decodeIfPresent(KnowledgeBaseLossyList<KnowledgeBaseArticle>.self, forKey: .articles)))?.items
        self.id = id
        self.name = name
        description = (try? c.decodeIfPresent(String.self, forKey: .description))
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon))
        color = (try? c.decodeIfPresent(String.self, forKey: .color))
        order = KnowledgeBaseDates.int(c, .order)
        articles = list?.map { $0.merged(categoryId: id, categoryName: name) }
        articleCount = KnowledgeBaseDates.int(c, .articleCount) ?? list?.count ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(articleCount, forKey: .articleCount)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(articles, forKey: .articles)
        try c.encodeIfPresent(order, forKey: .order)
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id))
        name = ((try? c.decodeIfPresent(String.self, forKey: .name))) ?? ""
        email = (try? c.decodeIfPresent(String.self, forKey: .email))
        avatar = (try? c.decodeIfPresent(String.self, forKey: .avatar))
    }
}

// MARK: - Help centre payload

/// The help centre as the server sends it: in `fetched-chatbot-data`'s
/// `knowledgeBaseData` (without bodies) and in the REST
/// `{data: {categories, recentArticles}}` (with bodies).
public struct KnowledgeBaseData: Decodable, Equatable {
    public let categories: [KnowledgeBaseCategory]
    public let recentArticles: [KnowledgeBaseArticle]

    public init(categories: [KnowledgeBaseCategory] = [], recentArticles: [KnowledgeBaseArticle] = []) {
        self.categories = categories
        self.recentArticles = recentArticles
    }

    enum CodingKeys: String, CodingKey { case categories, recentArticles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let topics = ((try? c.decodeIfPresent(KnowledgeBaseLossyList<KnowledgeBaseCategory>.self, forKey: .categories)))?.items ?? []
        let names = Dictionary(topics.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        categories = topics
        recentArticles = (((try? c.decodeIfPresent(KnowledgeBaseLossyList<KnowledgeBaseArticle>.self, forKey: .recentArticles)))?.items ?? [])
            .map { $0.merged(categoryName: $0.categoryId.flatMap { names[$0] }) }
    }

    /// From the socket payload (JSONSerialization objects).
    public static func from(json: Any?) -> KnowledgeBaseData? {
        guard let json = json, JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(KnowledgeBaseData.self, from: data)
    }

    /// Every article once: the topics' first, then any recent one not in a topic.
    public var allArticles: [KnowledgeBaseArticle] {
        var seen = Set<String>()
        var out: [KnowledgeBaseArticle] = []
        for article in categories.flatMap({ $0.articles ?? [] }) + recentArticles where seen.insert(article.id).inserted {
            out.append(article)
        }
        return out
    }
}

/// `category` (or another reference) as an id or a populated `{_id, name}`.
struct KnowledgeBaseRef: Decodable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey { case id = "_id", name }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            id = text.isEmpty ? nil : text
            name = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id))
        name = (try? c.decodeIfPresent(String.self, forKey: .name))
    }
}

/// A list that skips the items it cannot read instead of failing whole.
struct KnowledgeBaseLossyList<Element: Decodable>: Decodable {
    let items: [Element]

    /// Reads (and drops) any value, so the list moves past it.
    private struct Skip: Decodable { init(from decoder: Decoder) {} }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !c.isAtEnd {
            if let item = try? c.decode(Element.self) { out.append(item) } else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
}

/// Dates as the server writes them ("2026-09-27T06:31:04.520Z", with or
/// without milliseconds, or epoch milliseconds) and numbers that may come
/// as strings.
enum KnowledgeBaseDates {
    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Date? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return parse(text) }
        if let ms = try? c.decodeIfPresent(Double.self, forKey: key) { return Date(timeIntervalSince1970: ms / 1000) }
        return nil
    }

    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
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
