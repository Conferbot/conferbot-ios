//
//  GamesLogicTests.swift
//  The waiting games' rules (Core/LiveChat/GamesLogic), the same cases as
//  the React Native SDK's gamesLogic.test.ts (the web widget's
//  tests/waitingGames.test.js).
//

import XCTest
@testable import Conferbot

/// A repeatable "random": a fixed sequence.
func seq(_ xs: Double...) -> GamesRng {
    var i = 0
    return {
        defer { i += 1 }
        return xs[i % xs.count]
    }
}

final class GamesLogicTests: XCTestCase {
    typealias L = GamesLogic

    private func B(_ s: String) -> [L.Cell?] { s.map { $0 == "X" ? .x : $0 == "O" ? .o : nil } }

    // MARK: - Rock paper scissors

    func testEveryPairing() {
        XCTAssertEqual(L.rpsOutcome(.rock, .scissors), .win)
        XCTAssertEqual(L.rpsOutcome(.paper, .rock), .win)
        XCTAssertEqual(L.rpsOutcome(.scissors, .paper), .win)
        XCTAssertEqual(L.rpsOutcome(.rock, .paper), .lose)
        XCTAssertEqual(L.rpsOutcome(.paper, .scissors), .lose)
        XCTAssertEqual(L.rpsOutcome(.scissors, .rock), .lose)
        for h in L.hands { XCTAssertEqual(L.rpsOutcome(h, h), .draw) }
    }

    func testBestOfThreeTheFirstToTwo() {
        XCTAssertNil(L.rpsWinner(you: 1, bot: 1))
        XCTAssertEqual(L.rpsWinner(you: 2, bot: 1), "you")
        XCTAssertEqual(L.rpsWinner(you: 0, bot: 2), "bot")
    }

    // MARK: - Tic-tac-toe

    func testRowsColumnsDiagonalsDraws() {
        XCTAssertEqual(L.tttWinner(B("XXX......")), .won(.x, [0, 1, 2]))
        XCTAssertEqual(L.tttWinner(B("O..O..O..")), .won(.o, [0, 3, 6]))
        XCTAssertEqual(L.tttWinner(B("..X.X.X..")), .won(.x, [2, 4, 6]))
        XCTAssertEqual(L.tttWinner(B("XOXXOOOXX")), .draw)
        XCTAssertNil(L.tttWinner(B("XO.......")))
    }

    func testTheBotTakesAWinBeforeItBlocks() {
        XCTAssertEqual(L.tttBotMove(B("OO.XX...."), L.random, slip: 1), 2)
    }

    func testTheBotAlwaysBlocksEvenWhenItSlips() {
        XCTAssertEqual(L.tttBotMove(B("XX..O...."), { 0 }, slip: 1), 2)
        XCTAssertEqual(L.tttBotMove(B("X...X...."), { 0.99 }, slip: 1), 8)
    }

    func testWithNoSlipTheBotNeverLoses() {
        func play(_ board: [L.Cell?], _ turn: L.Cell) -> Bool {
            if let w = L.tttWinner(board) {
                if case .won(let who, _) = w { return who != .x }
                return true
            }
            if turn == .o {
                var next = board
                next[L.tttBotMove(board, { 0 }, slip: 0)] = .o
                return play(next, .x)
            }
            return board.indices.allSatisfy { i in
                guard board[i] == nil else { return true }
                var next = board
                next[i] = .x
                return play(next, .o)
            }
        }
        XCTAssertTrue(play(Array(repeating: nil, count: 9), .x))
    }

    func testTheBotCanSlipIntoACasualMoveSoItCanBeBeaten() {
        var moves = Set<Int>()
        for r in [0, 0.2, 0.5, 0.8, 0.95] { moves.insert(L.tttBotMove(B("X........"), seq(0, r), slip: 1)) }
        XCTAssertGreaterThan(moves.count, 1)
        XCTAssertEqual(L.tttBotMove(B("X........"), { 0.99 }, slip: 0), 4)
    }

    // MARK: - Memory

    func testSixPairsShuffled() {
        let deck = L.memoryDeck(L.memoryFaces, pairs: 6, seq(0.1, 0.7, 0.3, 0.9, 0.5))
        XCTAssertEqual(deck.count, 12)
        var counts: [String: Int] = [:]
        deck.forEach { counts[$0.face, default: 0] += 1 }
        XCTAssertEqual(counts.count, 6)
        XCTAssertTrue(counts.values.allSatisfy { $0 == 2 })
        XCTAssertEqual(deck.map(\.id), Array(0..<12))
    }

    func testAPairStaysUpAMissIsCountedAndTurnedBackTheLastPairEndsIt() {
        let cards = ["A", "B", "A", "B"].enumerated().map { L.MemoryCard(id: $0.offset, face: $0.element, matched: false) }
        var s = L.MemoryState(cards: cards, open: [], moves: 0)
        var r = L.memoryFlip(s, 0)
        XCTAssertEqual(r.result, .open)
        r = L.memoryFlip(r.state, 0)
        XCTAssertEqual(r.result, .ignored)
        r = L.memoryFlip(r.state, 1)
        XCTAssertEqual(r.result, .miss)
        XCTAssertEqual(r.state.moves, 1)
        XCTAssertEqual(L.memoryFlip(r.state, 2).result, .ignored)
        s = L.memoryHide(r.state)
        r = L.memoryFlip(L.memoryFlip(s, 0).state, 2)
        XCTAssertEqual(r.result, .match)
        XCTAssertTrue(r.state.cards[0].matched && r.state.cards[2].matched)
        XCTAssertEqual(L.memoryFlip(r.state, 0).result, .ignored)
        r = L.memoryFlip(L.memoryFlip(r.state, 1).state, 3)
        XCTAssertEqual(r.result, .done)
        XCTAssertEqual(r.state.moves, 3)
    }

