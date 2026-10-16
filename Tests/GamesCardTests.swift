//
//  GamesCardTests.swift
//  The waiting games' card (Core/LiveChat/GamesCard; web games/ui.ts), on a
//  fake clock: the menu, each game played through, the footer, and folding
//  away when a teammate joins. The same cases as the React Native SDK's
//  gamesCard.test.ts (web tests/audit-games-card.test.js).
//

import XCTest
@testable import Conferbot

final class GamesCardTests: XCTestCase {

    private var dismissed = 0

    // rng 0.9: no slip in tic-tac-toe, the bot plays its best move.
    private func make(_ c: [String: Any] = [:], rng: @escaping GamesRng = { 0.9 }, reduced: Bool = false, mode: GamesOffer.Mode = .offer,
                      categories: [[String: Any]] = []) -> (k: FakeClock, card: GamesCard) {
        let k = FakeClock()
        var o = GamesCard.Options(customizations: c)
        o.rng = rng
        o.reducedMotion = reduced
        o.mode = mode
        o.categories = categories
        o.schedule = k.schedule
        o.now = { k.now * 1000 }
        o.onDismiss = { [weak self] in self?.dismissed += 1 }
        return (k, GamesCard(o)!)
    }

    private func keys(_ card: GamesCard) -> [FootButton.Key] { card.state.foot.map(\.key) }

    // MARK: - The menu

    func testAnOfferOpensOnTheOwnersLineWithAChipPerGameAndNotNow() {
        let s = make().card.state
        XCTAssertEqual(s.view, .menu)
        XCTAssertEqual(s.title, WaitingGames.defaultOfferText)
        XCTAssertEqual(s.chips.map(\.id), [.rps, .ttt, .quiz, .memory, .reaction, .emoji, .scramble])
        XCTAssertEqual(s.foot.map(\.key), [.notNow])
        XCTAssertFalse(make().card.playing)
    }

    func testTheOwnersOwnLineAndGamesAskedForItSaysPickAGame() {
        let s = make(["waitingGames": ["offerText": "Bored? Play!", "games": ["ttt"]]]).card.state
        XCTAssertEqual(s.title, "Bored? Play!")
        XCTAssertEqual(s.chips.map(\.id), [.ttt])
        XCTAssertEqual(make(mode: .menu).card.state.title, "Pick a game")
    }

    func testNoGameLeftForTheLanguageNoCard() {
        var o = GamesCard.Options(customizations: ["waitingGames": ["games": ["emoji"]]])
        o.lang = "de"
        XCTAssertNil(GamesCard(o))
    }

    func testNotNowAndTheXCloseItOnce() {
        let card = make().card
        card.press(.notNow)
        XCTAssertEqual(card.state.view, .gone)
        XCTAssertFalse(card.up)
        card.dismiss()
        XCTAssertEqual(dismissed, 1)
    }

    func testAGameTheOwnerTurnedOffDoesNotOpen() {
        let card = make(["waitingGames": ["games": ["ttt"]]]).card
        card.open(.rps)
        XCTAssertEqual(card.state.view, .menu)
    }

    // MARK: - Rock paper scissors

    func testTheHandsShakeFor900msThenThePointFirstToTwoWins() {
        // rng 0.9: the bot always plays scissors.
        let (k, card) = make()
        card.open(.rps)
        XCTAssertEqual(card.state.title, "Rock paper scissors")
        XCTAssertEqual(card.state.titleEmoji, "✊")
        XCTAssertEqual(card.state.meta, "You 0 · 0 Bot")
        XCTAssertEqual(card.state.status, "First to two wins. Pick your hand!")
        card.input(.rps(.rock))
        XCTAssertEqual(card.state.board?.rps?.shaking, true)
        XCTAssertEqual(card.state.status, "Rock... paper... scissors...")
        // Busy: a second pick is ignored.
        card.input(.rps(.paper))
        k.tick(0.9)
        let b = card.state.board?.rps
        XCTAssertEqual(b?.shaking, false)
        XCTAssertEqual(b?.you, "✊")
        XCTAssertEqual(b?.bot, "✌️")
        XCTAssertEqual(b?.outcome, .win)
        XCTAssertEqual(b?.busy, false)
        XCTAssertEqual(card.state.status, "Rock beats scissors - point to you!")
        XCTAssertEqual(card.state.meta, "You 1 · 0 Bot")
        card.input(.rps(.rock))
        k.tick(0.9)
        XCTAssertEqual(card.state.result, "win")
        XCTAssertEqual(card.state.status, "Rock beats scissors - point to you! You win 2-0! 🎉")
        XCTAssertEqual(card.state.confetti, 1)
        XCTAssertEqual(keys(card), [.again, .another])
        XCTAssertFalse(card.playing)
    }

