//
//  GamesCard.swift
//  Conferbot
//
//  Waiting games: the in-chat card as a state machine, with no UI. Ported
//  from the React Native SDK (src/core/gamesCard.ts), itself from the web
//  widget's conferbot-widget src/ts/chat/games/ui.ts (mountGamesCard and the
//  seven game factories): the offer (the owner's line and a chip per game),
//  then the game itself, then "Play again" / "Another game"; folded away when
//  a teammate joins ("Finish my game"). Every change is a new `state`
//  snapshot that a view draws (UI/SwiftUI/GamesCardView.swift), and every
//  tap is a call.
//
//  Timers go through the injected clock. A game's pending steps (the bot's
//  move, cards turning back, the next round) are held while the card is
//  paused and run on resume, as the web's ctx.queued. With `reducedMotion`
//  the rock-paper-scissors shake is skipped and the bot moves sooner.
//
//  Nothing here is sent anywhere or stored: the games are the visitor's own
//  and leave no trace in the transcript.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

/// The card's words (web i18n/en.ts "games.*").
public enum GamesText {
    public static let card = "Games while you wait"
    public static let close = "Close games"
    public static let pick = "Pick a game"
    public static let again = "Play again"
    public static let another = "Another game"
    public static let notNow = "Not now"
    public static func pausedNamed(_ name: String) -> String { "\(name)'s here!" }
    public static let pausedSomeone = "Someone's here!"
    public static let pausedSaved = "Your game is saved - finish it later?"
    public static let resume = "Finish my game"
}

public struct FootButton: Equatable {
    public enum Key: String { case notNow, again, another, action, resume }
    public let key: Key
    public let label: String
    public let primary: Bool
}

public struct RpsBoard: Equatable {
    public struct HandChip: Equatable { public let hand: GamesLogic.Hand; public let emoji: String; public let name: String }
    public var you: String
    public var bot: String
    public var outcome: GamesLogic.Outcome?
    public var shaking: Bool
    public var busy: Bool
    public var hands: [HandChip]
}

public struct TttBoard: Equatable {
    public var cells: [GamesLogic.Cell?]
    public var line: [Int]
    public var over: Bool
    public var thinking: Bool
}

public struct MemoryBoard: Equatable {
    public struct Face: Equatable { public let face: String; public let up: Bool; public let matched: Bool }
    public var cards: [Face]
    public var pop: [Int]
}

public struct ChoiceBoard: Equatable {
    public var game: GameId
    public var tag: String?
    public var big: String?
    public var q: String
    public var options: [String]
    public var answer: Int
    public var picked: Int?
}

public struct ReactionBoard: Equatable {
    public enum Phase: String { case idle, wait, go, between, done }
    public var state: Phase
    public var big: String
    public var line: String
}

public struct ScrambleBoard: Equatable {
    public var hint: String
    public var letters: [String]
    /// Slot i holds letters[placed[i]].
    public var placed: [Int]
    public var solved: Bool
    public var revealed: Bool
    /// Bumped on a wrong word (the slots shake).
    public var nope: Int
    public var skipLabel: String
}

public enum GameBoard: Equatable {
    case rps(RpsBoard), ttt(TttBoard), memory(MemoryBoard), choice(ChoiceBoard), reaction(ReactionBoard), scramble(ScrambleBoard)

    public var rps: RpsBoard? { if case .rps(let b) = self { return b }; return nil }
    public var ttt: TttBoard? { if case .ttt(let b) = self { return b }; return nil }
    public var memory: MemoryBoard? { if case .memory(let b) = self { return b }; return nil }
    public var choice: ChoiceBoard? { if case .choice(let b) = self { return b }; return nil }
    public var reaction: ReactionBoard? { if case .reaction(let b) = self { return b }; return nil }
    public var scramble: ScrambleBoard? { if case .scramble(let b) = self { return b }; return nil }
}

public struct GamesCardState: Equatable {
    public enum View: String { case menu, game, paused, gone }
    public var view: View = .menu
    public var title = ""
    public var titleEmoji = ""
    /// The score or progress at the card's top right.
    public var meta = ""
    /// The line under the game (announced politely).
    public var status = ""
    public var result: String?   // "win" | "done"
    /// A finished game left as a result when a teammate joined: no buttons, no close.
    public var settled = false
    public var closable = true
    /// The menu's games (the owner's, for the language).
    public var chips: [GameMeta] = []
    public var game: GameId?
    public var board: GameBoard?
    public var foot: [FootButton] = []
    /// Bumped for a small "nice!" and for a win's confetti.
    public var cheer = 0
    public var confetti = 0
}

