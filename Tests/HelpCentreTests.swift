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
}
