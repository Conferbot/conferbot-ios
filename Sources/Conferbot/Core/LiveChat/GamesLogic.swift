//
//  GamesLogic.swift
//  Conferbot
//
//  Waiting games: the rules and the words, with no UI, so they can be
//  tested on their own. Ported from the React Native SDK
//  (src/core/gamesLogic.ts), itself from the web widget:
//  conferbot-widget src/ts/chat/games/logic.ts (every rule as it is) and
//  src/ts/chat/games/content.ts (the quiz and scramble per language come
//  from the bundled i18n table, Core/I18n, generated from it; the emoji
//  riddles are English wordplay). Words are the web's "games.*" keys, read
//  with I18n.t as logic.ts does. Every random choice takes an `rng`
//  (0 ..< 1) so tests can pin it.
//

import Foundation

public typealias GamesRng = () -> Double

public enum GamesLogic {

    public static let random: GamesRng = { Double.random(in: 0..<1) }

    /// A shuffled copy (Fisher-Yates).
    public static func shuffle<T>(_ items: [T], _ rng: GamesRng = random) -> [T] {
        var out = items
        var i = out.count - 1
        while i > 0 {
            let j = Int(floor(rng() * Double(i + 1)))
            out.swapAt(i, min(j, i))
            i -= 1
        }
        return out
    }

    public static func pick<T>(_ items: [T], _ rng: GamesRng = random) -> T {
        items[Int(floor(rng() * Double(items.count))) % items.count]
    }

    // MARK: - Content (web content.ts)

    public struct Trivia: Equatable { public let q: String; public let a: String; public let wrong: [String] }
    public struct Riddle: Equatable { public let e: String; public let a: String; public let wrong: [String] }
    public struct Word: Equatable { public let w: String; public let hint: String }

    /// The quiz in a language, English for any other (web content.ts triviaFor).
    public static func triviaFor(_ lang: String) -> [Trivia] {
        I18n.trivia(lang).compactMap { t in
            guard let q = t["q"] as? String, let a = t["a"] as? String else { return nil }
            return Trivia(q: q, a: a, wrong: (t["wrong"] as? [String]) ?? [])
        }
    }

    /// The scramble words in a language (web content.ts wordsFor).
    public static func wordsFor(_ lang: String) -> [Word] {
        I18n.words(lang).compactMap { w in
            guard let word = w["w"] as? String else { return nil }
            return Word(w: word, hint: (w["hint"] as? String) ?? "")
        }
    }

    /// The English quiz (web content.ts TRIVIA; every language in the i18n table).
    public static var trivia: [Trivia] { triviaFor("en") }

    public static let riddles: [Riddle] = [
        Riddle(e: "☀️🌻", a: "Sunflower", wrong: ["Daisy", "Sunrise", "Sunscreen"]),
        Riddle(e: "⭐🐟", a: "Starfish", wrong: ["Goldfish", "Swordfish", "Shooting star"]),
        Riddle(e: "🥵🐶", a: "Hot dog", wrong: ["Puppy love", "Sunbathing", "Dog days"]),
        Riddle(e: "🍿🎬", a: "Movie night", wrong: ["Popcorn party", "Film star", "Snack time"]),
        Riddle(e: "🐛📚", a: "Bookworm", wrong: ["Library", "Caterpillar", "Homework"]),
        Riddle(e: "🧈🪰", a: "Butterfly", wrong: ["Dragonfly", "Firefly", "Bumblebee"]),
        Riddle(e: "🌙🚶", a: "Moonwalk", wrong: ["Night shift", "Sleepwalk", "Stargazing"]),
        Riddle(e: "☕⏸️", a: "Coffee break", wrong: ["Morning rush", "Tea time", "Wake up call"]),
        Riddle(e: "🐟🍟", a: "Fish and chips", wrong: ["Sushi", "Fish fingers", "Seafood"]),
        Riddle(e: "🍯🌙", a: "Honeymoon", wrong: ["Sweet dreams", "Moonlight", "Bedtime"]),
        Riddle(e: "🌧️🏹", a: "Rainbow", wrong: ["Raincoat", "Archery", "Storm"]),
        Riddle(e: "☀️👓", a: "Sunglasses", wrong: ["Sunburn", "Eyesight", "Daylight"]),
        Riddle(e: "🧀🎂", a: "Cheesecake", wrong: ["Pizza", "Fondue", "Cupcake"]),
        Riddle(e: "⌚🐶", a: "Watchdog", wrong: ["Hot dog", "Dog walk", "Clockwork"]),
        Riddle(e: "🦶⚽", a: "Football", wrong: ["Footprint", "Basketball", "Kick off"]),
        Riddle(e: "🌊🏄", a: "Surfing", wrong: ["Swimming", "Sailing", "Beach day"]),
    ]