public enum GameInput: Equatable {
    case rps(GamesLogic.Hand)
    case ttt(Int)
    case memory(Int)
    case choice(Int)
    case reaction
    case tile(Int)
    case slot(Int)
    case skip
    /// A hardware key in the word scramble: a letter, or "Backspace".
    case key(String)
}

// MARK: - The games

/// What a game gets from its card (web ui.ts ctx).
final class GameCtx {
    var rng: GamesRng = GamesLogic.random
    var reduced = false
    var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
    var c: [String: Any]?
    var categories: [[String: Any]] = []
    var recent: [[String: Any]] = []
    var plays = 0
    var meta: (String) -> Void = { _ in }
    var status: (String) -> Void = { _ in }
    var finish: (_ text: String, _ win: Bool) -> Void = { _, _ in }
    var cheer: () -> Void = {}
    /// The main button in the footer ("Next"), gone once pressed.
    var action: (_ label: String, _ fn: @escaping () -> Void) -> Void = { _, _ in }
    /// A pending step, held while paused.
    var later: (_ fn: @escaping () -> Void, _ ms: Double) -> Void = { _, _ in }
    /// A timer that a pause drops (the reflex test's wait for green).
    var timer: (_ fn: @escaping () -> Void, _ ms: Double) -> Int = { _, _ in 0 }
    var clear: (Int) -> Void = { _ in }
}

protocol WaitingGame: AnyObject {
    func input(_ a: GameInput)
    func board() -> GameBoard
    func pause()
}

extension WaitingGame { func pause() {} }

private final class RpsGame: WaitingGame {
    let ctx: GameCtx
    var you = 0, botScore = 0
    var youHand = GamesLogic.emoji(.rock), botHand = GamesLogic.emoji(.rock)
    var outcome: GamesLogic.Outcome?
    var shaking = false, busy = false

    init(_ ctx: GameCtx) {
        self.ctx = ctx
        show()
        ctx.status("First to two wins. Pick your hand!")
    }

    func show() { ctx.meta("You \(you) · \(botScore) Bot") }

    func board() -> GameBoard {
        .rps(RpsBoard(you: youHand, bot: botHand, outcome: outcome, shaking: shaking, busy: busy,
                      hands: GamesLogic.hands.map { .init(hand: $0, emoji: GamesLogic.emoji($0), name: GamesLogic.name($0)) }))
    }

    func input(_ a: GameInput) {
        guard case .rps(let mine) = a, !busy else { return }
        let theirs = GamesLogic.hands[min(2, Int(floor(ctx.rng() * 3)))]
        busy = true
        youHand = GamesLogic.emoji(.rock)
        botHand = GamesLogic.emoji(.rock)
        outcome = nil
        let reveal = { [self] in
            shaking = false
            youHand = GamesLogic.emoji(mine)
            botHand = GamesLogic.emoji(theirs)
            let r = GamesLogic.rpsOutcome(mine, theirs)
            outcome = r
            if r == .win { you += 1 }
            if r == .lose { botScore += 1 }
            show()
            let lower = { (h: GamesLogic.Hand) in GamesLogic.name(h).lowercased() }
            let line = r == .draw ? "\(GamesLogic.name(mine)) and \(lower(theirs)) - a draw!"
                : r == .win ? "\(GamesLogic.name(mine)) beats \(lower(theirs)) - point to you!"
                : "\(GamesLogic.name(theirs)) beats \(lower(mine)) - point to the bot."
            if let w = GamesLogic.rpsWinner(you: you, bot: botScore) {
                ctx.finish(w == "you" ? "\(line) You win \(you)-\(botScore)! 🎉" : "\(line) The bot takes it \(botScore)-\(you). Rematch? 🤖", w == "you")
                return
            }
            ctx.status(line)
            busy = false
        }
        if ctx.reduced {
            reveal()
        } else {
            shaking = true
            ctx.status("Rock... paper... scissors...")
            ctx.later(reveal, 900)
        }
    }
}

private final class TttGame: WaitingGame {
    let ctx: GameCtx
    var cells = [GamesLogic.Cell?](repeating: nil, count: 9)
    var over = false, busy = false
    var line: [Int] = []

