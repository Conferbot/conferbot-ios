//
//  ChatHeaderTests.swift
//  The chat header for a chat that never got the bot's settings (#79): a
//  visitor refused at the handshake has a closed chat and no connection,
//  so no "Connecting..." line, and the bot's name from the last settings
//  this device saw for the bot.
//

import XCTest
@testable import Conferbot

final class ChatHeaderTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "ChatHeaderTests"

    override func setUp() {
        super.setUp()
        _ = I18n.setWidgetLanguage("en")
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAClosedChatHasNoConnectionLine() {
        XCTAssertEqual(ChatHeader.connection(connected: false, closed: true), .none)
        XCTAssertEqual(ChatHeader.connection(connected: false, closed: false), .connecting)
        XCTAssertEqual(ChatHeader.connection(connected: true, closed: false), .connected)
        // Connected and ended: the tagline or "Online" as before.
        XCTAssertEqual(ChatHeader.connection(connected: true, closed: true), .connected)
    }

    func testTheTitleIsTheSettingsThenTheRememberedNameThenTheHostsThenSupportChat() {
        XCTAssertEqual(ChatHeader.title(server: "Acme Bot", remembered: "Old", host: "Help"), "Acme Bot")
        XCTAssertEqual(ChatHeader.title(server: nil, remembered: "Acme Bot", host: "Help"), "Acme Bot")
        XCTAssertEqual(ChatHeader.title(server: nil, remembered: "  ", host: "Help"), "Help")
        XCTAssertEqual(ChatHeader.title(server: nil, remembered: nil, host: nil), "Support Chat")
    }

    func testTheBotsNameIsRememberedPerBot() {
        ChatHeader.remember("Acme Bot", botId: "b1", defaults: defaults)
        ChatHeader.remember("Other", botId: "b2", defaults: defaults)
        XCTAssertEqual(ChatHeader.remembered(botId: "b1", defaults: defaults), "Acme Bot")
        XCTAssertEqual(ChatHeader.remembered(botId: "b2", defaults: defaults), "Other")
        XCTAssertNil(ChatHeader.remembered(botId: "b3", defaults: defaults))
        // No bot, or an empty name: nothing kept.
        ChatHeader.remember("X", botId: nil, defaults: defaults)
        ChatHeader.remember("  ", botId: "b1", defaults: defaults)
        XCTAssertEqual(ChatHeader.remembered(botId: "b1", defaults: defaults), "Acme Bot")
        XCTAssertNil(ChatHeader.remembered(botId: nil, defaults: defaults))
    }
}
