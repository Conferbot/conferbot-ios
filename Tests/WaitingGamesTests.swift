//
//  WaitingGamesTests.swift
//  The waiting games' settings and the offer's timing
//  (Core/LiveChat/WaitingGames; web games/settings.ts and games/wire.ts),
//  the same cases as the React Native SDK's waitingGames.test.ts, on a fake
//  clock.
//

import XCTest
@testable import Conferbot

private final class FakeOfferCard: OfferCard {
    var on = true
    var game = false
    var menus = 0
    var removed = 0
    var wrapped: [String] = []
    var up: Bool { on }
    var playing: Bool { game }
    func menu() { menus += 1 }
    func remove() {
        on = false
        removed += 1
    }
    func wrapUp(_ name: String) { wrapped.append(name) }
}

final class WaitingGamesTests: XCTestCase {

    private let delay = WaitingGames.offerDelayMs / 1000
    private let retry = WaitingGames.offerRetryMs / 1000

    private func setup(enabled: Bool = true, failFirst: Int = 0) -> (k: FakeClock, offer: GamesOffer, mounts: () -> [String], last: () -> FakeOfferCard) {
        let k = FakeClock()
        var mounts: [String] = []
        var last = FakeOfferCard()
        var fails = failFirst
        let offer = GamesOffer(enabled: { enabled }, mount: { mode in
            mounts.append(mode.rawValue)
            if fails > 0 {
                fails -= 1
                return nil
            }
            last = FakeOfferCard()
            return last
        }, schedule: k.schedule)
        return (k, offer, { mounts }, { last })
    }

    // MARK: - Settings (web settings.ts)

    func testUnsetIsOnWithEveryGameAndTheDefaultLine() {
        XCTAssertEqual(WaitingGames.settings([:]), .init(enabled: true, games: WaitingGames.gameIds, offerText: WaitingGames.defaultOfferText))
        XCTAssertEqual(WaitingGames.gameIds.count, 7)
    }

    func testOffASubsetUnknownGamesDroppedNoGamesIsOffTheLineCleaned() {
        XCTAssertFalse(WaitingGames.settings(["waitingGames": ["enabled": false]]).enabled)
        XCTAssertEqual(WaitingGames.settings(["waitingGames": ["games": ["ttt", "nope", "ttt", "rps"]]]).games, [.ttt, .rps])
        XCTAssertFalse(WaitingGames.settings(["waitingGames": ["games": [] as [Any]]]).enabled)
        XCTAssertEqual(WaitingGames.settings(["waitingGames": ["offerText": "  Bored?   Play!  "]]).offerText, "Bored? Play!")
        XCTAssertEqual(WaitingGames.settings(["waitingGames": ["offerText": String(repeating: "x", count: 300)]]).offerText.count, WaitingGames.offerTextMax)
    }

    func testTheEmojiRiddlesOnlyInEnglish() {
        XCTAssertTrue(WaitingGames.forLanguage(WaitingGames.games, "en").map(\.id).contains(.emoji))
        XCTAssertFalse(WaitingGames.forLanguage(WaitingGames.games, "de").map(\.id).contains(.emoji))
    }

    func testTypingPlayOrGamesOpensTheMenuARealMessageDoesNot() {
        for t in ["play", "Play!", "games", "game", "let's play", "lets play", "play a game", "I want to play"] {
            XCTAssertTrue(WaitingGames.isPlay(t), t)
        }
        for t in ["how do I play the video", "my game crashed", "playlist", ""] {
            XCTAssertFalse(WaitingGames.isPlay(t), t)
        }
    }

    func testTheAccentTheHeaderColourUnlessTooPaleThenTheBotBubbleThenConferbotBlue() {
        XCTAssertEqual(WaitingGames.pickAccent(["headerBgColor": "#123456"]), "#123456")
        XCTAssertEqual(WaitingGames.pickAccent(["headerBgColor": "#ffe4ec", "botMsgColor": "#e65100"]), "#e65100")
        XCTAssertEqual(WaitingGames.pickAccent(["headerBgColor": "#ffffff", "botMsgColor": "red"]), "#0808EE")
        XCTAssertEqual(WaitingGames.pickAccent(nil), "#0808EE")
    }