    init(_ ctx: GameCtx) {
        self.ctx = ctx
        ctx.meta("You ✕ · Bot ◯")
        // Turns alternate between games: the bot opens every second one.
        if ctx.plays % 2 == 1 { botTurn() } else { ctx.status("You go first - tap a square") }
    }

    func check() -> Bool {
        guard let w = GamesLogic.tttWinner(cells) else { return false }
        over = true
        switch w {
        case .won(let who, let l):
            line = l
            if who == .x { ctx.finish("Three in a row - you beat the bot! 🎉", true) } else { ctx.finish("The bot got this one. Rematch? 🤖", false) }
        case .draw:
            line = []
            ctx.finish("A draw - great minds think alike 🤝", false)
        }
        return true
    }

    func botTurn() {
        busy = true
        ctx.status("The bot is thinking...")
        ctx.later({ [self] in
            let m = GamesLogic.tttBotMove(cells, ctx.rng)
            if m >= 0 { cells[m] = .o }
            busy = false
            if !check() { ctx.status("Your move") }
        }, ctx.reduced ? 250 : 550)
    }

    func board() -> GameBoard { .ttt(TttBoard(cells: cells, line: line, over: over, thinking: busy)) }

    func input(_ a: GameInput) {
        guard case .ttt(let i) = a, !over, !busy, i >= 0, i <= 8, cells[i] == nil else { return }
        cells[i] = .x
        if !check() { botTurn() }
    }
}

private final class MemoryGame: WaitingGame {
    let ctx: GameCtx
    var s: GamesLogic.MemoryState
    var waiting = false
    var pop: [Int] = []

    init(_ ctx: GameCtx) {
        self.ctx = ctx
        s = GamesLogic.MemoryState(cards: GamesLogic.memoryDeck(GamesLogic.memoryFaces, pairs: 6, ctx.rng), open: [], moves: 0)
        paint()
        ctx.status("Find all six pairs")
    }

    func paint() {
        let pairs = s.cards.filter(\.matched).count / 2
        ctx.meta("Moves \(s.moves) · Pairs \(pairs)/6")
    }

    func board() -> GameBoard {
        .memory(MemoryBoard(cards: s.cards.enumerated().map { .init(face: $0.element.face, up: $0.element.matched || s.open.contains($0.offset), matched: $0.element.matched) }, pop: pop))
    }

    func input(_ a: GameInput) {
        guard case .memory(let i) = a, !waiting else { return }
        let r = GamesLogic.memoryFlip(s, i)
        guard r.result != .ignored else { return }
        s = r.state
        pop = []
        paint()
        switch r.result {
        case .match:
            ctx.status("A pair! ✨")
            // The pair just made (the card tapped and its twin).
            let face = s.cards[i].face
            pop = s.cards.indices.filter { s.cards[$0].face == face }
        case .miss:
            ctx.status("Not a pair")
            waiting = true
            ctx.later({ [self] in
                s = GamesLogic.memoryHide(s)
                waiting = false
                paint()
            }, 850)
        case .done:
            ctx.finish("All pairs in \(s.moves) moves! \(String(repeating: "⭐", count: GamesLogic.memoryStars(s.moves)))", true)
        default:
            break
        }
    }
}

private struct Round {
    var q: String
    var big: String?
    var tag: String?
    var options: [String]
    var answer: Int
}

private let rightLines = ["Correct! 🎯", "Spot on! ✨", "Nailed it! 🙌", "Yes! 🎉"]

/// Shared by the quiz and the emoji riddles: a round at a time, three in all.
private final class ChoiceGame: WaitingGame {
    let ctx: GameCtx
    let game: GameId
    let rounds: [Round]
    let summary: (Int, Int) -> (text: String, win: Bool)
    var at = 0, score = 0, shown = 0
    var picked: Int?

    init(_ ctx: GameCtx, _ game: GameId, _ rounds: [Round], _ summary: @escaping (Int, Int) -> (text: String, win: Bool)) {
        self.ctx = ctx
        self.game = game
        self.rounds = rounds
        self.summary = summary
        showRound()
    }

    func meta() { ctx.meta("\(shown + 1) of \(rounds.count) · \(score) right") }

    func showRound() {
        shown = at
        picked = nil
        meta()
    }

    func board() -> GameBoard {
        let r = rounds[shown]
        return .choice(ChoiceBoard(game: game, tag: r.tag, big: r.big, q: r.q, options: r.options, answer: r.answer, picked: picked))
    }

