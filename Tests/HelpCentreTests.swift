//
//  HelpCentreTests.swift
//  ConferbotTests
//
//  The help centre against payloads captured from embed-server
//  (KnowledgeBaseFixtures): the socket's knowledgeBaseData, the REST list,
//  search and article, and the on/off rules of web core/helpCentre.ts.
//

import XCTest
@testable import Conferbot

final class HelpCentreTests: XCTestCase {

    private var sut: KnowledgeBaseService!
    private let baseURL = "https://test.conferbot.com/api/v1/mobile"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        sut = KnowledgeBaseService(apiKey: "key", botId: "6ab686f8d47ff029b76892f7", baseURL: baseURL, socketClient: nil, session: createMockURLSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        sut = nil
        super.tearDown()
    }

    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    private func respond(_ body: String, status: Int = 200) {
        MockURLProtocol.requestHandler = { request in
            (mockHTTPResponse(url: request.url!.absoluteString, statusCode: status), Data(body.utf8))
        }
    }

    private func socketData() -> KnowledgeBaseData {
        let payload = json(KnowledgeBaseFixtures.socketFetchedChatbotData)
        return KnowledgeBaseData.from(json: payload["knowledgeBaseData"])!
    }

    private func date(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)!
    }

    // MARK: - Socket payload (fetched-chatbot-data)

    func testSocketPayload_decodesTopicsAndRecentArticles() {
        let help = socketData()
        XCTAssertEqual(help.categories.map(\.name), ["Chatbot Essentials", "Chatbot Creation"])
        XCTAssertEqual(help.categories[0].articleCount, 2)
        XCTAssertEqual(help.recentArticles.map(\.id), ["6ab7ac0bb03f13ff22412c87", "6ab7ac19b03f13ff22412cd5"])
        XCTAssertEqual(help.allArticles.count, 5)
    }

    func testSocketPayload_topicArticleTakesTheTopicName() {
        let article = socketData().categories[0].articles![0]
        XCTAssertEqual(article.id, "6ab7ac01b03f13ff22412c4e")
        XCTAssertEqual(article.categoryId, "6ab7abfcb03f13ff22412c36")
        XCTAssertEqual(article.categoryName, "Chatbot Essentials")
        XCTAssertEqual(article.author?.name, "admin")
    }

    func testSocketPayload_populatedCategoryAndMillisecondDates() {
        let recent = socketData().recentArticles[0]
        XCTAssertEqual(recent.category, "6ab7abfcb03f13ff22412c38")
        XCTAssertEqual(recent.categoryName, "Chatbot Creation")
        XCTAssertEqual(recent.publishedDate, date("2026-09-27T06:31:04.520Z"))
        XCTAssertEqual(recent.updatedAt, date("2026-09-27T18:35:37.072Z"))
        // No createdAt in the list fields: the published date stands in.
        XCTAssertEqual(recent.createdAt, recent.publishedDate)
        XCTAssertEqual(recent.tags, [])
        XCTAssertEqual(recent.readingMinutes, 2)
        XCTAssertEqual(recent.readingTime, "2 min read")
    }

    func testSocketPayload_hasNoBodies() {
        XCTAssertTrue(socketData().allArticles.allSatisfy { !$0.hasContent })
    }

    @MainActor
    func testApply_fillsTheServiceWithoutARequest() async throws {
        sut.apply(socketData())
        XCTAssertEqual(sut.categories.count, 2)
        XCTAssertEqual(sut.recentArticles.count, 2)
        let topics = try await sut.fetchCategories()
        XCTAssertEqual(topics.count, 2)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testLossyList_skipsAnArticleWithoutAnId() throws {
        let text = #"{"categories":[{"_id":"c1","name":"Topic","articles":[{"title":"no id"},{"_id":"a1","title":"Kept"}]}],"recentArticles":[]}"#
        let help = try JSONDecoder().decode(KnowledgeBaseData.self, from: Data(text.utf8))
        XCTAssertEqual(help.categories[0].articles?.map(\.id), ["a1"])
    }

    // MARK: - REST

    @MainActor
    func testFetchArticles_decodesTheRESTHelpCentre() async throws {
        respond(KnowledgeBaseFixtures.restArticles)
        let articles = try await sut.fetchArticles()
        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/mobile/knowledge-base/articles")
        XCTAssertEqual(sut.categories.map(\.name), ["Chatbot Essentials", "Chatbot Creation"])
        XCTAssertEqual(sut.recentArticles.count, 2)
        XCTAssertEqual(articles.count, 5)
        XCTAssertTrue(articles.allSatisfy(\.hasContent))
    }

    @MainActor
    func testFetchCategories_decodesTheCategoriesObject() async throws {
        let full = json(KnowledgeBaseFixtures.restArticles)
        let categories = (full["data"] as! [String: Any])["categories"]!
        let body = String(data: try JSONSerialization.data(withJSONObject: ["success": true, "data": ["categories": categories]]), encoding: .utf8)!
        respond(body)
        let topics = try await sut.fetchCategories()
        XCTAssertEqual(topics.map(\.name), ["Chatbot Essentials", "Chatbot Creation"])
        XCTAssertEqual(topics[1].articles?.first?.categoryName, "Chatbot Creation")
    }

    @MainActor
    func testSearch_sendsQueryNotQ() async throws {
        respond(KnowledgeBaseFixtures.restSearch)
        let results = try await sut.searchArticles(query: "set up & go")
        let url = try XCTUnwrap(MockURLProtocol.capturedRequests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/api/v1/mobile/knowledge-base/search")
        XCTAssertEqual(items.first(where: { $0.name == "query" })?.value, "set up & go")
        XCTAssertNil(items.first(where: { $0.name == "q" }))
        XCTAssertEqual(results.map(\.id), ["6ab7ac19b03f13ff22412cd5", "6ab7ac01b03f13ff22412c4e"])
        XCTAssertEqual(results[0].categoryName, "AI Chatbot Features")
        XCTAssertEqual(results[0].createdAt, date("2026-09-26T11:27:21.633Z"))
    }

    @MainActor
    func testGetArticle_fetchesTheBodyOnceForAListArticle() async throws {
        sut.apply(socketData())
        respond(KnowledgeBaseFixtures.restArticle)
        let article = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")
        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/mobile/knowledge-base/articles/6ab7ac0bb03f13ff22412c87")
        XCTAssertTrue(article.hasContent)
        XCTAssertEqual(article.categoryName, "Chatbot Creation")

        _ = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    // MARK: - Socket (web kbContent.ts: search-kb-articles, get-kb-article)

    /// The socket as the server answers it, recording what was sent.
    private func socket(_ answer: @escaping (String, [String: Any]) -> Any?) -> () -> [(String, [String: Any])] {
        var sent: [(String, [String: Any])] = []
        sut.emitWithAck = { event, data, _, done in
            sent.append((event, data))
            done(answer(event, data))
        }
        return { sent }
    }

    @MainActor
    func testSearch_overTheSocket_localTitleMatchesFirstThenServerSnippets() async throws {
        sut.apply(socketData())
        let sent = socket { _, _ in
            ["success": true, "query": "openai", "articles": [
                ["_id": "6ab7ac01b03f13ff22412c4e", "title": "How to Integrate OpenAI with Conferbot", "snippet": "connect your OpenAI key"],
                ["_id": "6ab7ac0cb03f13ff22412c8d", "title": "How to Use Rich Media in Your Conferbot Chatbot", "snippet": "images made with OpenAI"],
                ["_id": "6ab7ffffb03f13ff22419999", "title": "Not in the list yet", "snippet": "OpenAI in the body",
                 "category": ["_id": "6ab7abfcb03f13ff22412c3c", "name": "AI Chatbot Features"]],
                ["_id": "6ab7eeeeb03f13ff22418888", "title": "A draft", "reviewStatus": "draft"]
            ]]
        }

        let results = try await sut.searchArticles(query: "OpenAI ")

        // The title match from the help centre first, then the server's others, each once; no draft
        XCTAssertEqual(results.map(\.id), ["6ab7ac01b03f13ff22412c4e", "6ab7ac0cb03f13ff22412c8d", "6ab7ffffb03f13ff22419999"])
        XCTAssertEqual(results[1].snippet, "images made with OpenAI")
        XCTAssertEqual(results[1].categoryName, "Chatbot Creation") // the list's own fields kept
        XCTAssertEqual(results[2].snippet, "OpenAI in the body")
        XCTAssertEqual(results[2].categoryName, "AI Chatbot Features")
        XCTAssertEqual(sent().count, 1)
        XCTAssertEqual(sent()[0].0, "search-kb-articles")
        XCTAssertEqual(sent()[0].1["chatbotId"] as? String, "6ab686f8d47ff029b76892f7")
        XCTAssertEqual(sent()[0].1["query"] as? String, "openai")
        XCTAssertEqual(sent()[0].1["limit"] as? Int, 10)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)

        // Kept per query: the same search does not ask again
        _ = try await sut.searchArticles(query: "openai")
        XCTAssertEqual(sent().count, 1)
    }

    @MainActor
    func testSearch_socketFails_fallsBackToREST() async throws {
        let sent = socket { _, _ in ["success": false] }
        respond(KnowledgeBaseFixtures.restSearch)

        let results = try await sut.searchArticles(query: "set up & go")

        XCTAssertEqual(sent().count, 1)
        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/mobile/knowledge-base/search")
        XCTAssertEqual(results.map(\.id), ["6ab7ac19b03f13ff22412cd5", "6ab7ac01b03f13ff22412c4e"])
    }

    @MainActor
    func testSearch_oneLetterSkipsTheSocket() async throws {
        let sent = socket { _, _ in ["success": true, "articles": []] }
        respond(#"{"success":true,"data":[]}"#)

        _ = try await sut.searchArticles(query: "a")

        XCTAssertTrue(sent().isEmpty)
    }

    @MainActor
    func testGetArticle_overTheSocket() async throws {
        sut.apply(socketData())
        let sent = socket { _, data in
            ["success": true, "articleId": data["articleId"] ?? "", "article": [
                "_id": "6ab7ac0bb03f13ff22412c87", "title": "How to Use Conferbot's AI Chatbot Builder",
                "content": "<p>Open the builder.</p>", "readingTime": 3
            ]]
        }

        let article = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")

        XCTAssertEqual(article.content, "<p>Open the builder.</p>")
        XCTAssertEqual(article.categoryName, "Chatbot Creation")
        XCTAssertEqual(sent().map(\.0), ["get-kb-article"])
        XCTAssertEqual(sent()[0].1["chatbotId"] as? String, "6ab686f8d47ff029b76892f7")
        XCTAssertEqual(sent()[0].1["articleId"] as? String, "6ab7ac0bb03f13ff22412c87")
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)

        // The body is kept: opened again, nothing is asked
        _ = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")
        XCTAssertEqual(sent().count, 1)
    }

    @MainActor
    func testGetArticle_socketWithoutABody_fallsBackToREST() async throws {
        sut.apply(socketData())
        let sent = socket { _, _ in ["success": true, "article": ["_id": "6ab7ac0bb03f13ff22412c87", "title": "No body"]] }
        respond(KnowledgeBaseFixtures.restArticle)

        let article = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")

        XCTAssertEqual(sent().count, 1)
        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/mobile/knowledge-base/articles/6ab7ac0bb03f13ff22412c87")
        XCTAssertTrue(article.hasContent)
    }

    @MainActor
    func testGetArticle_noAnswer_fallsBackToREST() async throws {
        _ = socket { _, _ in nil } // timed out
        respond(KnowledgeBaseFixtures.restArticle)

        let article = try await sut.getArticle(id: "6ab7ac0bb03f13ff22412c87")

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
        XCTAssertTrue(article.hasContent)
    }

    @MainActor
    func testSocketAnswerTwice_resumesOnce() async throws {
        sut.emitWithAck = { _, _, _, done in
            done(["success": true, "articles": []])
            done(["success": true, "articles": []])
        }
        let results = try await sut.searchArticles(query: "zz")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - On / off (web core/helpCentre.ts)

    func testHelpCentre_followsTheOwnersSwitch() {
        XCTAssertTrue(HelpCentre.isOn(["enableKnowledgeBase": true]))
        XCTAssertFalse(HelpCentre.isOn(["enableKnowledgeBase": false]))
        XCTAssertFalse(HelpCentre.isOn([:]))
        XCTAssertFalse(HelpCentre.isOn(nil))
    }

    func testHelpCentre_hostCanOnlyTurnItOff() {
        let on: [String: Any] = ["enableKnowledgeBase": true]
        let off: [String: Any] = ["enableKnowledgeBase": false]
        XCTAssertTrue(HelpCentre.isShown(on, host: nil))
        XCTAssertTrue(HelpCentre.isShown(on, host: true))
        XCTAssertFalse(HelpCentre.isShown(on, host: false))
        XCTAssertFalse(HelpCentre.isShown(off, host: true))
        XCTAssertFalse(HelpCentre.isShown(nil, host: nil))
    }

    func testRecentArticles_hiddenByTheOwnerOrWithoutArticles() {
        XCTAssertTrue(HelpCentre.showsRecentArticles(["enableKnowledgeBase": true], articleCount: 2))
        XCTAssertFalse(HelpCentre.showsRecentArticles(["enableKnowledgeBase": true, "hideRecentArticles": true], articleCount: 2))
        XCTAssertFalse(HelpCentre.showsRecentArticles(["enableKnowledgeBase": true], articleCount: 0))
        XCTAssertFalse(HelpCentre.showsRecentArticles(["enableKnowledgeBase": false], articleCount: 2))
    }

    func testCanOpenArticle_onlyWhileOnAndWithAnId() {
        XCTAssertTrue(HelpCentre.canOpenArticle(["enableKnowledgeBase": true], articleId: "6ab7ac0bb03f13ff22412c87"))
        XCTAssertFalse(HelpCentre.canOpenArticle(["enableKnowledgeBase": true], articleId: ""))
        XCTAssertFalse(HelpCentre.canOpenArticle(["enableKnowledgeBase": false], articleId: "6ab7ac0bb03f13ff22412c87"))
    }

    /// #83: a wait's article (queue-help) opens even with the help centre off, fetched by id.
    func testWaitArticle_helpCentreWhileOnElseById() {
        let id = "6ab7ac0bb03f13ff22412c87"
        XCTAssertEqual(HelpCentre.waitArticleRoute(["enableKnowledgeBase": true], articleId: id), .helpCentre)
        XCTAssertEqual(HelpCentre.waitArticleRoute(["enableKnowledgeBase": false], articleId: id), .byId)
        XCTAssertEqual(HelpCentre.waitArticleRoute(nil, articleId: id), .byId)
        XCTAssertEqual(HelpCentre.waitArticleRoute(["enableKnowledgeBase": true], articleId: ""), .nowhere)
    }
}
