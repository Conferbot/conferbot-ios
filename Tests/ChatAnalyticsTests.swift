//
//  ChatAnalyticsTests.swift
//  ConferbotTests
//
//  Starting and ending a session's analytics sends its events and returns:
//  the events are sent while the analytics lock is held, which deadlocked
//  with a plain NSLock and left startSession() hanging (#61).
//

import XCTest
@testable import Conferbot

final class ChatAnalyticsTests: XCTestCase {

    private var events: [String] = []
    private let eventsLock = NSLock()

    override func setUp() {
        super.setUp()
        events = []
        ChatAnalytics.shared.setEmitHandler { [weak self] name, _ in
            guard let self = self else { return }
            self.eventsLock.lock()
            self.events.append(name)
            self.eventsLock.unlock()
        }
    }

    override func tearDown() {
        ChatAnalytics.shared.setEmitHandler { _, _ in }
        super.tearDown()
    }

    /// Runs `work` off the main thread and fails instead of hanging when it never returns.
    private func returns(_ name: String, _ work: @escaping () -> Void) {
        let done = expectation(description: name)
        DispatchQueue.global().async {
            work()
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testInitializeChatAnalytics_returnsAndSendsChatStart() {
        returns("initializeChatAnalytics") {
            ChatAnalytics.shared.initializeChatAnalytics(sessionId: "s-1", botIdentifier: "bot-1", visitorIdentifier: "v-1")
        }
        eventsLock.lock(); defer { eventsLock.unlock() }
        XCTAssertTrue(events.contains("track-chat-start"))
    }

    func testFinalizeChatAnalytics_returnsAfterAStart() {
        returns("initializeChatAnalytics") {
            ChatAnalytics.shared.initializeChatAnalytics(sessionId: "s-2", botIdentifier: "bot-1", visitorIdentifier: "v-1")
        }
        returns("finalizeChatAnalytics") {
            ChatAnalytics.shared.finalizeChatAnalytics()
        }
    }
}