    func input(_ a: GameInput) {
        guard case .choice(let i) = a, picked == nil else { return }
        let r = rounds[shown]
        guard i >= 0, i < r.options.count else { return }
        picked = i
        let right = i == r.answer
        if right { score += 1 }
        meta()
        if right { ctx.cheer() }
        let fb = right ? rightLines[Int(floor(ctx.rng() * Double(rightLines.count))) % rightLines.count] : "Not quite - it's \(r.options[r.answer])"
        at += 1
        if at >= rounds.count {
            let s = summary(score, rounds.count)
            ctx.finish("\(fb). \(s.text)", s.win)
            return
        }
        ctx.status(fb)
        ctx.action(at == rounds.count - 1 ? "Last one →" : "Next →") { [weak self] in self?.showRound() }
    }
}

private func quizGame(_ ctx: GameCtx) -> WaitingGame {
    let kb = ctx.c?["enableKnowledgeBase"] as? Bool == true ? GamesLogic.quizFromArticles(ctx.categories, ctx.recent, ctx.rng) : []
    let qs = GamesLogic.buildQuiz(GamesLogic.trivia, kb, ctx.rng)
    ctx.status(kb.isEmpty ? "Three quick questions" : "Three questions - some about our help centre")
    return ChoiceGame(ctx, .quiz, qs.map { Round(q: $0.q, big: nil, tag: $0.source == .kb ? "From our help centre" : nil, options: $0.options, answer: $0.answer) }) { score, total in
        ("\(score) out of \(total). \(GamesLogic.quizVerdict(score, total))", score == total)
    }
}

private func emojiGame(_ ctx: GameCtx) -> WaitingGame {
    let picked = Array(GamesLogic.shuffle(GamesLogic.riddles, ctx.rng).prefix(3))
    ctx.status("What phrase do the emoji spell?")
    return ChoiceGame(ctx, .emoji, picked.map { r in
        let o = GamesLogic.riddleOptions(r, ctx.rng)
        return Round(q: "What's the phrase?", big: r.e, tag: nil, options: o.options, answer: o.answer)
    }) { score, total in
        ("\(score) of \(total) riddles solved. \(GamesLogic.quizVerdict(score, total))", score == total)
    }
}

public enum GamesRounds {
    public static let reaction = 3
    public static let scramble = 3
}

private final class ReactionGame: WaitingGame {
    let ctx: GameCtx
    var times: [Int] = []
    var phase: ReactionBoard.Phase = .idle
    var big = "⚡"
    var line = "Tap to start"
    var goAt: Double = 0
    var timer: Int?

    init(_ ctx: GameCtx) {
        self.ctx = ctx
        ctx.meta("Round 1 of \(GamesRounds.reaction)")
        ctx.status("When the pad turns green, tap as fast as you can")
    }

    func set(_ p: ReactionBoard.Phase, _ e: String, _ text: String) {
        phase = p
        big = e
        line = text
    }

    func start() {
        set(.wait, "👀", "Wait for green...")
        ctx.meta("Round \(times.count + 1) of \(GamesRounds.reaction)")
        timer = ctx.timer({ [self] in
            timer = nil
            goAt = ctx.now()
            set(.go, "🟢", "Tap now!")
        }, GamesLogic.reactionDelay(ctx.rng))
    }

    func board() -> GameBoard { .reaction(ReactionBoard(state: phase, big: big, line: line)) }

    // On press, not on release, so the time is the visitor's.
    func input(_ a: GameInput) {
        guard case .reaction = a else { return }
        switch phase {
        case .idle, .between:
            start()
        case .wait:
            if let t = timer { ctx.clear(t) }
            timer = nil
            set(.between, "🙈", "Too soon! Tap to try again")
            ctx.status("Too soon - wait for green")
        case .go:
            let ms = Int((ctx.now() - goAt).rounded())
            guard GamesLogic.reactionCounts(ms) else {
                set(.between, "🙈", "A lucky guess! Tap to try again")
                ctx.status("Too quick to be real - wait until you see green")
                return
            }
            times.append(ms)
            if times.count >= GamesRounds.reaction {
                let avg = GamesLogic.average(times)
                set(.done, "🏁", "\(avg) ms average")
                ctx.meta(times.map(String.init).joined(separator: " · ") + " ms")
                ctx.finish("\(GamesLogic.reactionVerdict(avg)) - \(avg) ms on average.", avg < 350)
                return
            }
            set(.between, "⏱️", "\(ms) ms - tap for the next round")
            ctx.status("\(ms) milliseconds")
        case .done:
            break
        }
    }