    // MARK: - The offer (web wire.ts)

    func testOffersOnce2500msAfterTheWaitingSignal() {
        let s = setup()
        s.offer.waiting()
        s.k.tick(delay - 0.5)
        XCTAssertEqual(s.mounts(), [])
        s.k.tick(0.5)
        XCTAssertEqual(s.mounts(), ["offer"])
        // A second signal in the same wait changes nothing.
        s.offer.waiting()
        s.k.tick(10)
        XCTAssertEqual(s.mounts(), ["offer"])
    }

    func testACardThatCouldNotBeDrawnIsTriedThreeMoreTimes1500msApart() {
        let s = setup(failFirst: 10)
        s.offer.waiting()
        s.k.tick(delay)
        s.k.tick(retry * 3)
        XCTAssertEqual(s.mounts().count, 4)
        s.k.tick(60)
        XCTAssertEqual(s.mounts().count, 4)
    }

    func testOffNoOfferAndPlayIsSentAsWords() {
        let s = setup(enabled: false)
        s.offer.waiting()
        s.k.tick(20)
        XCTAssertEqual(s.mounts(), [])
        XCTAssertFalse(s.offer.play("play"))
    }

    func testAPersonJoiningBeforeTheOfferNoneComes() {
        let s = setup()
        s.offer.waiting()
        s.k.tick(1)
        s.offer.joined("Sam")
        s.k.tick(10)
        XCTAssertEqual(s.mounts(), [])
        XCTAssertEqual(s.k.pending, 0)
    }

    func testAPersonJoiningTheCardWrapsUpWithTheirName() {
        let s = setup()
        s.offer.waiting()
        s.k.tick(delay)
        s.offer.joined("Sam")
        XCTAssertEqual(s.last().wrapped, ["Sam"])
        s.offer.joined(nil)
        XCTAssertEqual(s.last().wrapped, ["Sam", ""])
    }

    func testTheWaitOverAnUnusedCardLeavesAGameBeingPlayedStays() {
        let a = setup()
        a.offer.waiting()
        a.k.tick(delay)
        a.offer.waitOver()
        XCTAssertEqual(a.last().removed, 1)

        let b = setup()
        b.offer.waiting()
        b.k.tick(delay)
        b.last().game = true
        b.offer.waitOver()
        XCTAssertEqual(b.last().removed, 0)
    }

    func testTheWaitOverBeforeTheOfferNoneComes() {
        let s = setup()
        s.offer.waiting()
        s.offer.waitOver()
        s.k.tick(10)
        XCTAssertEqual(s.mounts(), [])
    }

    func testNotNowNoMoreOffersThisSessionEvenInALaterWaitTypingPlayStillOpensTheMenu() {
        let s = setup()
        s.offer.waiting()
        s.k.tick(delay)
        s.offer.dismissed()
        s.offer.waitOver()
        s.offer.waiting()
        s.k.tick(10)
        XCTAssertEqual(s.mounts(), ["offer"])
        XCTAssertTrue(s.offer.play("let's play"))
        XCTAssertEqual(s.mounts(), ["offer", "menu"])
        // A new conversation keeps a "Not now" (the web: this page view).
        s.offer.dismissed()
        s.offer.reset()
        s.offer.waiting()
        s.k.tick(10)
        XCTAssertEqual(s.mounts(), ["offer", "menu"])
    }

    func testTypingPlayOnlyWhileWaitingOnACardAlreadyUpItGoesBackToTheMenuMidGameItDoesNot() {
        let s = setup()
        XCTAssertFalse(s.offer.play("play"))
        s.offer.waiting()
        XCTAssertFalse(s.offer.play("my game crashed"))
        s.k.tick(delay)
        XCTAssertTrue(s.offer.play("games"))
        XCTAssertEqual(s.last().menus, 1)
        s.last().game = true
        XCTAssertTrue(s.offer.play("play"))
        XCTAssertEqual(s.last().menus, 1)
        XCTAssertEqual(s.mounts(), ["offer"])
    }
}