    /// The English scramble words (web content.ts WORDS).
    public static var words: [Word] { wordsFor("en") }

    public static let memoryFaces = ["🍕", "🚀", "🌵", "🐙", "🎈", "🍩", "🦊", "🌈", "⚽", "🎧", "🍉", "🐢", "🦄", "🍦"]

    // MARK: - Rock paper scissors

    public enum Hand: String, CaseIterable, Equatable { case rock, paper, scissors }
    public static let hands: [Hand] = [.rock, .paper, .scissors]
    public static func emoji(_ h: Hand) -> String { h == .rock ? "✊" : h == .paper ? "✋" : "✌️" }
    /// Each hand's name in the active language (web ui.ts handName, games.rps.*).
    public static func name(_ h: Hand) -> String { I18n.t("games.rps.\(h.rawValue)") }
    private static func beats(_ h: Hand) -> Hand { h == .rock ? .scissors : h == .paper ? .rock : .paper }

    public enum Outcome: String, Equatable { case win, lose, draw }

    /// From the visitor's side.
    public static func rpsOutcome(_ you: Hand, _ bot: Hand) -> Outcome {
        you == bot ? .draw : beats(you) == bot ? .win : .lose
    }

    /// Best of three: the first to two wins.
    public static let rpsToWin = 2
    public static func rpsWinner(you: Int, bot: Int) -> String? {
        you >= rpsToWin ? "you" : bot >= rpsToWin ? "bot" : nil
    }

    // MARK: - Tic-tac-toe

    public enum Cell: String, Equatable { case x = "X", o = "O" }
    public static let lines: [[Int]] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    public enum TttResult: Equatable { case won(Cell, [Int]), draw }

    /// The winner and the line, a draw on a full board, else nil.
    public static func tttWinner(_ board: [Cell?]) -> TttResult? {
        for l in lines {
            if let a = board[l[0]], a == board[l[1]], a == board[l[2]] { return .won(a, l) }
        }
        return board.allSatisfy { $0 != nil } ? .draw : nil
    }

    private static func empties(_ board: [Cell?]) -> [Int] { board.indices.filter { board[$0] == nil } }

    /// The square that completes a line for `who`, or -1.
    public static func tttFinisher(_ board: [Cell?], _ who: Cell) -> Int {
        for l in lines {
            let mine = l.filter { board[$0] == who }.count
            let open = l.filter { board[$0] == nil }
            if mine == 2 && open.count == 1 { return open[0] }
        }
        return -1
    }

    private static func minimax(_ board: inout [Cell?], _ turn: Cell, _ depth: Int) -> Int {
        if let w = tttWinner(board) {
            if case .won(let who, _) = w { return who == .o ? 10 - depth : depth - 10 }
            return 0
        }
        let scores: [Int] = empties(board).map { i in
            board[i] = turn
            let s = minimax(&board, turn == .o ? .x : .o, depth + 1)
            board[i] = nil
            return s
        }
        return turn == .o ? scores.max()! : scores.min()!
    }

    /// The bot (O): always takes a win, always blocks one, and otherwise
    /// plays its best move - except now and then (`slip`, 0-1) it plays a
    /// casual one, so a sharp visitor can set up a fork and beat it.
    public static func tttBotMove(_ board: [Cell?], _ rng: GamesRng = random, slip: Double = 0.3) -> Int {
        let open = empties(board)
        guard !open.isEmpty else { return -1 }
        let win = tttFinisher(board, .o)
        if win >= 0 { return win }
        let block = tttFinisher(board, .x)
        if block >= 0 { return block }
        if rng() < slip { return pick(open, rng) }
        var b = board
        var best = Int.min
        var moves: [Int] = []
        for i in open {
            b[i] = .o
            let s = minimax(&b, .x, 1)
            b[i] = nil
            if s > best {
                best = s
                moves = [i]
            } else if s == best {
                moves.append(i)
            }
        }
        return pick(moves, rng)
    }

