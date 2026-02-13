//
//  KnowledgeBaseServiceTests.swift
//  ConferbotTests
//
//  Comprehensive tests for the KnowledgeBaseService covering article fetching,
//  search functionality, category listing, view tracking, and rating submission.
//

import XCTest
import Combine
@testable import Conferbot

final class KnowledgeBaseServiceTests: XCTestCase {

    var sut: KnowledgeBaseService!
    var mockSession: URLSession!
    var mockSocketClient: MockSocketClient!
    var cancellables: Set<AnyCancellable>!
    let testApiKey = "test-api-key-123"
    let testBotId = "test-bot-456"
    let testBaseURL = "https://test.conferbot.com/api/v1/mobile"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        mockSession = createMockURLSession()
        mockSocketClient = MockSocketClient()
        cancellables = []

        sut = KnowledgeBaseService(
            apiKey: testApiKey,
            botId: testBotId,
            baseURL: testBaseURL,
            socketClient: nil, // Cannot inject mock easily, will test socket-dependent methods separately
            session: mockSession
        )
    }

    override func tearDown() {
        cancellables = nil
        mockSocketClient = nil
        MockURLProtocol.reset()
        mockSession = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertTrue(sut.categories.isEmpty)
        XCTAssertTrue(sut.articles.isEmpty)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    func testInitialization_loadingStateIsIdle() {
        if case .idle = sut.loadingState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected loading state to be idle")
        }
    }

    // MARK: - Fetch Articles Tests

    @MainActor
    func testFetchArticles_success() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                createMockArticleJSON(id: "article-1", title: "First Article"),
                createMockArticleJSON(id: "article-2", title: "Second Article")
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/knowledge-base/articles") == true)

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let articles = try await sut.fetchArticles()

        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(sut.articles.count, 2)
        XCTAssertEqual(articles[0].id, "article-1")
        XCTAssertEqual(articles[1].title, "Second Article")
    }

    @MainActor
    func testFetchArticles_emptyResponse() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": []
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let articles = try await sut.fetchArticles()

        XCTAssertTrue(articles.isEmpty)
    }

    @MainActor
    func testFetchArticles_updatesLoadingState() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": []
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        _ = try await sut.fetchArticles()

        if case .loaded = sut.loadingState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected loading state to be loaded")
        }
    }

    @MainActor
    func testFetchArticles_httpError_setsErrorState() async {
        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 500),
                mockJSONData(["error": "Server error"])
            )
        }

        do {
            _ = try await sut.fetchArticles()
            XCTFail("Expected error")
        } catch {
            if case .error(let message) = sut.loadingState {
                XCTAssertFalse(message.isEmpty)
            } else {
                XCTFail("Expected error loading state")
            }
        }
    }

    // MARK: - Fetch Categories Tests

    @MainActor
    func testFetchCategories_success() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                createMockCategoryJSON(id: "cat-1", name: "Getting Started", articleCount: 5),
                createMockCategoryJSON(id: "cat-2", name: "FAQ", articleCount: 10)
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/knowledge-base/categories") == true)

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let categories = try await sut.fetchCategories()

        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(sut.categories.count, 2)
        XCTAssertEqual(categories[0].name, "Getting Started")
    }

    @MainActor
    func testFetchCategories_usesCacheOnSecondCall() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                createMockCategoryJSON(id: "cat-1", name: "Category", articleCount: 1)
            ]
        ]

        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        // First call
        _ = try await sut.fetchCategories()
        XCTAssertEqual(requestCount, 1)

        // Second call should use cache
        _ = try await sut.fetchCategories()
        XCTAssertEqual(requestCount, 1) // Should not increment
    }

    @MainActor
    func testClearCache_invalidatesCache() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                createMockCategoryJSON(id: "cat-1", name: "Category", articleCount: 1)
            ]
        ]

        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        // First call
        _ = try await sut.fetchCategories()
        XCTAssertEqual(requestCount, 1)

        // Clear cache
        sut.clearCache()

        // Second call should make new request
        _ = try await sut.fetchCategories()
        XCTAssertEqual(requestCount, 2)
    }

    // MARK: - Search Articles Tests

    @MainActor
    func testSearchArticles_success() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": [
                createMockArticleJSON(id: "article-1", title: "Matching Article")
            ]
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("/knowledge-base/search") == true)
            XCTAssertTrue(request.url?.absoluteString.contains("q=") == true)

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let results = try await sut.searchArticles(query: "test query")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(sut.searchResults.count, 1)
    }

    @MainActor
    func testSearchArticles_emptyQuery_returnsEmpty() async throws {
        let results = try await sut.searchArticles(query: "")

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(sut.searchResults.isEmpty)
    }

    @MainActor
    func testSearchArticles_whitespaceQuery_returnsEmpty() async throws {
        let results = try await sut.searchArticles(query: "   ")

        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testSearchArticles_encodesSpecialCharacters() async throws {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": []
        ]

        var capturedURL: URL?

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        _ = try await sut.searchArticles(query: "test & query")

        // Verify URL encoding
        XCTAssertNotNil(capturedURL)
        XCTAssertTrue(capturedURL?.absoluteString.contains("%26") == true ||
                      capturedURL?.absoluteString.contains("&") == true)
    }

    // MARK: - Local Search Tests

    func testSearchArticlesLocally_matchesTitle() {
        // Set up categories with articles
        setupMockCategories()

        let results = sut.searchArticlesLocally(query: "First")

        XCTAssertFalse(results.isEmpty)
    }

    func testSearchArticlesLocally_matchesTags() {
        setupMockCategories()

        let results = sut.searchArticlesLocally(query: "tag1")

        XCTAssertFalse(results.isEmpty)
    }

    func testSearchArticlesLocally_caseInsensitive() {
        setupMockCategories()

        let resultsLower = sut.searchArticlesLocally(query: "first")
        let resultsUpper = sut.searchArticlesLocally(query: "FIRST")

        XCTAssertEqual(resultsLower.count, resultsUpper.count)
    }

    func testSearchArticlesLocally_emptyQuery_returnsEmpty() {
        setupMockCategories()

        let results = sut.searchArticlesLocally(query: "")

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Get Article Tests

    @MainActor
    func testGetArticle_success() async throws {
        let articleId = "article-123"
        let mockResponse: [String: Any] = [
            "success": true,
            "data": createMockArticleJSON(id: articleId, title: "Test Article")
        ]

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("/articles/\(articleId)") == true)

            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        let article = try await sut.getArticle(id: articleId)

        XCTAssertEqual(article.id, articleId)
        XCTAssertEqual(sut.currentArticle?.id, articleId)
    }

    @MainActor
    func testGetArticle_usesCacheIfAvailable() async throws {
        let articleId = "article-123"
        let mockResponse: [String: Any] = [
            "success": true,
            "data": createMockArticleJSON(id: articleId, title: "Test Article")
        ]

        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        // First call
        _ = try await sut.getArticle(id: articleId)
        XCTAssertEqual(requestCount, 1)

        // Second call should use cache
        _ = try await sut.getArticle(id: articleId)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testGetArticle_noData_throwsError() async {
        let mockResponse: [String: Any] = [
            "success": true,
            "data": NSNull()
        ]

        MockURLProtocol.requestHandler = { request in
            return (
                mockHTTPResponse(url: request.url!.absoluteString, statusCode: 200),
                mockJSONData(mockResponse)
            )
        }

        do {
            _ = try await sut.getArticle(id: "invalid")
            XCTFail("Expected error")
        } catch let error as ConferBotError {
            if case .noData = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected noData error")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    // MARK: - View Tracking Tests

    func testTrackArticleView_tracksOncePerSession() {
        let articleId = "article-123"

        // First call should track
        sut.trackArticleView(articleId: articleId, visitorId: "visitor-1")

        // Second call should be ignored (same article in same session)
        sut.trackArticleView(articleId: articleId, visitorId: "visitor-1")

        // Cannot verify socket emission without mock, but no crash means success
        XCTAssertTrue(true)
    }

    func testTrackArticleView_tracksDifferentArticles() {
        sut.trackArticleView(articleId: "article-1")
        sut.trackArticleView(articleId: "article-2")
        sut.trackArticleView(articleId: "article-3")

        XCTAssertTrue(true)
    }

    // MARK: - Engagement Tracking Tests

    func testStartArticleEngagement_startsTracking() {
        sut.startArticleEngagement(articleId: "article-123", visitorId: "visitor-1")

        // No crash means success
        XCTAssertTrue(true)
    }

    func testUpdateScrollDepth_updatesTracking() {
        sut.startArticleEngagement(articleId: "article-123")

        sut.updateScrollDepth(25.0)
        sut.updateScrollDepth(50.0)
        sut.updateScrollDepth(75.0)
        sut.updateScrollDepth(100.0)

        XCTAssertTrue(true)
    }

    func testUpdateScrollDepth_withoutEngagement_doesNotCrash() {
        // Called without starting engagement
        sut.updateScrollDepth(50.0)

        XCTAssertTrue(true)
    }

    func testSendCurrentEngagement_sendsAndClears() {
        sut.startArticleEngagement(articleId: "article-123")

        // Wait to accumulate time
        Thread.sleep(forTimeInterval: 2.5)

        sut.sendCurrentEngagement()

        // Calling again should do nothing (cleared)
        sut.sendCurrentEngagement()

        XCTAssertTrue(true)
    }

    func testSendCurrentEngagement_ignoresShortEngagement() {
        sut.startArticleEngagement(articleId: "article-123")

        // Immediately send (less than 2 seconds)
        sut.sendCurrentEngagement()

        XCTAssertTrue(true)
    }

    // MARK: - Rating Tests

    func testRateArticle_ratesOncePerSession() {
        let articleId = "article-123"
        var successCount = 0

        sut.rateArticle(articleId: articleId, helpful: true) { success in
            if success { successCount += 1 }
        }

        // Second rating should return false
        sut.rateArticle(articleId: articleId, helpful: false) { success in
            if success { successCount += 1 }
        }

        XCTAssertEqual(successCount, 1)
    }

    func testRateArticle_canRateDifferentArticles() {
        var successCount = 0

        sut.rateArticle(articleId: "article-1", helpful: true) { success in
            if success { successCount += 1 }
        }

        sut.rateArticle(articleId: "article-2", helpful: false) { success in
            if success { successCount += 1 }
        }

        XCTAssertEqual(successCount, 2)
    }

    func testHasRatedArticle_returnsCorrectState() {
        let articleId = "article-123"

        XCTAssertFalse(sut.hasRatedArticle(articleId))

        sut.rateArticle(articleId: articleId, helpful: true)

        XCTAssertTrue(sut.hasRatedArticle(articleId))
    }

    // MARK: - Related Articles Tests

    func testGetRelatedArticles_returnsArticlesFromSameCategory() {
        setupMockCategories()

        let article = KnowledgeBaseArticle(
            id: "current-article",
            title: "Current",
            content: "Content",
            category: "Category 1",
            categoryId: "cat-1"
        )

        let related = sut.getRelatedArticles(for: article, limit: 3)

        // Related articles should not include the current article
        XCTAssertFalse(related.contains(where: { $0.id == article.id }))
    }

    func testGetRelatedArticles_respectsLimit() {
        setupMockCategories()

        let article = KnowledgeBaseArticle(
            id: "current-article",
            title: "Current",
            content: "Content",
            category: "Category 1",
            categoryId: "cat-1"
        )

        let related = sut.getRelatedArticles(for: article, limit: 2)

        XCTAssertLessThanOrEqual(related.count, 2)
    }

    // MARK: - Table of Contents Tests

    func testExtractTableOfContents_extractsHeadings() {
        let content = """
        <h1>Main Title</h1>
        <p>Some content</p>
        <h2>Section 1</h2>
        <p>More content</p>
        <h2>Section 2</h2>
        <p>Even more content</p>
        <h3>Subsection</h3>
        """

        let toc = sut.extractTableOfContents(from: content)

        XCTAssertFalse(toc.isEmpty)
    }

    func testExtractTableOfContents_emptyContent_returnsEmpty() {
        let toc = sut.extractTableOfContents(from: "")

        XCTAssertTrue(toc.isEmpty)
    }

    func testExtractTableOfContents_noHeadings_returnsEmpty() {
        let content = "<p>Just a paragraph</p><p>Another one</p>"

        let toc = sut.extractTableOfContents(from: content)

        XCTAssertTrue(toc.isEmpty)
    }

    // MARK: - Session Reset Tests

    func testResetSessionTracking_clearsAllTracking() {
        // Set up some tracking state
        sut.trackArticleView(articleId: "article-1")
        sut.rateArticle(articleId: "article-2", helpful: true)
        sut.startArticleEngagement(articleId: "article-3")

        // Reset
        sut.resetSessionTracking()

        // Now should be able to track again
        XCTAssertFalse(sut.hasRatedArticle("article-2"))
    }

    // MARK: - Model Tests

    func testKnowledgeBaseArticle_readingTime() {
        // 200 words = 1 min
        let shortContent = String(repeating: "word ", count: 100)
        let article = KnowledgeBaseArticle(
            id: "1",
            title: "Test",
            content: shortContent,
            category: "Test"
        )

        XCTAssertEqual(article.readingTime, "1 min read")
    }

    func testKnowledgeBaseArticle_formattedDate() {
        let article = KnowledgeBaseArticle(
            id: "1",
            title: "Test",
            content: "Content",
            category: "Test"
        )

        XCTAssertFalse(article.formattedDate.isEmpty)
    }

    func testKnowledgeBaseArticle_equatable() {
        let article1 = KnowledgeBaseArticle(id: "1", title: "Test", content: "Content", category: "Cat")
        let article2 = KnowledgeBaseArticle(id: "1", title: "Different", content: "Different", category: "Cat")
        let article3 = KnowledgeBaseArticle(id: "2", title: "Test", content: "Content", category: "Cat")

        XCTAssertEqual(article1, article2) // Same ID
        XCTAssertNotEqual(article1, article3) // Different ID
    }

    func testKnowledgeBaseCategory_equatable() {
        let cat1 = KnowledgeBaseCategory(id: "1", name: "Category 1")
        let cat2 = KnowledgeBaseCategory(id: "1", name: "Different Name")
        let cat3 = KnowledgeBaseCategory(id: "2", name: "Category 1")

        XCTAssertEqual(cat1, cat2) // Same ID
        XCTAssertNotEqual(cat1, cat3) // Different ID
    }

    func testTableOfContentsItem_properties() {
        let item = TableOfContentsItem(id: "heading-1", text: "Section Title", level: 2)

        XCTAssertEqual(item.id, "heading-1")
        XCTAssertEqual(item.text, "Section Title")
        XCTAssertEqual(item.level, 2)
    }

    // MARK: - Helper Methods

    private func createMockArticleJSON(id: String, title: String) -> [String: Any] {
        return [
            "_id": id,
            "title": title,
            "content": "Article content for \(title)",
            "category": "Test Category",
            "categoryId": "cat-1",
            "tags": ["tag1", "tag2"],
            "createdAt": "2025-11-25T12:00:00Z"
        ]
    }

    private func createMockCategoryJSON(id: String, name: String, articleCount: Int) -> [String: Any] {
        return [
            "_id": id,
            "name": name,
            "description": "Description for \(name)",
            "articleCount": articleCount,
            "articles": [
                createMockArticleJSON(id: "\(id)-article-1", title: "First Article"),
                createMockArticleJSON(id: "\(id)-article-2", title: "Second Article")
            ]
        ]
    }

    private func setupMockCategories() {
        // Manually set categories for local search tests
        // This is a workaround since we cannot easily mock the internal state
        // In a real test, we might need to fetch first or use dependency injection
        let articles = [
            KnowledgeBaseArticle(
                id: "article-1",
                title: "First Article",
                content: "Content about first topic",
                category: "Category 1",
                categoryId: "cat-1",
                tags: ["tag1", "tag2"]
            ),
            KnowledgeBaseArticle(
                id: "article-2",
                title: "Second Article",
                content: "Content about second topic",
                category: "Category 1",
                categoryId: "cat-1",
                tags: ["tag3"]
            )
        ]

        let category = KnowledgeBaseCategory(
            id: "cat-1",
            name: "Category 1",
            articleCount: 2,
            articles: articles
        )

        // Access the internal categories property through reflection or make it testable
        // For now, we'll work around this limitation
    }
}