    func testWithReducedMotionTheHandsShowAtOnce() {
        let card = make(reduced: true).card
        card.open(.rps)
        card.input(.rps(.paper))
        XCTAssertEqual(card.state.status, "Scissors beats paper - point to the bot.")
        XCTAssertEqual(card.state.board?.rps?.shaking, false)
    }

    // MARK: - Tic-tac-toe

    func testTheVisitorGoesFirstTheBotThinksFor550msThenItIsTheirMove() {
        let (k, card) = make()
        card.open(.ttt)
        XCTAssertEqual(card.state.status, "You go first - tap a square")
        XCTAssertEqual(card.state.meta, "You ✕ · Bot ◯")
        card.input(.ttt(0))
        XCTAssertEqual(card.state.board?.ttt?.thinking, true)
        card.input(.ttt(1))
        XCTAssertEqual(card.state.board?.ttt?.cells.compactMap { $0 }.count, 1)
        k.tick(0.55)
        XCTAssertEqual(card.state.board?.ttt?.cells.filter { $0 == .o }.count, 1)
        XCTAssertEqual(card.state.status, "Your move")
    }

    func testTheBotOpensEverySecondGame() {
        let (k, card) = make()
        card.open(.ttt)
        card.press(.another)
        card.open(.ttt)
        XCTAssertEqual(card.state.status, "The bot is thinking...")
        k.tick(0.55)
        XCTAssertEqual(card.state.board?.ttt?.cells.filter { $0 == .o }.count, 1)
    }

    func testATeammateJoinsWhileTheBotIsThinkingFinishMyGameMakesItsMove() {
        let (k, card) = make()
        card.open(.ttt)
        card.input(.ttt(0))
        XCTAssertEqual(k.pending, 1)
        card.wrapUp("Sam")
        XCTAssertEqual(card.state.view, .paused)
        XCTAssertEqual(card.state.titleEmoji, "👋")
        XCTAssertEqual(card.state.title, "Sam's here!")
        XCTAssertEqual(card.state.status, "Your game is saved - finish it later?")
        XCTAssertEqual(card.state.foot, [FootButton(key: .resume, label: "Finish my game", primary: false)])
        k.tick(5)
        XCTAssertEqual(card.state.board?.ttt?.cells.filter { $0 == .o }.count, 0)
        card.input(.ttt(4))
        XCTAssertEqual(card.state.board?.ttt?.cells.compactMap { $0 }.count, 1)
        card.press(.resume)
        let b = card.state.board!.ttt!
        XCTAssertEqual(b.cells.filter { $0 == .o }.count, 1)
        XCTAssertFalse(b.thinking)
        let free = b.cells.firstIndex { $0 == nil }!
        card.input(.ttt(free))
        XCTAssertEqual(card.state.board?.ttt?.cells.filter { $0 == .x }.count, 2)
    }

    func testAWinMarksTheLineAndFinishes() {
        // rng 0 every time: a slip each move, the bot's casual move is the first free square.
        let (k, card) = make(rng: { 0 })
        card.open(.ttt)
        for i in [4, 2, 8] {
            card.input(.ttt(i))
            k.tick(0.55)
        }
        for _ in 0..<9 where card.state.result == nil {
            guard let free = card.state.board?.ttt?.cells.firstIndex(where: { $0 == nil }) else { break }
            card.input(.ttt(free))
            k.tick(0.55)
        }
        XCTAssertNotNil(card.state.result)
        XCTAssertEqual(card.state.board?.ttt?.over, true)
        XCTAssertTrue(["Three in a row - you beat the bot! 🎉", "The bot got this one. Rematch? 🤖", "A draw - great minds think alike 🤝"].contains(card.state.status))
    }