    // MARK: - Memory

    public struct MemoryCard: Equatable {
        public let id: Int
        public let face: String
        public var matched: Bool
    }

    /// `pairs` faces from the pool, each twice, shuffled (4x3 = 6 pairs).
    public static func memoryDeck(_ pool: [String], pairs: Int = 6, _ rng: GamesRng = random) -> [MemoryCard] {
        let faces = Array(shuffle(pool, rng).prefix(pairs)).flatMap { [$0, $0] }
        return shuffle(faces, rng).enumerated().map { MemoryCard(id: $0.offset, face: $0.element, matched: false) }
    }

    public struct MemoryState: Equatable {
        public var cards: [MemoryCard]
        /// Face-up cards not yet matched (0, 1 or 2).
        public var open: [Int]
        public var moves: Int
    }

    public enum FlipResult: String, Equatable { case ignored, open, match, miss, done }

    /// Turn a card over. Two open cards make a move: a pair stays up, a miss
    /// reports "miss" (the caller turns them back after a beat with `memoryHide`).
    public static func memoryFlip(_ s: MemoryState, _ id: Int) -> (state: MemoryState, result: FlipResult) {
        guard id >= 0, id < s.cards.count, !s.cards[id].matched, !s.open.contains(id), s.open.count < 2 else { return (s, .ignored) }
        let open = s.open + [id]
        if open.count < 2 { return (MemoryState(cards: s.cards, open: open, moves: s.moves), .open) }
        let a = s.cards[open[0]], b = s.cards[open[1]]
        let moves = s.moves + 1
        if a.face == b.face {
            let cards = s.cards.map { c -> MemoryCard in
                var c = c
                if c.id == a.id || c.id == b.id { c.matched = true }
                return c
            }
            let done = cards.allSatisfy(\.matched)
            return (MemoryState(cards: cards, open: [], moves: moves), done ? .done : .match)
        }
        return (MemoryState(cards: s.cards, open: open, moves: moves), .miss)
    }

    public static func memoryHide(_ s: MemoryState) -> MemoryState { MemoryState(cards: s.cards, open: [], moves: s.moves) }

    /// Three stars for a near-perfect run, down to one.
    public static func memoryStars(_ moves: Int, pairs: Int = 6) -> Int {
        moves <= pairs + 3 ? 3 : moves <= pairs * 2 + 2 ? 2 : 1
    }

    // MARK: - Quiz

    public struct QuizQuestion: Equatable {
        public enum Source: String { case kb, trivia }
        public let q: String
        public let options: [String]
        public let answer: Int
        /// Where it came from: the bot's help centre, or the trivia pool.
        public let source: Source
    }

    private static func cleanText(_ v: Any?, _ max: Int) -> String {
        guard let s = v as? String else { return "" }
        return String(WaitArticles.replace(WaitArticles.replace(s, "<[^>]*>", " "), "\\s+", " ")
            .trimmingCharacters(in: .whitespaces).prefix(max))
    }

    /// Options in a random order, the right one tracked.
    private static func asQuestion(_ q: String, _ right: String, _ wrong: [String], _ source: QuizQuestion.Source, _ rng: GamesRng) -> QuizQuestion {
        let options = shuffle([right] + wrong, rng)
        return QuizQuestion(q: q, options: options, answer: options.firstIndex(of: right) ?? 0, source: source)
    }

    private struct Item: Equatable { let title: String; let desc: String; let cat: String }

