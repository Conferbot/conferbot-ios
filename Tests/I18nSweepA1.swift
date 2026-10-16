import XCTest
@testable import Conferbot

// The live chat, handover, "Helpful?", transcript, reply time and wait
// articles in German (RN __tests__/core/i18nCore.test.ts).
extension I18nSweepTests {

    func testHelpfulInGerman() {
        XCTAssertEqual(HelpfulText.ask, "Hilfreich?")
        XCTAssertEqual(HelpfulText.ask, de("helpful.ask"))
        XCTAssertEqual(HelpfulRow.reasons.map { $0.label },
                       ["wrong", "outdated", "unanswered", "other"].map { de("helpful.reason.\($0)") })
        XCTAssertEqual(HelpfulRow.ratedLabel(AnswerFeedback(helpful: true)), de("helpful.rated.up"))
        XCTAssertEqual(HelpfulRow.ratedLabel(AnswerFeedback(helpful: false, reason: "wrong")),
                       "\(de("helpful.rated.down")) \u{00B7} \(de("helpful.reason.wrong"))")
        for s in [HelpfulText.groupLabel, HelpfulText.yes, HelpfulText.no, HelpfulText.thanks, HelpfulText.sorry,
                  HelpfulText.comment, HelpfulText.sendFeedback, HelpfulText.retry, HelpfulText.thanksComment,
                  HelpfulText.talkToPerson, HelpfulText.talkToPersonAsk, LiveChat.talkToPersonAsk] {
            assertNoEnglish(s, "HelpfulText")
        }
    }

    func testHandoverLinesJoinsAndLeavesInGerman() {
        XCTAssertEqual(HandoverState.lineText(nil), de("handover.pending"))
        XCTAssertEqual(HandoverState.lineText(.joined), de("handover.joined"))
        XCTAssertEqual(HandoverState.joinedText("Ada"), "Ada\(de("system.joined"))")
        XCTAssertEqual(HandoverState.joinedText(""), "\(de("agent.anAgent"))\(de("system.joined"))")
        XCTAssertEqual(HandoverState.agentLeftText(nil, handover: false), "\(de("agent.theAgent"))\(de("system.left"))")
        XCTAssertEqual(HandoverState.handedOverNoteText(HandoverState.handedOverNoteMarker), de("system.handedOverNote"))
        XCTAssertEqual(HandoverState.handedOverNoteText("Own note"), "Own note")
        XCTAssertEqual(HandoverState.handedOverNote, de("system.handedOverNote"))
        for o in [HandoverOutcome.joined, .unavailable, .cancelled, .ended] { assertNoEnglish(HandoverState.text(o), "\(o)") }
        let left = AgentLeftMessageRecord(id: "l", time: Date(), agentDetails: AgentDetails(id: "", name: "", email: ""), handover: true)
        XCTAssertEqual(left.text, de("handover.pending"))
    }

    func testLiveEventsAndTheClosedChatInGerman() {
        XCTAssertEqual(LiveEvents.requeuedText(teamName: nil), de("takeover.requeued"))
        XCTAssertEqual(LiveEvents.requeuedText(teamName: "Sales"), de("takeover.requeuedTeam", ["team": "Sales"]))
        XCTAssertEqual(LiveEvents.blockedText(nil), de("system.closed"))
        // The server's stock English is drawn in German; its own words as sent.
        XCTAssertEqual(LiveEvents.blockedText(["message": LiveEvents.closedEnglish]), de("system.closed"))
        XCTAssertEqual(LiveEvents.blockedText(["message": "Gesperrt."]), "Gesperrt.")
        XCTAssertEqual(LiveEvents.newChatText, "Neuen Chat starten")
        let ended = LiveEvents.closedState([["type": "agent-joined-message"], ["type": "agent-chat-ended"]],
                                           blocked: nil, stepWaiting: false, live: false)
        XCTAssertEqual(ended?.text, de("system.chatEnded"))
        assertNoEnglish(LiveEvents.chatHasEndedText, "chatHasEnded")
        // The record keeps the English.
        XCTAssertEqual(LiveEvents.requeuedDefaultText, "Connecting you to another agent...")
    }

    func testEmailTranscriptTheServerReasonOnlyInEnglish() {
        XCTAssertEqual(EmailTranscript.Copy.title, de("chat.menu.emailChat"))
        XCTAssertEqual(EmailTranscript.Copy.sent("a@b.co"), de("mailchat.sent", ["email": "a@b.co"]))
        for s in [EmailTranscript.Copy.menu, EmailTranscript.Copy.sub, EmailTranscript.Copy.label, EmailTranscript.Copy.send,
                  EmailTranscript.Copy.sending, EmailTranscript.Copy.cancel, EmailTranscript.Copy.checkEmail] {
            assertNoEnglish(s, "EmailTranscript.Copy")
        }
        XCTAssertEqual(EmailTranscript.errorText(TranscriptEmailResult(ok: false, message: "Too many requests")), de("form.sendFailed"))
        I18n.setWidgetLanguage("en", languages: [])
        XCTAssertEqual(EmailTranscript.errorText(TranscriptEmailResult(ok: false, message: "Too many requests")), "Too many requests")
    }

    func testWhileYouWaitInGerman() {
        XCTAssertEqual(WaitArticles.Text.title, de("wait.title"))
        XCTAssertEqual(WaitArticles.Text.recordText, "Resolved while waiting")
        for s in [WaitArticles.Text.label, WaitArticles.Text.settledTitle, WaitArticles.Text.read, WaitArticles.Text.solved,
                  WaitArticles.Text.done, WaitArticles.Text.leftHelped] {
            assertNoEnglish(s, "WaitArticles.Text")
        }
    }

