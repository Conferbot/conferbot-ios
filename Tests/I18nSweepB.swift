//
//  I18nSweepB.swift
//  ConferbotTests
//
//  The waiting games in German (RN __tests__/core/i18nCore.test.ts, "the
//  games and their lists"): the names, the offer, the hands, the verdicts,
//  the lists per language, and every line of each game played through.
//

import XCTest
@testable import Conferbot

extension I18nSweepTests {

    func testTheGamesNamesOfferHandsAndVerdictsInGerman() {
        XCTAssertEqual(WaitingGames.games[0].name, de("games.rps.name"))
        XCTAssertEqual(WaitingGames.games[0].blurb, de("games.rps.blurb"))
        XCTAssertEqual(WaitingGames.offerLine(WaitingGames.defaultOfferText), de("games.offer"))
        XCTAssertEqual(WaitingGames.offerLine("Spiel?"), "Spiel?")
        XCTAssertEqual(GamesLogic.name(.rock), de("games.rps.rock"))
        XCTAssertEqual(GamesLogic.quizVerdict(3, 3), de("games.verdict.perfect"))
        XCTAssertEqual(GamesLogic.reactionVerdict(200), de("games.reaction.fast"))
        XCTAssertNotEqual(GamesLogic.triviaFor("de").first?.q, GamesLogic.trivia.first?.q)
        XCTAssertEqual(GamesLogic.wordsFor("xx"), GamesLogic.wordsFor("en"))
        XCTAssertEqual(GamesText.pausedNamed("Ada"), de("games.paused.named", ["name": "Ada"]))
        for g in WaitingGames.games {
            assertNoEnglish(g.name, "name")
            assertNoEnglish(g.blurb, "blurb")
        }
    }

    func testTheEmojiRiddlesAreNotOfferedInGermanAndTheCardSpeaksGerman() {
        XCTAssertNil(GamesCard(GamesCard.Options(customizations: ["waitingGames": ["games": ["emoji"]]])))
        let card = GamesCard(GamesCard.Options(customizations: [:]))!
        XCTAssertEqual(card.state.title, de("games.offer"))
        XCTAssertFalse(card.state.chips.map(\.id).contains(.emoji))
        XCTAssertEqual(card.state.foot.map(\.label), [de("common.notNow")])
    }

    private func words(_ s: GamesCardState) -> [String] {
        var out = [s.title, s.meta, s.status] + s.foot.map(\.label) + s.chips.flatMap { [$0.name, $0.blurb] }
        switch s.board {
        case .rps(let b)?: out += b.hands.map(\.name)
        case .choice(let b)?: out += [b.q, b.tag ?? ""] + b.options
        case .reaction(let b)?: out.append(b.line)
        case .scramble(let b)?: out.append(b.skipLabel)
        default: break
        }
        return out
    }

    /// Plays each game through in German and checks every line drawn.
    func testEveryGamePlayedThroughInGermanHasNoEnglish() {
        var seen: [String] = []
        for id in GameId.allCases where id != .emoji {
            let k = FakeClock()
            var o = GamesCard.Options(customizations: [:])
            var n = 0.0
            o.rng = { n += 0.37; return n.truncatingRemainder(dividingBy: 1) }
            o.schedule = k.schedule
            o.now = { k.now * 1000 }
            let card = GamesCard(o)!
            _ = card.subscribe { seen += self.words($0) }
            seen += words(card.state)
            card.open(id)
            for step in 0..<40 {
                switch id {
                case .rps: card.input(.rps(GamesLogic.hands[step % 3]))
                case .ttt: card.input(.ttt(step % 9))
                case .memory: card.input(.memory(step % 12))
                case .quiz: card.input(.choice(step % 3)); card.press(.action)
                case .reaction: card.input(.reaction); k.tick(step % 2 == 0 ? 0.05 : 4)
                case .scramble: if step % 4 == 0 { card.input(.skip) } else { card.input(.tile(step % 6)) }
                case .emoji: break
                }
                k.tick(2)
            }
            card.wrapUp("Ada")
            seen += words(card.state)
            card.press(.resume)
            seen += words(card.state)
        }
        for w in Set(seen) { assertNoEnglish(w, "games") }
        XCTAssertTrue(seen.contains(de("games.paused.named", ["name": "Ada"])) || seen.contains(de("games.again")))
    }
}