    func pause() {
        if let t = timer { ctx.clear(t) }
        timer = nil
        if phase == .wait || phase == .go { set(.between, "⏸️", "Tap to carry on") }
    }
}

private final class ScrambleGame: WaitingGame {
    let ctx: GameCtx
    let words: [GamesLogic.Word]
    var at = 0, solved = 0
    var letters: [String] = []
    var placed: [Int] = []
    var isSolved = false, revealed = false
    var nope = 0
    var word = "", hint = ""

    init(_ ctx: GameCtx) {
        self.ctx = ctx
        words = Array(GamesLogic.shuffle(GamesLogic.words, ctx.rng).prefix(GamesRounds.scramble))
        // The web's intro says "or just type": a phone has no keys to type on.
        ctx.status("Tap the letters in order")
        round()
    }

    func round() {
        word = words[at].w
        hint = words[at].hint
        letters = GamesLogic.scrambleWord(word, ctx.rng)
        placed = []
        isSolved = false
        revealed = false
        ctx.meta("Word \(at + 1) of \(GamesRounds.scramble) · \(solved) solved")
    }

    func next(_ msg: String, _ win: Bool) {
        at += 1
        if win { solved += 1 }
        ctx.meta("Word \(min(at + 1, GamesRounds.scramble)) of \(GamesRounds.scramble) · \(solved) solved")
        if at >= GamesRounds.scramble {
            let verdict = solved == GamesRounds.scramble ? "Word wizard! 🧙" : solved > 0 ? GamesLogic.Verdict.nice : "Tricky ones! 🙈"
            ctx.finish("\(msg) You solved \(solved) of \(GamesRounds.scramble). \(verdict)", solved == GamesRounds.scramble)
            return
        }
        ctx.status(msg)
        ctx.later({ [weak self] in self?.round() }, win ? 1100 : 1500)
    }

    func check() {
        guard placed.count >= letters.count else { return }
        let guess = placed.map { letters[$0] }.joined()
        if GamesLogic.scrambleSolved(guess, word) {
            isSolved = true
            ctx.cheer()
            next("\(word) - got it! 🎉", true)
        } else {
            nope += 1
            ctx.status("Not quite - tap letters to take them back")
        }
    }

    func put(_ i: Int) {
        guard i >= 0, i < letters.count, !placed.contains(i), placed.count < letters.count, !isSolved else { return }
        placed.append(i)
        check()
    }

    func board() -> GameBoard {
        .scramble(ScrambleBoard(hint: hint, letters: letters, placed: placed, solved: isSolved, revealed: revealed, nope: nope,
                                skipLabel: at == GamesRounds.scramble - 1 ? "Reveal" : "Skip"))
    }

    func input(_ a: GameInput) {
        switch a {
        case .tile(let i):
            put(i)
        case .slot(let i):
            guard !isSolved, i >= 0, i < placed.count else { return }
            placed.removeSubrange(i...)
        case .key(let k):
            guard !isSolved else { return }
            if k == "Backspace" {
                if !placed.isEmpty { placed.removeLast() }
                return
            }
            guard k.count == 1, k.range(of: "^[a-zA-Z]$", options: .regularExpression) != nil else { return }
            if let i = letters.indices.first(where: { letters[$0] == k.uppercased() && !placed.contains($0) }) { put(i) }
        case .skip:
            guard !isSolved else { return }
            isSolved = true
            revealed = true
            placed = []
            for ch in word.map(String.init) {
                let i = letters.indices.first { letters[$0] == ch && !placed.contains($0) } ?? -1
                placed.append(i)
            }
            next("It was \(word).", false)
        default:
            break
        }
    }
}

private func makeGame(_ id: GameId, _ ctx: GameCtx) -> WaitingGame {
    switch id {
    case .rps: return RpsGame(ctx)
    case .ttt: return TttGame(ctx)
    case .quiz: return quizGame(ctx)
    case .memory: return MemoryGame(ctx)
    case .reaction: return ReactionGame(ctx)
    case .emoji: return emojiGame(ctx)
    case .scramble: return ScrambleGame(ctx)
    }
}