    // MARK: - Memory

    private func byFace(_ b: MemoryBoard) -> [[Int]] {
        var order: [String] = []
        var m: [String: [Int]] = [:]
        for (i, c) in b.cards.enumerated() {
            if m[c.face] == nil { order.append(c.face) }
            m[c.face, default: []].append(i)
        }
        return order.map { m[$0]! }
    }

    func testAPairPopsTheTwoCardsJustMatchedAMissTurnsBackAfter850ms() {
        let (k, card) = make()
        card.open(.memory)
        XCTAssertEqual(card.state.meta, "Moves 0 · Pairs 0/6")
        let pairs = byFace(card.state.board!.memory!)
        card.input(.memory(pairs[0][0]))
        card.input(.memory(pairs[0][1]))
        XCTAssertEqual(card.state.status, "A pair! ✨")
        XCTAssertEqual(card.state.board?.memory?.pop.sorted(), pairs[0].sorted())
        card.input(.memory(pairs[1][0]))
        card.input(.memory(pairs[2][0]))
        XCTAssertEqual(card.state.status, "Not a pair")
        XCTAssertEqual(card.state.board?.memory?.cards.filter(\.up).count, 4)
        // Waiting for them to turn back: taps are ignored.
        card.input(.memory(pairs[3][0]))
        k.tick(0.85)
        XCTAssertEqual(card.state.board?.memory?.cards.filter(\.up).count, 2)
        XCTAssertEqual(card.state.meta, "Moves 2 · Pairs 1/6")
    }

    func testAllSixPairsTheMovesAndTheStars() {
        let card = make().card
        card.open(.memory)
        for p in byFace(card.state.board!.memory!) {
            card.input(.memory(p[0]))
            card.input(.memory(p[1]))
        }
        XCTAssertEqual(card.state.result, "win")
        XCTAssertEqual(card.state.status, "All pairs in 6 moves! ⭐⭐⭐")
    }

    // MARK: - Quiz and emoji riddles

    private func answerAll(_ card: GamesCard, right: Bool) {
        for r in 0..<3 {
            let b = card.state.board!.choice!
            card.input(.choice(right ? b.answer : (b.answer + 1) % b.options.count))
            if r < 2 { card.press(.action) }
        }
    }

    func testThreeTriviaRoundsFeedbackNextLastOneTheScore() {
        let card = make().card
        card.open(.quiz)
        XCTAssertEqual(card.state.status, "Three quick questions")
        XCTAssertEqual(card.state.meta, "1 of 3 · 0 right")
        var b = card.state.board!.choice!
        XCTAssertEqual(b.options.count, 3)
        XCTAssertNil(b.tag)
        card.input(.choice(b.answer))
        XCTAssertEqual(card.state.meta, "1 of 3 · 1 right")
        XCTAssertEqual(card.state.cheer, 1)
        XCTAssertEqual(card.state.foot.map(\.label), ["Another game", "Next →"])
        // A second pick on the same round is ignored.
        card.input(.choice((b.answer + 1) % 3))
        XCTAssertEqual(card.state.meta, "1 of 3 · 1 right")
        card.press(.action)
        XCTAssertEqual(card.state.meta, "2 of 3 · 1 right")
        b = card.state.board!.choice!
        card.input(.choice((b.answer + 1) % 3))
        XCTAssertEqual(card.state.status, "Not quite - it's \(b.options[b.answer])")
        XCTAssertEqual(card.state.foot.map(\.label), ["Another game", "Last one →"])
        card.press(.action)
        b = card.state.board!.choice!
        card.input(.choice(b.answer))
        XCTAssertEqual(card.state.result, "done")
        XCTAssertTrue(card.state.status.hasSuffix(". 2 out of 3. So close! 🌟"), card.state.status)
    }

