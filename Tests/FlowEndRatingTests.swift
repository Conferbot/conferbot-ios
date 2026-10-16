//
//  FlowEndRatingTests.swift
//  The post-chat rating at the flow's end (#95), as the web asks after
//  chat-flow-completed: only with the owner's post-chat feedback on, once
//  per conversation, never for a blocked visitor or over a rating already
//  up or sent, and the post-chat redirect waits for it.
//

import XCTest
@testable import Conferbot

final class FlowEndRatingTests: XCTestCase {

    private var session = "s1"
    private var live: LiveChatExtras!

    override func setUp() {
        super.setUp()
        session = "s1"
        live = LiveChatExtras(socket: { nil }, sessionId: { [unowned self] in self.session },
                              chatState: { ChatState.shared }, addMessage: { _ in }, sendRecord: {})
    }

    private func ratingOn() {
        live.setChatbotData(["csatConfig": ["enabled": true, "ratingType": "stars"]])
    }

    func testTheFlowsEndOpensTheRatingWhenTheOwnerHasItOn() {
        ratingOn()
        live.flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testNoRatingWithPostChatFeedbackOff() {
        live.setChatbotData(["csatConfig": ["enabled": false]])
        live.flowEnded()
        XCTAssertFalse(live.csatOpen)
        live.setChatbotData([:])
        live.flowEnded()
        XCTAssertFalse(live.csatOpen)
    }

    func testOncePerConversation() {
        ratingOn()
        live.flowEnded()
        live.dismissCsat()
        live.flowEnded()
        XCTAssertFalse(live.csatOpen, "put away, it isn't asked again for the same conversation")
        // A new conversation asks again.
        session = "s2"
        live.flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testAnAgentsEndAlreadyAskedSoTheFlowsEndAfterItDoesNot() {
        ratingOn()
        live.chatEnded()
        XCTAssertTrue(live.csatOpen)
        live.dismissCsat()
        // The handover step's post-chat questions run, then the flow ends.
        live.flowEnded()
        XCTAssertFalse(live.csatOpen)
    }

    func testNeverForABlockedVisitorOrOverASentRating() {
        ratingOn()
        live.block("This conversation has been closed.")
        live.flowEnded()
        XCTAssertFalse(live.csatOpen)

        live.reset()
        ratingOn()
        live.chatEnded()
        live.submitRating(5, feedback: nil)
        live.dismissCsat()
        session = "s3"
        live.flowEnded()
        XCTAssertFalse(live.csatOpen, "sent already")
    }

    func testANewChatAsksAgain() {
        ratingOn()
        live.flowEnded()
        live.dismissCsat()
        live.reset()
        ratingOn()
        live.flowEnded()
        XCTAssertTrue(live.csatOpen)
    }

    func testThePostChatRedirectWaitsForTheRatingOpenedAtTheFlowsEnd() {
        ratingOn()
        let clock = FakeClock()
        var went: [String] = []
        let redirect = PostChatRedirectController(hooks: .init(
            redirectUrl: { "https://www.example.com/thanks" },
            sessionId: { [unowned self] in self.session },
            chatVisible: { true },
            blocked: { false },
            live: { false },
            ratingPending: { [unowned self] in self.live.csatConfig != nil && self.live.csatOpen && !self.live.csatSent },
            open: { href, done in went.append(href); done(true) },
            disabled: { false },
            onPostChatRedirect: { nil },
            store: { nil },
            appInForeground: { true }
        ), schedule: clock.schedule)

        // As ConferBot does at the flow's end: the rating, then the redirect.
        live.flowEnded()
        redirect.conversationEnded()
        clock.tick(PostChatRedirect.settleSeconds + 1)
        XCTAssertNil(redirect.line, "no countdown while the rating is up")

        live.dismissCsat()
        redirect.update()
        clock.tick(PostChatRedirect.settleSeconds)
        XCTAssertNotNil(redirect.line)
    }
}
