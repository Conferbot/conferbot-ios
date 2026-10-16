//
//  WaitArticles.swift
//  Conferbot
//
//  While you wait for a person: the help that may answer the visitor
//  meanwhile, as one card. Ported from the React Native SDK
//  (src/core/waitArticles.ts), itself from the web widget:
//
//    - conferbot-widget src/ts/chat/waitArticles.ts: WAIT_BEFORE_MS, the
//      articles picked for the visitor's last real question
//      (waitArticlesFor), and the card: up to two rows, "That solved it"
//      when the wait can end there.
//    - src/ts/chat/handlers/special.ts: the timer's start and stop points
//      (waitForPerson), lastVisitorText (ASKS_FOR_PERSON), queueServerSeen,
//      and _wireQueue: the server's own pick (queue-help, or queue-status's
//      `help`) replacing the card when it has new items, and "That solved it"
//      sending queue-self-resolve {chatSessionId, articleId}.
//    - src/ts/home/askBox.ts answersFor / keywordsOf, homeUtils.ts
//      flattenArticles, knowledgeBase/kbUtils.ts tokenize / searchArticles,
//      home/visitorMemory.ts isRealQuestion, core/helpCentre.ts helpCentreOn.
//    - src/ts/chat/handoverState.ts: once the wait is over the card stays as
//      history under "Articles that might help".
//
//  The server (embed-server liveChat/queueHelp.js) emits queue-help
//  { chatSessionId, items: [{ kind: 'article' | 'page', id, title,
//  description, url?, score }], offer } to the chat room; at most two cards
//  per wait. Pure: WaitingExtras feeds it.
//

import Foundation

public enum WaitArticles {

    /// The articles card comes this long into a wait for a person.
    public static let waitBeforeMs: Double = 6000
    /// "That solved it" waits this long for the server's answer.
    public static let solveTimeoutMs: Double = 8000

    public enum Text {
        public static let label = "While you wait"
        public static let title = "While you wait, this might help"
        /// Once nobody is waiting any more (web handover.articlesTitle).
        public static let settledTitle = "Articles that might help"
        public static let read = "Read"
        public static let solved = "That solved it"
        public static let done = "Glad that helped. You have left the queue."
        /// The line drawn for a queue left this way (web queue.leftHelped).
        public static let leftHelped = "You left the queue. Glad that helped."
        /// What the record keeps (web special.ts leave()).
        public static let recordText = "Resolved while waiting"
    }

    // MARK: - Help centre

    /// The help centre is on only when enableKnowledgeBase is true (web core/helpCentre.ts).
    public static func helpCentreOn(_ c: [String: Any]?) -> Bool { c?["enableKnowledgeBase"] as? Bool == true }

    public struct HelpArticle: Equatable {
        public var id: String
        public var title: String
        public var description: String
        public var categoryName: String
        public var text: String
    }