    func testWithTheHelpCentreOnQuestionsFromItsArticlesComeFirstTagged() {
        let categories: [[String: Any]] = [
            ["name": "Billing", "articles": [
                ["_id": "1", "title": "Downloading invoices", "description": "Find every invoice in one place."],
                ["_id": "2", "title": "Changing your plan", "description": "Upgrade or cancel."],
            ]],
            ["name": "Account", "articles": [["_id": "3", "title": "Resetting your password", "description": "Forgot it? Reset it."]]],
        ]
        let card = make(["enableKnowledgeBase": true], categories: categories).card
        card.open(.quiz)
        XCTAssertEqual(card.state.status, "Three questions - some about our help centre")
        XCTAssertEqual(card.state.board?.choice?.tag, "From our help centre")
        let off = make([:], categories: categories).card
        off.open(.quiz)
        XCTAssertNil(off.state.board?.choice?.tag)
    }

    func testEmojiRiddlesThePictureFourOptionsAllRightIsAWin() {
        let card = make().card
        card.open(.emoji)
        let b = card.state.board!.choice!
        XCTAssertFalse((b.big ?? "").isEmpty)
        XCTAssertEqual(b.q, "What's the phrase?")
        XCTAssertEqual(b.options.count, 4)
        answerAll(card, right: true)
        XCTAssertEqual(card.state.result, "win")
        XCTAssertTrue(card.state.status.hasSuffix("3 of 3 riddles solved. Perfect score! 🏆"), card.state.status)
    }

    // MARK: - Reflex test

    func testWaitForGreenTapTooSoonALuckyGuessThreeRoundsAndTheAverage() {
        // rng 0.9: green after 1200 + 1980 = 3180ms.
        let (k, card) = make()
        card.open(.reaction)
        func pad() -> ReactionBoard { card.state.board!.reaction! }
        XCTAssertEqual(pad().state, .idle)
        XCTAssertEqual(pad().line, "Tap to start")
        card.input(.reaction)
        XCTAssertEqual(pad().state, .wait)
        XCTAssertEqual(pad().big, "👀")
        card.input(.reaction)
        XCTAssertEqual(pad().state, .between)
        XCTAssertEqual(pad().line, "Too soon! Tap to try again")
        XCTAssertEqual(card.state.status, "Too soon - wait for green")
        card.input(.reaction)
        k.tick(3.18)
        XCTAssertEqual(pad().state, .go)
        XCTAssertEqual(pad().line, "Tap now!")
        k.tick(0.05)
        card.input(.reaction)
        XCTAssertEqual(pad().line, "A lucky guess! Tap to try again")
        for ms in [200.0, 300, 400] {
            card.input(.reaction)
            k.tick(3.18)
            k.tick(ms / 1000)
            card.input(.reaction)
        }
        XCTAssertEqual(card.state.result, "win")
        XCTAssertEqual(card.state.status, "Sharp reflexes 🎯 - 300 ms on average.")
        XCTAssertEqual(card.state.meta, "200 · 300 · 400 ms")
        XCTAssertEqual(pad().state, .done)
        XCTAssertEqual(pad().line, "300 ms average")
    }

    func testATeammateJoiningMidRoundTheRoundIsResetTapToCarryOn() {
        let (k, card) = make()
        card.open(.reaction)
        card.input(.reaction)
        card.wrapUp("")
        XCTAssertEqual(card.state.title, "Someone's here!")
        k.tick(10)
        card.press(.resume)
        XCTAssertEqual(card.state.board?.reaction, ReactionBoard(state: .between, big: "⏸️", line: "Tap to carry on"))
    }

    // MARK: - Word scramble

    private func solve(_ b: ScrambleBoard) -> String {
        let w = GamesLogic.words.first { $0.hint == b.hint }!.w
        XCTAssertEqual(b.letters.sorted(), w.map(String.init).sorted())
        return w
    }