    /// Questions from the bot's own help centre: "Which of our articles
    /// helps with: <its summary>" and "Where in our help centre would you
    /// find <title>?". Needs three titled articles (and three categories for
    /// the second kind); none otherwise.
    public static func quizFromArticles(_ categories: [[String: Any]], _ recent: [[String: Any]], _ rng: GamesRng = random, count: Int = 3) -> [QuizQuestion] {
        var seen = Set<String>()
        var items: [Item] = []
        func add(_ a: [String: Any], _ cat: String) {
            let title = cleanText(a["title"], 70)
            guard !title.isEmpty, !seen.contains(title.lowercased()) else { return }
            seen.insert(title.lowercased())
            items.append(Item(title: title, desc: cleanText(a["description"], 120), cat: cat))
        }
        for c in categories {
            for a in (c["articles"] as? [[String: Any]]) ?? [] { add(a, cleanText(c["name"], 40)) }
        }
        for a in recent { add(a, "") }
        guard items.count >= 3 else { return [] }
        var cats: [String] = []
        for i in items where !i.cat.isEmpty && !cats.contains(i.cat) { cats.append(i.cat) }
        var out: [QuizQuestion] = []
        for it in shuffle(items, rng) {
            if out.count >= count { break }
            let others = Array(shuffle(items.filter { $0 != it }, rng).map(\.title).prefix(2))
            if !it.desc.isEmpty && it.desc.lowercased() != it.title.lowercased() && others.count == 2 {
                out.append(asQuestion(I18n.t("games.quiz.kbWhich", ["desc": it.desc]), it.title, others, .kb, rng))
            } else if !it.cat.isEmpty && cats.count >= 3 {
                let wrong = Array(shuffle(cats.filter { $0 != it.cat }, rng).prefix(2))
                out.append(asQuestion(I18n.t("games.quiz.kbWhere", ["title": it.title]), it.cat, wrong, .kb, rng))
            }
        }
        return out
    }

    /// The quiz: help-centre questions first, topped up with trivia.
    public static func buildQuiz(_ pool: [Trivia], _ kb: [QuizQuestion], _ rng: GamesRng = random, count: Int = 3) -> [QuizQuestion] {
        var out = Array(kb.prefix(count))
        for t in shuffle(pool, rng) {
            if out.count >= count { break }
            out.append(asQuestion(t.q, t.a, Array(t.wrong.prefix(2)), .trivia, rng))
        }
        return out
    }

    /// How many of `picks` are right.
    public static func quizScore(_ questions: [QuizQuestion], _ picks: [Int]) -> Int {
        questions.enumerated().reduce(0) { n, e in n + (e.offset < picks.count && picks[e.offset] == e.element.answer ? 1 : 0) }
    }

    /// The verdicts in the active language (web logic.ts, games.verdict.*).
    public enum Verdict {
        public static var perfect: String { I18n.t("games.verdict.perfect") }
        public static var tough: String { I18n.t("games.verdict.tough") }
        public static var close: String { I18n.t("games.verdict.close") }
        public static var notBad: String { I18n.t("games.verdict.notBad") }
        public static var nice: String { I18n.t("games.verdict.nice") }
    }

    public static func quizVerdict(_ score: Int, _ total: Int) -> String {
        score == total ? Verdict.perfect : score == 0 ? Verdict.tough : score >= total - 1 ? Verdict.close : Verdict.notBad
    }

    // MARK: - Reflex

    /// A random wait before green: 1.2 to 3.4 seconds (ms).
    public static func reactionDelay(_ rng: GamesRng = random) -> Double { 1200 + (rng() * 2200).rounded() }

    /// Faster than any person can see it: a lucky guess, counted as too soon.
    public static let reactionMinMs = 100
    public static func reactionCounts(_ ms: Int) -> Bool { ms >= reactionMinMs }

    public static func reactionVerdict(_ ms: Int) -> String {
        I18n.t(ms < 250 ? "games.reaction.fast" : ms < 350 ? "games.reaction.sharp" : ms < 500 ? "games.verdict.nice" : "games.reaction.steady")
    }

    public static func average(_ xs: [Int]) -> Int {
        xs.isEmpty ? 0 : Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded())
    }

    // MARK: - Word scramble

    /// The word's letters in an order that is not the word itself.
    public static func scrambleWord(_ word: String, _ rng: GamesRng = random) -> [String] {
        let letters = word.uppercased().map(String.init)
        guard Set(letters).count >= 2 else { return letters }
        for _ in 0..<20 {
            let s = shuffle(letters, rng)
            if s != letters { return s }
        }
        return letters.reversed()
    }

    public static func scrambleSolved(_ guess: String, _ word: String) -> Bool {
        guess.trimmingCharacters(in: .whitespaces).uppercased() == word.trimmingCharacters(in: .whitespaces).uppercased()
    }

    // MARK: - Emoji riddles

    /// One riddle's options, shuffled, with the answer's index.
    public static func riddleOptions(_ r: Riddle, _ rng: GamesRng = random) -> (options: [String], answer: Int) {
        let options = shuffle([r.a] + r.wrong.prefix(3), rng)
        return (options, options.firstIndex(of: r.a) ?? 0)
    }
}