    static func plain(_ html: Any?) -> String {
        var s = html.map { $0 is NSNull ? "" : "\($0)" } ?? ""
        s = replace(s, "(?is)<(script|style)[^>]*>.*?</\\1>", " ")
        s = replace(s, "<[^>]*>", " ")
        s = replace(s, "(?i)&[a-z#0-9]+;", " ")
        s = replace(s, "\\s+", " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func replace(_ s: String, _ pattern: String, _ with: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: with)
    }

    static func matches(_ s: String, _ pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func idOf(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        return "\(v)"
    }

    /// Every article the visitor can open, once each: the categories'
    /// articles first (they carry the category name), then any recent article
    /// not already listed. Only ones with an id and a title (web homeUtils.ts).
    public static func flattenArticles(_ categories: [[String: Any]], _ recent: [[String: Any]] = []) -> [HelpArticle] {
        var out: [HelpArticle] = []
        var seen = Set<String>()
        func add(_ a: [String: Any], _ categoryName: String) {
            let id = idOf(a["_id"])
            let title = (a["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !title.isEmpty, !seen.contains(id) else { return }
            seen.insert(id)
            out.append(HelpArticle(id: id, title: title, description: (a["description"] as? String) ?? "",
                                   categoryName: categoryName, text: plain(a["content"])))
        }
        for c in categories {
            for a in (c["articles"] as? [[String: Any]]) ?? [] { add(a, (c["name"] as? String) ?? "") }
        }
        for a in recent { add(a, ((a["category"] as? [String: Any])?["name"] as? String) ?? "") }
        return out
    }

    /// An article by id among the bot's help centre data, or nil.
    public static func findArticle(_ id: String, _ categories: [[String: Any]], _ recent: [[String: Any]]) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        for c in categories {
            if let hit = ((c["articles"] as? [[String: Any]]) ?? []).first(where: { idOf($0["_id"]) == id }) { return hit }
        }
        return recent.first { idOf($0["_id"]) == id }
    }

    // MARK: - Search (web kbUtils.ts, askBox.ts)

    private static let wordSplit = try! NSRegularExpression(pattern: "[^a-z0-9\\u00C0-\\uFFFF]+")

    public static func tokenize(_ query: String) -> [String] {
        let s = query.lowercased()
        let marked = wordSplit.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\u{0}")
        let words = marked.split(separator: "\u{0}").map(String.init).filter { !$0.isEmpty }
        // One-letter words only count when they are all there is.
        let long = words.filter { $0.count > 1 }
        var seen = Set<String>()
        return (long.isEmpty ? words : long).filter { seen.insert($0).inserted }
    }

    private static func escape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    /// Rank articles for a query. Every word must appear somewhere (title,
    /// summary, category or body); titles weigh most, then summaries, then
    /// the category, then the body. A title that starts with the query wins.
    public static func searchArticles(_ articles: [HelpArticle], _ query: String) -> [HelpArticle] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var scored: [(article: HelpArticle, score: Int, index: Int)] = []
        outer: for (index, article) in articles.enumerated() {
            let title = article.title.lowercased()
            let desc = article.description.lowercased()
            let cat = article.categoryName.lowercased()
            let body = article.text.lowercased()
            var score = 0
            for t in tokens {
                let inTitle = title.contains(t), inDesc = desc.contains(t), inCat = cat.contains(t), inBody = body.contains(t)
                if !inTitle && !inDesc && !inCat && !inBody { continue outer } // every word must match
                if inTitle { score += matches(title, "(^|[^a-z0-9\\u00C0-\\uFFFF])\(escape(t))") ? 12 : 8 }
                if inDesc { score += 4 }
                if inCat { score += 3 }
                if inBody { score += 1 }
            }
            if !phrase.isEmpty && title.hasPrefix(phrase) { score += 10 } else if !phrase.isEmpty && title.contains(phrase) { score += 5 }
            scored.append((article, score, index))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.article)
    }

    // Words that say nothing about what the question is about.
    private static let stop = Set((
        "a an and are as at be but by can could did do does for from get got had has have how i if in is it its " +
        "me my of on or our so that the their them then there this to us was we what when where which who why " +
        "will with would you your yours about any anyone need want please hi hello hey tell know help there's " +
        "i'm im ive i've dont don't cant can't"
    ).split(separator: " ").map(String.init))

    /// The words of a question worth matching on (no "how do I ...").
    public static func keywordsOf(_ query: String) -> [String] {
        tokenize(query).filter { ($0.count > 2 || $0.contains(where: \.isNumber)) && !stop.contains($0) }
    }

    // A word and its plain forms: "changing" also finds "change", "plans" "plan".
    private static func stemsOf(_ w: String) -> [String] {
        var out = [w]
        if w.count > 5 && w.hasSuffix("ing") { let b = String(w.dropLast(3)); out += [b, b + "e"] }
        if w.count > 4 && w.hasSuffix("es") { out.append(String(w.dropLast(2))) }
        if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") { out.append(String(w.dropLast(1))) }
        if w.count > 4 && w.hasSuffix("ed") { out += [String(w.dropLast(2)), String(w.dropLast(1))] }
        return out
    }

    private static func has(_ text: String, _ w: String) -> Bool { stemsOf(w).contains { text.contains($0) } }

    /// The articles that answer a question, best first: those matching every
    /// word, then those matching most of its key words, weighted to titles.
    public static func answersFor(_ articles: [HelpArticle], _ query: String, max: Int = 4) -> [HelpArticle] {
        let strict = searchArticles(articles, query)
        let seen = Set(strict.map(\.id))
        let words = keywordsOf(query)
        let need = Swift.max(1, Int((Double(words.count) / 2).rounded(.up)))
        struct Ranked { let a: HelpArticle; let hits: Int; let score: Int; let index: Int }
        var ranked: [Ranked] = []
        if !words.isEmpty {
            for (index, a) in articles.filter({ !seen.contains($0.id) }).enumerated() {
                let title = a.title.lowercased()
                let desc = "\(a.description) \(a.categoryName)".lowercased()
                let body = a.text.lowercased()
                var hits = 0, score = 0
                for w in words {
                    let t = has(title, w), d = has(desc, w), b = has(body, w)
                    if t || d || b { hits += 1 }
                    if t { score += 6 }
                    if d { score += 3 }
                    if b { score += 1 }
                }
                if hits >= need { ranked.append(Ranked(a: a, hits: hits, score: score, index: index)) }
            }
        }
        ranked.sort { x, y in
            if x.hits != y.hits { return x.hits > y.hits }
            if x.score != y.score { return x.score > y.score }
            return x.index < y.index
        }
        let loose = ranked.map(\.a)
        return Array((strict + loose).prefix(max))
    }

    // MARK: - The question

    private static let greetingOnly =
        "(?i)^(hi+|hey+|hello+|yo|hiya|ok(ay)?|thanks?|thank you|thx|ty|yes|no|yep|nope|sure|cool|great|bye|good (morning|afternoon|evening))[\\s!.?,]*$"

    /// Is this a question worth matching (web visitorMemory.ts)?
    public static func isRealQuestion(_ text: String) -> Bool {
        let t = replace(text, "\\s+", " ").trimmingCharacters(in: .whitespaces)
        if t.count < 10 || t.count > 300 { return false }
        if matches(t, greetingOnly) { return false }
        if matches(t, "^\\S+@\\S+\\.\\S+$") || matches(t, "^[+\\d\\s().-]{7,}$") { return false }
        return t.split(separator: " ", omittingEmptySubsequences: false).filter { matches(String($0), "(?i)[a-z\\u00C0-\\uFFFF]{2,}") }.count >= 3
    }

    /// "Can I talk to a person" says nothing about the problem (web special.ts).
    public static let asksForPerson =
        "(?i)\\b(human|person|agent|someone|somebody|representative|operator|real people|staff|talk to|speak to|speak with|call me)\\b"

    /// The visitor's last real question in their own words (web special.ts
    /// lastVisitorText): the newest typed message that is a real question and
    /// not an ask for a person.
    public static func waitQuestion(_ record: [[String: Any]]?) -> String {
        let kinds: Set<String> = ["user-message", "user-input-response", "user-live-message", "user-input"]
        for r in (record ?? []).reversed() {
            let type = (r["type"] as? String) ?? ""
            let kind = type.isEmpty ? ((r["shape"] as? String) ?? "") : type
            guard kinds.contains(kind) else { continue }
            let raw = r["text"] ?? r["value"]
            let s = raw.map { $0 is NSNull ? "" : "\($0)" } ?? ""
            let text = replace(replace(s, "<[^>]*>", " "), "\\s+", " ").trimmingCharacters(in: .whitespaces)
            if isRealQuestion(text) && !matches(text, asksForPerson) { return text }
        }
        return ""
    }

    // MARK: - The card

    /// The articles to offer for this question (none when the help centre is off).
    public static func waitArticlesFor(_ c: [String: Any]?, _ question: String, _ categories: [[String: Any]], _ recent: [[String: Any]]) -> [HelpItem] {
        guard helpCentreOn(c), !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return answersFor(flattenArticles(categories, recent), question, max: 2).map {
            HelpItem(kind: .article, id: $0.id, title: $0.title, description: $0.description.isEmpty ? nil : $0.description)
        }
    }

    private static func safeUrl(_ u: Any?) -> String? {
        guard let s = u as? String, matches(s, "(?i)^https?://") else { return nil }
        return s
    }

    /// The server's items (queue-help, queue-status help), cleaned: an id and a title each.
    public static func helpItemsOf(_ data: [String: Any]?) -> [HelpItem] {
        let items = (data?["items"] as? [Any]) ?? []
        return items.compactMap { raw -> HelpItem? in
            guard let i = raw as? [String: Any] else { return nil }
            let id = idOf(i["id"])
            let title = (i["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !title.isEmpty else { return nil }
            let kind: HelpItem.Kind = i["kind"] as? String == "page" ? .page : .article
            let desc = (i["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HelpItem(kind: kind, id: id, title: title,
                            description: (desc ?? "").isEmpty ? nil : desc,
                            url: kind == .page ? safeUrl(i["url"]) : nil)
        }
    }
}

/// One row of the help card: an article in the app, or a page in the browser.
public struct HelpItem: Equatable {
    public enum Kind: String { case article, page }
    public var kind: Kind
    public var id: String
    public var title: String
    public var description: String?
    /// A page's address (http/https only).
    public var url: String?

    public init(kind: Kind, id: String, title: String, description: String? = nil, url: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.description = description
        self.url = url
    }
}

public struct HelpCardState: Equatable {
    /// Bumped each time a new card replaces the old (it is drawn at the end again).
    public var key: Int
    public var items: [HelpItem]
    /// The wait can end here ("That solved it"): only the server's pick.
    public var solvable: Bool
    /// The wait is over: the history title, no button.
    public var settled: Bool
    /// "That solved it" is waiting for the server.
    public var busy: Bool
    /// Left the queue this way: "Glad that helped."
    public var done: Bool
}

/// The help card's rules. startWait() where a wait for a person begins
/// (with no AI agent taking it first), endWait() wherever it ends; feed the
/// server's queue-status and queue-help in; solving() / solved(ok) around
/// the queue-self-resolve call. Main thread.
public final class WaitHelp {
    public struct Options {
        /// The bot's customizations (the help centre switch).
        var customizations: () -> [String: Any]?
        /// The visitor's last real question (waitQuestion of the record).
        var question: () -> String
        /// The bot's help centre: categories and recent articles.
        var articles: () -> (categories: [[String: Any]], recent: [[String: Any]])
        /// A person is here already (a join the timer missed).
        var joined: () -> Bool
        /// The card changed (nil: none).
        var onChange: (HelpCardState?) -> Void
        var schedule: ConnectingSignal.Schedule = ConnectingSignal.mainQueueTimer
    }

    private let o: Options
    private var timer: SignalTimer?
    // The server keeps a queue: it picks the help itself, ours stays out.
    private var serverSeen = false
    private var helpKey = ""
    private var done = false
    private var opened: HelpItem?
    public private(set) var card: HelpCardState?
    private var key = 0

    init(_ o: Options) { self.o = o }

    private func set(_ next: HelpCardState?) {
        card = next
        o.onChange(card)
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func mount(_ items: [HelpItem], solvable: Bool) {
        guard !items.isEmpty else { return }
        opened = nil
        key += 1
        set(HelpCardState(key: key, items: items, solvable: solvable, settled: false, busy: false, done: false))
    }

    private func showServerHelp(_ data: [String: Any]?) {
        let items = WaitArticles.helpItemsOf(data)
        let k = items.map(\.id).joined(separator: ",")
        guard !done, !items.isEmpty, k != helpKey else { return }
        helpKey = k
        mount(items, solvable: true)
    }

    /// A wait for a person began: after waitBeforeMs, the articles for their question.
    public func startWait() {
        cancel()
        // A new wait: the server's pick and "That solved it" start over (web _wireQueue).
        helpKey = ""
        done = false
        timer = o.schedule(WaitArticles.waitBeforeMs / 1000) { [weak self] in
            guard let self = self else { return }
            self.timer = nil
            let question = self.o.question()
            guard !question.isEmpty, !self.serverSeen, !self.o.joined() else { return }
            let kb = self.o.articles()
            self.mount(WaitArticles.waitArticlesFor(self.o.customizations(), question, kb.categories, kb.recent), solvable: false)
        }
    }

    /// The wait ended (a person, nobody, left, ended): no card yet to come; one drawn stays as history.
    public func endWait() {
        cancel()
        if var c = card, !c.settled {
            c.settled = true
            c.solvable = c.done ? c.solvable : false
            c.busy = false
            set(c)
        }
    }

    /// queue-status (event or answer): a waiting status means the server picks the help.
    public func queueStatus(_ data: [String: Any]?) {
        guard !done, let data = data, data["status"] as? String == "waiting" else { return }
        serverSeen = true
        if let help = data["help"] as? [String: Any] { showServerHelp(help) }
    }

    /// queue-help: the server's pick for this wait.
    public func queueHelp(_ data: [String: Any]?) {
        serverSeen = true
        showServerHelp(data)
    }

    /// A row was opened (it is the article "That solved it" names).
    public func open(_ id: String) {
        opened = card?.items.first { $0.id == id }
    }

    /// "That solved it" pressed: the article to send, or nil when it cannot go now.
    public func solving() -> HelpItem? {
        guard var c = card, c.solvable, !c.busy, !c.done, !c.settled else { return nil }
        c.busy = true
        set(c)
        return opened ?? c.items.first
    }

    /// The server's answer: ok leaves the queue ("Glad that helped."), else the button comes back.
    public func solved(_ ok: Bool) {
        guard var c = card else { return }
        c.busy = false
        if ok {
            done = true
            cancel()
            c.done = true
        }
        set(c)
    }

    /// Left the queue another way (queue-left from another device): no more server cards.
    public func left() {
        done = true
        cancel()
    }

    /// A new conversation.
    public func reset() {
        cancel()
        serverSeen = false
        helpKey = ""
        done = false
        opened = nil
        if card != nil { set(nil) }
    }
}