    func testTapLettersInOrderAWrongWordShakesTapASlotToTakeItBackSolvedMovesOn() {
        let (k, card) = make()
        card.open(.scramble)
        let b0 = card.state.board!.scramble!
        XCTAssertEqual(card.state.meta, "Word 1 of 3 · 0 solved")
        XCTAssertEqual(b0.skipLabel, "Skip")
        // Wrong: the tiles as they lie (never the word itself).
        b0.letters.indices.forEach { card.input(.tile($0)) }
        var b = card.state.board!.scramble!
        XCTAssertEqual(b.nope, 1)
        XCTAssertEqual(card.state.status, "Not quite - tap letters to take them back")
        card.input(.slot(0))
        XCTAssertEqual(card.state.board?.scramble?.placed, [])
        card.input(.skip)
        b = card.state.board!.scramble!
        XCTAssertTrue(b.revealed)
        let revealed = b.placed.map { b.letters[$0] }.joined()
        XCTAssertEqual(card.state.status, "It was \(revealed).")
        k.tick(1.5)
        b = card.state.board!.scramble!
        XCTAssertEqual(card.state.meta, "Word 2 of 3 · 0 solved")
        XCTAssertEqual(b.placed, [])
    }

    func testThreeWordsSolvedWordWizard() {
        let (k, card) = make()
        card.open(.scramble)
        var words: [String] = []
        for r in 0..<3 {
            let target = solve(card.state.board!.scramble!)
            words.append(target)
            for ch in target { card.input(.key(String(ch).lowercased())) }
            if r < 2 {
                XCTAssertEqual(card.state.status, "\(target) - got it! 🎉")
                k.tick(1.1)
            }
        }
        XCTAssertEqual(card.state.result, "win")
        XCTAssertEqual(card.state.status, "\(words[2]) - got it! 🎉 You solved 3 of 3. Word wizard! 🧙")
    }

    // MARK: - The footer and folding away

    func testPlayAgainReplaysTheSameGameAnotherGameGoesBackToTheMenu() {
        let card = make().card
        card.open(.memory)
        card.press(.another)
        XCTAssertEqual(card.state.view, .menu)
        XCTAssertEqual(card.state.title, "Pick a game")
        card.open(.rps)
        card.press(.again)
        XCTAssertEqual(card.state.view, .game)
        XCTAssertEqual(card.state.game, .rps)
        XCTAssertEqual(card.state.meta, "You 0 · 0 Bot")
    }

    func testATeammateJoinsTheMenuLeavesAFinishedGameStaysAsAResultWithNoButtonsAndNoX() {
        let a = make().card
        a.wrapUp("Sam")
        XCTAssertEqual(a.state.view, .gone)

        let b = make(reduced: true).card
        b.open(.rps)
        b.input(.rps(.rock))
        b.input(.rps(.rock))
        XCTAssertEqual(b.state.result, "win")
        b.wrapUp("Sam")
        XCTAssertEqual(b.state.view, .game)
        XCTAssertTrue(b.state.settled)
        XCTAssertFalse(b.state.closable)
        XCTAssertEqual(b.state.foot, [])
    }

    func testTheMenuOnAPausedCardIsBackWithItsX() {
        let card = make().card
        card.open(.rps)
        card.wrapUp("Sam")
        card.menu()
        XCTAssertEqual(card.state.view, .menu)
        XCTAssertTrue(card.state.closable)
        XCTAssertEqual(card.state.chips.count, 7)
    }

    func testRemovedItsTimersStopAndTapsDoNothing() {
        let (k, card) = make()
        card.open(.ttt)
        card.input(.ttt(0))
        card.remove()
        XCTAssertEqual(k.pending, 0)
        card.input(.ttt(1))
        XCTAssertEqual(card.state.view, .gone)
    }

    func testEveryChangeReachesTheSubscribers() {
        let card = make().card
        var seen: [GamesCardState.View] = []
        let off = card.subscribe { seen.append($0.view) }
        card.open(.quiz)
        card.press(.another)
        off()
        card.open(.rps)
        XCTAssertEqual(seen, [.game, .menu])
    }

    func testWithReducedMotionNoCheerAndNoConfetti() {
        let card = make(reduced: true).card
        card.open(.memory)
        for p in byFace(card.state.board!.memory!) {
            card.input(.memory(p[0]))
            card.input(.memory(p[1]))
        }
        XCTAssertEqual(card.state.result, "win")
        XCTAssertEqual(card.state.confetti, 0)
        XCTAssertEqual(card.state.cheer, 0)
    }
}
