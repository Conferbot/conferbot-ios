import XCTest
@testable import Conferbot

final class LiveChatTests: XCTestCase {

    func testReadsAWaitingQueueStatusAndDropsNone() {
        XCTAssertNil(LiveChat.queueStatus(["status": "none"]))
        XCTAssertNil(LiveChat.queueStatus(nil))
        let q = LiveChat.queueStatus(["status": "waiting", "position": 2, "ahead": 1, "agentsOnline": 3, "estimate": ["label": " About 2 min "]])
        XCTAssertEqual(q, QueueStatus(status: "waiting", position: 2, ahead: 1, agentsOnline: 3, estimateLabel: "About 2 min"))
    }

    func testSaysWhereTheVisitorStands() {
        XCTAssertEqual(LiveChat.queueLine(QueueStatus(status: "waiting", position: 1, ahead: 0, agentsOnline: 1, estimateLabel: nil)), "You're next in line")
        XCTAssertEqual(LiveChat.queueLine(QueueStatus(status: "waiting", position: 3, ahead: 2, agentsOnline: 1, estimateLabel: nil)), "You're 3rd in line")
        XCTAssertEqual(LiveChat.queueLine(nil), "Connecting you to the team")
        XCTAssertEqual(LiveChat.queueSubline(QueueStatus(status: "waiting", position: 1, ahead: 0, agentsOnline: 1, estimateLabel: "Under a minute")), "Under a minute")
        XCTAssertEqual(LiveChat.queueSubline(nil), "Our team will be with you soon")
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(LiveChat.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "111th"])
    }

    func testReadsHandoverWaitingAndWordsIt() {
        let w = LiveChat.handoverWaiting(["offline": false, "askEmail": true])!
        XCTAssertEqual(w.reason, "busy")
        XCTAssertEqual(LiveChat.handoverWaitingLine(w), "Everyone's busy right now. Leave your email and they will reply.")
        var withEmail = w
        withEmail.email = "jo@example.com"
        XCTAssertTrue(LiveChat.handoverWaitingLine(withEmail).hasSuffix("They'll reply to jo@example.com."))
    }

    func testLabelsBackAtTimes() {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10))!
        XCTAssertNil(LiveChat.backAtLabel(nil))
        XCTAssertNil(LiveChat.backAtLabel("nope"))
        XCTAssertFalse(LiveChat.backAtLabel("2026-10-14T15:30:00.000Z", now: now, timeZone: utc)!.contains("day"))
        XCTAssertTrue(LiveChat.backAtLabel("2026-10-16T09:00:00Z", now: now, timeZone: utc)!.hasPrefix("Friday"))
    }

    func testKeepsATranslationOnlyWithAnOriginal() {
        XCTAssertEqual(LiveChat.agentTranslation(["translation": ["from": "en", "to": "es", "original": "Hi"]]), AgentTranslation(from: "en", to: "es", original: "Hi"))
        XCTAssertNil(LiveChat.agentTranslation(["translation": ["to": "es", "original": " "]]))
        XCTAssertEqual(LiveChat.translationLabels("es-MX").0, "Ver original")
        XCTAssertEqual(LiveChat.translationLabels("xx").1, "See translation")
    }

    func testMarksTheLatestVisitorMessage() {
        let record = [LiveEntry(id: "a1", kind: "agent-message"), LiveEntry(id: "v1", kind: "user-live-message"), LiveEntry(id: "v2", kind: "user-live-message")]
        XCTAssertEqual(LiveChat.visitorReceipt(record, marks: ReceiptMarks()), VisitorReceipt(id: "v2", state: .sent))
        XCTAssertEqual(LiveChat.visitorReceipt(record, marks: ReceiptMarks(deliveredMessageId: "v2"))?.state, .delivered)
        XCTAssertEqual(LiveChat.visitorReceipt(record, marks: ReceiptMarks(deliveredMessageId: "v2", seenMessageId: "v2"))?.state, .seen)
        XCTAssertEqual(LiveChat.visitorReceipt(record, marks: ReceiptMarks(seenMessageId: "v1"))?.state, .sent)
        XCTAssertNil(LiveChat.visitorReceipt(record + [LiveEntry(id: "a2", kind: "agent-message")], marks: ReceiptMarks()))
        XCTAssertEqual(LiveChat.latestAgentMessageId(record + [LiveEntry(id: "f1", kind: "agent-message-file"), LiveEntry(id: "v3", kind: "user-live-message")]), "f1")
        XCTAssertEqual(LiveChat.latestAgentMessageId([]), "")
    }

    func testReceiptEntriesComeFromTheServerRecord() {
        let entries = LiveChatExtras.entries([["id": "m1", "shape": "user-live-message"], ["_id": "a1", "type": "agent-message"]])
        XCTAssertEqual(entries, [LiveEntry(id: "m1", kind: "user-live-message"), LiveEntry(id: "a1", kind: "agent-message")])
    }

    func testChecksEmailsAndUploads() {
        XCTAssertTrue(LiveChat.isEmail(" a@b.co "))
        XCTAssertFalse(LiveChat.isEmail("a@b"))
        XCTAssertTrue(LiveChat.visitorUploadsOn(nil))
        XCTAssertFalse(LiveChat.visitorUploadsOn(["enableVisitorFileUpload": false]))
    }

    func testReadsRatingSettingsAndBuildsThePayload() {
        XCTAssertNil(LiveChat.csatConfig(nil))
        XCTAssertNil(LiveChat.csatConfig(["ratingType": "stars"]))
        let c = LiveChat.csatConfig(["enabled": true, "ratingType": "bogus"])!
        XCTAssertEqual(c.ratingType, "stars")
        XCTAssertEqual(c.titleText, "How was your experience?")
        let stars = LiveChat.ratingPayload(chatSessionId: "s1", type: "stars", value: 4, feedback: " great ")
        XCTAssertEqual(stars["csatScore"] as? Int, 4)
        XCTAssertEqual(stars["feedback"] as? String, "great")
        XCTAssertEqual(LiveChat.ratingPayload(chatSessionId: "s1", type: "thumbs", value: false)["thumbsUp"] as? Bool, false)
        XCTAssertNil(LiveChat.ratingPayload(chatSessionId: "s1", type: "nps", value: 9, feedback: "  ")["feedback"])
    }

    func testResolvesFileLinksAndNamesThem() {
        XCTAssertEqual(LiveChat.resolveMediaURL("/api/v1/media/1", origin: "https://api.example.com/")?.absoluteString, "https://api.example.com/api/v1/media/1")
        XCTAssertNil(LiveChat.resolveMediaURL("java\nscript:alert(1)", origin: "https://a"))
        XCTAssertTrue(LiveChat.isImageURL("https://x/a.JPG?x=1"))
        XCTAssertTrue(LiveChat.isImageURL("/media/abc", mimeType: "image/png"))
        XCTAssertFalse(LiveChat.isImageURL("/media/abc"))
        XCTAssertEqual(LiveChat.fileName("Invoice.pdf", url: "/media/1"), "Invoice.pdf")
        XCTAssertEqual(LiveChat.fileName(nil, url: "https://x/My%20File.pdf?sig=1"), "My File.pdf")
    }

    func testPlainTextAndWaitMinutes() {
        XCTAssertEqual(LiveChat.plainText("<p>Please wait &amp; relax.</p>"), "Please wait & relax.")
        XCTAssertEqual(LiveChat.waitMinutes("0.5") as? Double, 0.5)
        XCTAssertEqual(LiveChat.waitMinutes("3") as? Int, 3)
        XCTAssertEqual(LiveChat.waitMinutes(1.5) as? Double, 1.5)
        XCTAssertEqual(LiveChat.waitMinutes(nil) as? Int, 2)
        XCTAssertEqual(LiveChat.waitMinutes("x") as? Int, 2)
    }

    func testAsksTheServerToDecideOnceTheMaxWaitPasses() {
        let p = LiveChat.handoverTimeoutPayload(chatSessionId: "s1", nodeData: ["assignmentType": "manual", "assignedAgents": ["a2"], "agentAssignmentStrategy": "round_robin"], workspaceId: "w1")
        XCTAssertEqual(p["chatSessionId"] as? String, "s1")
        XCTAssertEqual(p["workspaceId"] as? String, "w1")
        let a = p["assignmentData"] as? [String: Any]
        XCTAssertEqual(a?["assignmentType"] as? String, "manual")
        XCTAssertEqual(a?["assignmentStrategy"] as? String, "round_robin")
        XCTAssertEqual(a?["assignedAgents"] as? [String], ["a2"])
        XCTAssertEqual(LiveChat.waitSeconds("0.5"), 30)
        XCTAssertEqual(LiveChat.waitSeconds(nil), 120)
    }
}