    func testReplyTimeOnTheHeaderAndTheHomeCardInGerman() {
        XCTAssertEqual(ReplyTime.headerStatus(nil), de("status.online"))
        XCTAssertEqual(ReplyTime.phrases["few_minutes"], de("reply.phrase.few_minutes"))
        XCTAssertEqual(ReplyTime.homePeople(["mode": "auto", "handover": true, "state": "online", "bucket": "few_minutes"]).text,
                       de("reply.usually", ["phrase": de("reply.phrase.few_minutes")]))
        XCTAssertEqual(ReplyTime.headerLine(["handover": true, "bucket": "day"]),
                       de("reply.typicallyShort", ["phrase": de("reply.phrase.day")]))
        let now = ISO8601DateFormatter().date(from: "2026-10-16T08:00:00Z")!
        let utc = TimeZone(identifier: "UTC")!
        let tomorrow = ReplyTime.backWhen("2026-10-17T09:00:00Z", now: now, timeZone: utc)
        XCTAssertTrue(tomorrow.hasPrefix("morgen"), tomorrow)
        assertNoEnglish(ReplyTime.backWhen("2026-10-16T09:00:00Z", now: now, timeZone: utc), "backWhen today")
        let cases: [[String: Any]] = [
            ["handover": true, "state": "away", "backAt": "2026-10-17T09:00:00Z"],
            ["handover": true, "state": "offline"],
            ["handover": true, "state": "offline", "leaveMessage": false],
            ["handover": true, "state": "online"],
            ["handover": true, "state": "online", "bucket": "few_hours"],
        ]
        for rt in cases {
            assertNoEnglish(ReplyTime.headerStatus(rt, now: now, timeZone: utc), "header \(rt)")
            assertNoEnglish(ReplyTime.homePeople(rt, now: now, timeZone: utc).text, "people \(rt)")
            assertNoEnglish(ReplyTime.homePeople(rt, agent: true, now: now, timeZone: utc).text, "agent people \(rt)")
            if case .line(let l)? = ReplyTime.homeLine(rt, now: now, timeZone: utc) { assertNoEnglish(l.text, "home \(rt)") }
            if case .line(let l)? = ReplyTime.homeLine(rt, agent: true, now: now, timeZone: utc) { assertNoEnglish(l.text, "agent home \(rt)") }
        }
    }

    func testQueueWaitingReceiptsAndRatingInGerman() {
        func q(_ p: Int?) -> QueueStatus { QueueStatus(status: "waiting", position: p, ahead: nil, agentsOnline: nil, estimateLabel: nil) }
        XCTAssertEqual(LiveChat.queueLine(q(1)), de("queue.next"))
        XCTAssertEqual(LiveChat.queueLine(q(3)), de("queue.position", ["n": 3, "ord": "3rd"]))
        XCTAssertEqual(LiveChat.queueLine(nil), de("queue.connecting"))
        XCTAssertEqual(LiveChat.queueSubline(q(2)), de("queue.soon"))
        for w in [HandoverWaiting(offline: false, reason: "busy", backAt: nil, askEmail: true, email: nil),
                  HandoverWaiting(offline: true, reason: "offline", backAt: nil, askEmail: false, email: "a@b.co"),
                  HandoverWaiting(offline: true, reason: "offline", backAt: "2026-10-17T09:00:00Z", askEmail: false, email: nil)] {
            assertNoEnglish(LiveChat.handoverWaitingLine(w), "waiting line")
        }
        for r in [ReceiptState.seen, .delivered, .sent] { assertNoEnglish(LiveChat.receiptLabel(r), "receipt") }
        XCTAssertEqual(LiveChat.receiptLabel(.seen), de("receipt.seen"))
        XCTAssertEqual(LiveChat.csatConfig(["enabled": true])?.titleText, de("csat.title"))
        XCTAssertEqual(LiveChat.csatConfig(["enabled": true, "titleText": "Wie war es?"])?.titleText, "Wie war es?")
        XCTAssertEqual(LiveChat.csatConfig(["enabled": true, "feedbackPlaceholder": "Tell us more..."])?.feedbackPlaceholder, de("csat.placeholder"))
        let c = LiveChat.csatConfig(["enabled": true])!
        for s in [c.subtitleText, c.thankYouText, c.feedbackPlaceholder] { assertNoEnglish(s, "csat") }
        XCTAssertEqual(LiveChat.fileName(nil, url: "https://x/"), de("file.file"))
    }

    func testAgentBotWordsInGerman() {
        XCTAssertEqual(AgentBotParser.replyTimeoutNotice().text, de("chat.replyTimeout"))
        XCTAssertEqual(AgentBotParser.defaultGreetingText, de("agent.defaultGreeting"))
        XCTAssertEqual(AgentBotParser.parseAgentBot(["agentBot": ["agentId": "a1"]])?.displayName, de("agent.defaultName"))
        let card = AgentBotParser.resultCard(["status": "ok", "link": ["url": "https://x.co/y"]])
        XCTAssertEqual(card?.title, de("result.done"))
        XCTAssertEqual(card?.linkLabel, de("result.open"))
        XCTAssertEqual(KnowledgeBaseArticle(id: "1", title: "T", content: "a b c", category: "c").readingTime, de("kb.minRead", ["n": 1]))
        assertNoEnglish(FileUploadError.noData.errorDescription, "upload")
        assertNoEnglish(FileUploadError.fileTooLarge(maxSize: 10 * 1024 * 1024).errorDescription, "upload too big")
    }
}