// MARK: - The card

/// One card (web mountGamesCard). Starts on the menu: with the owner's
/// offer line for an offer, "Pick a game" when the visitor asked. Main thread.
public final class GamesCard: ObservableObject, OfferCard {
    public struct Options {
        var customizations: [String: Any]?
        var categories: [[String: Any]] = []
        var recentArticles: [[String: Any]] = []
        /// "offer": the owner's line; "menu": the visitor asked for the games.
        var mode: GamesOffer.Mode = .offer
        var rng: GamesRng = GamesLogic.random
        var reducedMotion = false
        /// The language the games are offered in (the emoji riddles are English only).
        var lang = "en"
        /// The card was closed ("Not now", the x).
        var onDismiss: (() -> Void)?
        var schedule: ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer
        /// A clock in milliseconds, for the reflex test.
        var now: () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 }
    }

    /// The card as last drawn; every change publishes a new one.
    @Published public private(set) var state = GamesCardState()

    private let o: Options
    private let settings: WaitingGames.Settings
    private var st = GamesCardState()
    private final class Entry {
        let id: GameId
        var game: WaitingGame?
        var timers: [Int: SignalTimer] = [:]
        var queued: [Int: () -> Void] = [:]
        var over = false
        init(_ id: GameId) { self.id = id }
    }
    private var current: Entry?
    private var plays = 0
    private var action: (() -> Void)?
    private var held: [() -> Void] = []
    private var nextTimerId = 0
    private var listeners: [Int: (GamesCardState) -> Void] = [:]
    private var nextListener = 0

    /// Nil when the owner left no game for this language.
    init?(_ o: Options) {
        let settings = WaitingGames.settings(o.customizations)
        let available = WaitingGames.forLanguage(WaitingGames.games.filter { settings.games.contains($0.id) }, o.lang)
        guard !available.isEmpty else { return nil }
        self.o = o
        self.settings = settings
        st.chips = available
        showMenu(first: true)
        state = st
    }

    private func emit() {
        if let g = current?.game { st.board = g.board() }
        state = st
        for fn in listeners.values { fn(st) }
    }

    /// Every snapshot as it is published (for tests and hosts). Returns the unsubscribe.
    @discardableResult
    public func subscribe(_ fn: @escaping (GamesCardState) -> Void) -> () -> Void {
        nextListener += 1
        let id = nextListener
        listeners[id] = fn
        return { [weak self] in self?.listeners[id] = nil }
    }

    private func stopTimers() {
        current?.timers.values.forEach { $0.cancel() }
    }

    private static let quietAnother = FootButton(key: .another, label: GamesText.another, primary: false)

    private func showMenu(first: Bool) {
        stopTimers()
        current = nil
        action = nil
        st.view = .menu
        st.settled = false
        st.closable = true
        st.game = nil
        st.board = nil
        st.titleEmoji = ""
        st.title = first && o.mode != .menu ? settings.offerText : GamesText.pick
        st.meta = ""
        st.status = ""
        st.result = nil
        st.foot = [FootButton(key: .notNow, label: GamesText.notNow, primary: false)]
    }

    private func openGame(_ id: GameId) {
        guard let g = WaitingGames.meta(id), settings.games.contains(id), st.view != .gone else { return }
        stopTimers()
        action = nil
        st.view = .game
        st.game = id
        st.titleEmoji = g.emoji
        st.title = g.name
        st.meta = ""
        st.status = ""
        st.result = nil
        st.settled = false
        st.closable = true
        st.foot = [Self.quietAnother]
        let entry = Entry(id)
        let ctx = GameCtx()
        ctx.rng = o.rng
        ctx.reduced = o.reducedMotion
        ctx.now = o.now
        ctx.c = o.customizations
        ctx.categories = o.categories
        ctx.recent = o.recentArticles
        ctx.plays = plays
        ctx.meta = { [weak self] t in self?.st.meta = t }
        ctx.status = { [weak self] t in self?.st.status = t }
        ctx.action = { [weak self] label, fn in
            guard let self = self else { return }
            self.action = fn
            self.st.foot = self.st.foot.filter { $0.key != .action } + [FootButton(key: .action, label: label, primary: true)]
        }
        ctx.cheer = { [weak self] in
            guard let self = self, !self.o.reducedMotion else { return }
            self.st.cheer += 1
        }
        ctx.finish = { [weak self, weak entry] text, win in
            guard let self = self else { return }
            entry?.over = true
            self.action = nil
            self.st.result = win ? "win" : "done"
            self.st.status = text
            if win && !self.o.reducedMotion { self.st.confetti += 1 }
            self.st.foot = [FootButton(key: .again, label: GamesText.again, primary: true),
                            FootButton(key: .another, label: GamesText.another, primary: false)]
        }
        ctx.later = { [weak self, weak entry] fn, ms in
            guard let self = self, let entry = entry else { return }
            self.nextTimerId += 1
            let id = self.nextTimerId
            entry.timers[id] = self.o.schedule(ms / 1000) { [weak self, weak entry] in
                guard let self = self, let entry = entry else { return }
                entry.timers[id] = nil
                entry.queued[id] = nil
                guard self.current === entry else { return }
                fn()
                self.emit()
            }
            entry.queued[id] = fn
        }
        ctx.timer = { [weak self, weak entry] fn, ms in
            guard let self = self, let entry = entry else { return 0 }
            self.nextTimerId += 1
            let id = self.nextTimerId
            entry.timers[id] = self.o.schedule(ms / 1000) { [weak self, weak entry] in
                guard let self = self, let entry = entry else { return }
                entry.timers[id] = nil
                guard self.current === entry else { return }
                fn()
                self.emit()
            }
            return id
        }
        ctx.clear = { [weak entry] id in
            entry?.timers[id]?.cancel()
            entry?.timers[id] = nil
        }
        plays += 1
        current = entry
        entry.game = makeGame(id, ctx)
    }

    private func removeNow() {
        stopTimers()
        current = nil
        action = nil
        st.view = .gone
        st.board = nil
        st.foot = []
    }

    // MARK: - Calls

    public func open(_ id: GameId) {
        openGame(id)
        emit()
    }

    public func menu() {
        guard st.view != .gone else { return }
        showMenu(first: false)
        emit()
    }

    /// A footer button.
    public func press(_ key: FootButton.Key) {
        guard st.foot.contains(where: { $0.key == key }) else { return }
        switch key {
        case .notNow:
            return dismiss()
        case .again:
            if let c = current { openGame(c.id) }
        case .another:
            showMenu(first: false)
        case .resume:
            resume()
        case .action:
            if let fn = action {
                action = nil
                st.foot = st.foot.filter { $0.key != .action }
                fn()
            }
        }
        emit()
    }

    /// A tap inside the game.
    public func input(_ a: GameInput) {
        guard st.view == .game, let c = current, !c.over else { return }
        c.game?.input(a)
        emit()
    }

    /// The x.
    public func dismiss() {
        guard st.view != .gone else { return }
        removeNow()
        emit()
        o.onDismiss?()
    }

    public func wrapUp(_ name: String) {
        guard st.view != .paused, st.view != .gone else { return }
        guard let c = current else {
            // Only the offer or the menu: nothing to keep.
            removeNow()
            return emit()
        }
        if c.over {
            // A finished game stays as a result, without its buttons.
            st.foot = []
            st.settled = true
            st.closable = false
            return emit()
        }
        c.game?.pause()
        // Hold the game's pending steps for "Finish my game": dropped, the board would stay locked.
        held = c.queued.sorted { $0.key < $1.key }.map(\.value)
        stopTimers()
        c.timers = [:]
        c.queued = [:]
        action = nil
        let who = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        st.view = .paused
        st.titleEmoji = "👋"
        st.title = who.isEmpty ? GamesText.pausedSomeone : GamesText.pausedNamed(who)
        st.status = GamesText.pausedSaved
        st.foot = [FootButton(key: .resume, label: GamesText.resume, primary: false)]
        emit()
    }

    private func resume() {
        guard let c = current, st.view == .paused else { return }
        let g = WaitingGames.meta(c.id)
        st.view = .game
        st.titleEmoji = g?.emoji ?? ""
        st.title = g?.name ?? ""
        st.status = ""
        st.foot = []
        let run = held
        held = []
        run.forEach { $0() }
    }

    public func remove() {
        guard st.view != .gone else { return }
        removeNow()
        emit()
    }

    /// A game is under way (not the menu, not a finished one).
    public var playing: Bool { st.view == .game && current != nil && current?.over == false }
    public var up: Bool { st.view != .gone }
    /// The state now (the published one lags only inside a call).
    public var snapshot: GamesCardState { st }
}