    func testStarsForFewerMoves() {
        XCTAssertEqual(L.memoryStars(6), 3)
        XCTAssertEqual(L.memoryStars(9), 3)
        XCTAssertEqual(L.memoryStars(12), 2)
        XCTAssertEqual(L.memoryStars(20), 1)
    }

    // MARK: - Quiz

    static let cats: [[String: Any]] = [
        ["name": "Billing", "articles": [
            ["_id": "1", "title": "Downloading invoices", "description": "Find every invoice in one place."],
            ["_id": "2", "title": "Changing your plan", "description": "Upgrade, downgrade or cancel at any time."],
        ]],
        ["name": "Account", "articles": [["_id": "3", "title": "Resetting your password", "description": ""]]],
        ["name": "Shipping", "articles": [["_id": "4", "title": "Tracking an order", "description": "See where your parcel is."]]],
    ]

    func testQuestionsFromTheHelpCentreTheRightAnswerAmongTheOptions() {
        let qs = L.quizFromArticles(Self.cats, [], seq(0.3, 0.6, 0.1, 0.8))
        XCTAssertEqual(qs.count, 3)
        for q in qs {
            XCTAssertEqual(q.source, .kb)
            XCTAssertEqual(q.options.count, 3)
            XCTAssertGreaterThanOrEqual(q.answer, 0)
            XCTAssertEqual(Set(q.options).count, 3)
        }
        let pw = qs.first { $0.q.contains("Resetting your password") }
        XCTAssertNotNil(pw)
        XCTAssertEqual(pw.map { $0.options[$0.answer] }, "Account")
        XCTAssertEqual(pw?.q, "Where in our help centre would you find \"Resetting your password\"?")
    }

    func testTooFewArticlesMeansTrivia() {
        XCTAssertEqual(L.quizFromArticles([["name": "x", "articles": [["title": "Only one"]]]], []), [])
        let qs = L.buildQuiz(L.trivia, [], seq(0.2, 0.4, 0.6))
        XCTAssertEqual(qs.count, 3)
        XCTAssertTrue(qs.allSatisfy { $0.source == .trivia && $0.options.count == 3 })
    }

    func testHelpCentreQuestionsComeFirstToppedUpWithTrivia() {
        let kb = Array(L.quizFromArticles(Self.cats, [], seq(0.5)).prefix(1))
        XCTAssertEqual(L.buildQuiz(L.trivia, kb, seq(0.5)).map(\.source), [.kb, .trivia, .trivia])
    }

    func testScoringAndTheVerdict() {
        let qs = [0, 2, 1].map { L.QuizQuestion(q: "", options: [], answer: $0, source: .trivia) }
        XCTAssertEqual(L.quizScore(qs, [0, 2, 1]), 3)
        XCTAssertEqual(L.quizScore(qs, [0, 1, 1]), 2)
        XCTAssertEqual(L.quizScore(qs, [1, 1, 0]), 0)
        XCTAssertTrue(L.quizVerdict(3, 3).contains("Perfect"))
        XCTAssertTrue(L.quizVerdict(0, 3).contains("another go"))
        XCTAssertTrue(L.quizVerdict(2, 3).contains("So close"))
    }

    // MARK: - Reflex, word scramble, emoji riddles

    func testAFairRandomWaitAndAFriendlyVerdict() {
        XCTAssertEqual(L.reactionDelay({ 0 }), 1200)
        XCTAssertEqual(L.reactionDelay({ 1 }), 3400)
        XCTAssertTrue(L.reactionVerdict(200).contains("Lightning"))
        XCTAssertTrue(L.reactionVerdict(300).contains("Sharp"))
        XCTAssertTrue(L.reactionVerdict(400).contains("Nicely"))
        XCTAssertTrue(L.reactionVerdict(600).contains("steady"))
        XCTAssertEqual(L.average([200, 300, 401]), 300)
        XCTAssertFalse(L.reactionCounts(40))
        XCTAssertTrue(L.reactionCounts(180))
    }

    func testAScrambleIsNeverTheWordItselfAndAnyCaseSolvesIt() {
        for w in L.words.map(\.w) {
            let s = L.scrambleWord(w, seq(0.99, 0.98, 0.97, 0.96, 0.95, 0.94))
            XCTAssertNotEqual(s.joined(), w)
            XCTAssertEqual(s.sorted(), w.map(String.init).sorted())
        }
        XCTAssertTrue(L.scrambleSolved(" planet ", "PLANET"))
        XCTAssertFalse(L.scrambleSolved("PLANTE", "PLANET"))
    }

    func testFourRiddleOptionsOneRight() {
        for r in L.riddles {
            let o = L.riddleOptions(r, seq(0.4, 0.1))
            XCTAssertEqual(o.options.count, 4)
            XCTAssertEqual(o.options[o.answer], r.a)
            XCTAssertEqual(Set(o.options).count, 4)
        }
    }

    func testNoEmDashesInTheWords() {
        let all = (L.trivia.flatMap { [$0.q, $0.a] + $0.wrong } + L.riddles.flatMap { [$0.e, $0.a] + $0.wrong }
            + L.words.map(\.w) + [L.Verdict.perfect, L.Verdict.tough, L.Verdict.close, L.Verdict.notBad, L.Verdict.nice]).joined()
        XCTAssertFalse(all.contains("\u{2014}"))
    }
}
