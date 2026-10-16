//
//  FlowEndRatingTests.swift
//  The post-chat rating at the flow's end (#95), as the web asks after
//  chat-flow-completed: only with the owner's post-chat feedback on, once
//  per conversation, never for a blocked visitor or over a rating already
//  up or sent, and the post-chat redirect waits for it. 1.5 s after the
//  flow's end, the conversation remembered across restarts (#98).
//

import XCTest
@testable import Conferbot

private final class RatingMemory: RedirectStore {
    var values: [String: String] = [:]
    func read(_ key: String) -> String? { values[key] }
    func write(_ key: String, _ value: String) { values[key] = value }
}

final class FlowEndRatingTests: XCTestCase {

    private var session = "s1"
    private var live: LiveChatExtras!
    private var clock: FakeClock!
    private var store: RatingMemory!

    override func setUp() {
        super.setUp()
        session = "s1"
        clock = FakeClock()
        store = RatingMemory()
        live = makeLive()
    }

    private func makeLive() -> LiveChatExtras {
        let l = LiveChatExtras(socket: { nil }, sessionId: { [unowned self] in self.session },
                               chatState: { ChatState.shared }, addMessage: { _ in }, sendRecord: {})
        l.schedule = clock.schedule
        let st = store!
        l.ratingStore = { st }
        return l
    }

    /// The flow's end, and its 1.5 s.
    private func flowEnded() {
        live.flowEnded()
        clock.tick(LiveChatExtras.flowEndRatingSeconds)
    }

    private func ratingOn() {
        live.setChatbotData(["csatConfig": ["enabled": true, "ratingType": "stars"]])
    }

    func testTheFlowsEndOpensTheRatingWhenTheOwnerHasItOn() {
        ratingOn()
        flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testNoRatingWithPostChatFeedbackOff() {
        live.setChatbotData(["csatConfig": ["enabled": false]])
        flowEnded()
        XCTAssertFalse(live.csatOpen)
        live.setChatbotData([:])
        flowEnded()
        XCTAssertFalse(live.csatOpen)
    }

    func testOncePerConversation() {
        ratingOn()
        flowEnded()
        live.dismissCsat()
        flowEnded()
        XCTAssertFalse(live.csatOpen, "put away, it isn't asked again for the same conversation")
        // A new conversation asks again.
        session = "s2"
        flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testAnAgentsEndAlreadyAskedSoTheFlowsEndAfterItDoesNot() {
        ratingOn()
        live.chatEnded()
        XCTAssertTrue(live.csatOpen)
        live.dismissCsat()
        // The handover step's post-chat questions run, then the flow ends.
        flowEnded()
        XCTAssertFalse(live.csatOpen)
    }

    func testNeverForABlockedVisitorOrOverASentRating() {
        ratingOn()
        live.block("This conversation has been closed.")
        flowEnded()
        XCTAssertFalse(live.csatOpen)

        live.reset()
        ratingOn()
        live.chatEnded()
        live.submitRating(5, feedback: nil)
        live.dismissCsat()
        session = "s3"
        flowEnded()
        XCTAssertFalse(live.csatOpen, "sent already")
    }

    func testANewChatAsksAgain() {
        ratingOn()
        flowEnded()
        live.dismissCsat()
        live.reset()
        // "Start a new chat": a new conversation.
        session = "s2"
        ratingOn()
        flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testThePostChatRedirectWaitsForTheRatingOpenedAtTheFlowsEnd() {
        ratingOn()
        var went: [String] = []
        let redirect = PostChatRedirectController(hooks: .init(
            redirectUrl: { "https://www.example.com/thanks" },
            sessionId: { [unowned self] in self.session },
            chatVisible: { true },
            blocked: { false },
            live: { false },
            ratingPending: { [unowned self] in self.live.ratingPending },
            open: { href, done in went.append(href); done(true) },
            disabled: { false },
            onPostChatRedirect: { nil },
            store: { nil },
            appInForeground: { true }
        ), schedule: clock.schedule)

        // As ConferBot does at the flow's end: the rating, then the redirect.
        live.flowEnded()
        redirect.conversationEnded()
        XCTAssertTrue(live.ratingPending, "due before it shows")
        clock.tick(PostChatRedirect.settleSeconds + 1)
        XCTAssertTrue(live.csatOpen)
        XCTAssertNil(redirect.line, "no countdown while the rating is due or up")

        live.dismissCsat()
        redirect.update()
        clock.tick(PostChatRedirect.settleSeconds)
        XCTAssertNotNil(redirect.line)
    }

    func testTheRatingShows1_5sAfterTheFlowsEnd() {
        ratingOn()
        live.flowEnded()
        XCTAssertFalse(live.csatOpen)
        XCTAssertTrue(live.csatDue)
        XCTAssertTrue(live.ratingPending)
        clock.tick(1.4)
        XCTAssertFalse(live.csatOpen)
        clock.tick(0.1)
        XCTAssertTrue(live.csatOpen)
        XCTAssertFalse(live.csatDue)
    }

    func testOfferedIsSavedPerConversation_soARestartDoesNotAskAgain() {
        ratingOn()
        flowEnded()
        XCTAssertEqual(store.values["conferbot_rating_offered_s1"], "1")
        // The app restarts on the same conversation.
        live = makeLive()
        ratingOn()
        flowEnded()
        XCTAssertFalse(live.csatOpen)
        XCTAssertFalse(live.ratingPending)
        // Another conversation is asked.
        session = "s2"
        flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testAnAgentsEndAndASentRatingAreRememberedToo() {
        ratingOn()
        live.chatEnded()
        XCTAssertEqual(store.values["conferbot_rating_offered_s1"], "1")
        session = "s2"
        live.reset()
        ratingOn()
        live.submitRating(4, feedback: nil)
        XCTAssertEqual(store.values["conferbot_rating_offered_s2"], "1")
    }

    func testABlockCancelsAPendingRating() {
        ratingOn()
        live.flowEnded()
        live.block("This conversation has been closed.")
        XCTAssertFalse(live.csatDue)
        clock.tick(2)
        XCTAssertFalse(live.csatOpen)
    }

    func testANewConversationCancelsAPendingRating() {
        ratingOn()
        live.flowEnded()
        live.reset()
        XCTAssertFalse(live.csatDue)
        clock.tick(2)
        XCTAssertFalse(live.csatOpen)
        // Moved on without a reset: the old conversation's rating doesn't show over the new one.
        ratingOn()
        session = "s5"
        live.flowEnded()
        session = "s6"
        clock.tick(2)
        XCTAssertFalse(live.csatOpen)
        XCTAssertFalse(live.csatDue)
    }
}
