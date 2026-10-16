//
//  ComposerStateTests.swift
//  The message box of the stock chats (ChatView, ChatViewWithKBSheet, the
//  UIKit-drawn chat): off and saying why for a closed chat (#40, #80), off
//  with "Replies are off" while locked or turned off.
//

import XCTest
@testable import Conferbot

final class ComposerStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = I18n.setWidgetLanguage("en")
    }

    func testOpenChatTakesText() {
        let s = ComposerState.of(lockedBy: nil, visitorInputEnabled: true, closed: nil)
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.placeholder, I18n.t("chat.composer.placeholder"))
    }

    func testLockedOrRepliesOff() {
        for s in [ComposerState.of(lockedBy: "Ann", visitorInputEnabled: true, closed: nil),
                  ComposerState.of(lockedBy: nil, visitorInputEnabled: false, closed: nil)] {
            XCTAssertFalse(s.enabled)
            XCTAssertEqual(s.placeholder, I18n.t("sdk.chat.repliesOff"))
        }
    }

    func testAClosedChatSaysWhy() {
        let blocked = LiveEvents.closedState([], blocked: "This conversation has been closed.", stepWaiting: false, live: false)
        let s = ComposerState.of(lockedBy: nil, visitorInputEnabled: true, closed: blocked)
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.placeholder, "This conversation has been closed.")

        let ended = LiveEvents.ClosedState(kind: .ended, text: "Chat ended", newChat: true, inputOff: true)
        XCTAssertEqual(ComposerState.of(lockedBy: "Ann", visitorInputEnabled: false, closed: ended),
                       ComposerState(enabled: false, placeholder: "Chat ended"))
    }
}
