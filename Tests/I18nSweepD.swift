//
//  I18nSweepD.swift
//  ConferbotTests
//
//  The home screen, "Your requests", the greeting card, the launcher's
//  label and idle call, the mascot's typing words and the header tagline in
//  German (RN __tests__/core/i18nCore.test.ts: 'while you wait, requests and
//  timestamps', 'queue, rating, home and greeting', 'the idle call').
//

import XCTest
@testable import Conferbot

extension I18nSweepTests {

    /// Every String inside a value (structs, enums, arrays, optionals, tuples).
    func strings(of value: Any) -> [String] {
        if let s = value as? String { return [s] }
        return Mirror(reflecting: value).children.flatMap { strings(of: $0.value) }
    }

    func testRequestsAndTheirTimesInGerman() {
        XCTAssertEqual(Requests.Text.title, de("requests.title"))
        XCTAssertEqual(Requests.Text.seeAll(4), de("requests.seeAll", ["n": 4]))
        XCTAssertEqual(Requests.Text.newReplyFrom("Ada"), de("requests.newReplyFrom", ["name": "Ada"]))
        XCTAssertEqual(Requests.Text.menu(1), "\(de("requests.title")) · \(de("requests.newReply"))")
        XCTAssertEqual(Requests.stateWords(.solved).label, de("requests.solved.label"))
        for s in [RequestState.replied, .waiting, .solved] {
            assertNoEnglish(Requests.stateWords(s).label, "state label")
            assertNoEnglish(Requests.stateWords(s).detail, "state detail")
        }
        for w in [Requests.Text.one, Requests.Text.back, Requests.Text.loading, Requests.Text.loadFailed, Requests.Text.tryAgain,
                  Requests.Text.empty, Requests.Text.you, Requests.Text.supportTeam, Requests.Text.replyPlaceholder,
                  Requests.Text.reopenPlaceholder, Requests.Text.yourReply, Requests.Text.send, Requests.Text.sending,
                  Requests.Text.notSent, Requests.Text.locked, Requests.Text.newReply] {
            assertNoEnglish(w, "requests")
        }

        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15))!.timeIntervalSince1970 * 1000
        let at = { (y: Int, m: Int, d: Int, h: Int) in
            Requests.iso(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!.timeIntervalSince1970 * 1000)
        }
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 10_000), now: now), de("when.justNow"))
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 5 * 60_000), now: now), de("when.minutesAgo", ["n": 5]))
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 70 * 60_000), now: now), de("when.hourAgo"))
        XCTAssertEqual(Requests.whenWords(Requests.iso(now - 3 * 3_600_000), now: now), de("when.hoursAgo", ["n": 3]))
        XCTAssertEqual(Requests.whenWords(at(2026, 10, 15, 12), now: now), de("when.yesterday"))
        XCTAssertEqual(Requests.whenWords(at(2026, 10, 12, 9), now: now), "Montag")
        let oct = Requests.whenWords(at(2026, 10, 3, 9), now: now)
        XCTAssertTrue(oct.contains("3") && oct.contains("Okt"), oct)
        let dec = Requests.whenWords(at(2025, 12, 24, 9), now: now)
        XCTAssertTrue(dec.contains("24") && dec.contains("Dez") && dec.contains("2025"), dec)

        let r = RequestSummary(id: "mobile_1_abc", title: "Rechnung", status: .open, lastAt: Requests.iso(now - 2 * 3_600_000),
                               lastFrom: .team, lastText: "Erledigt", teamName: "")
        XCTAssertEqual(Requests.rowLine(r, seen: [:], now: now), "\(de("requests.newReply")) · \(de("when.hoursAgo", ["n": 2]))")
        assertNoEnglish(Requests.rowLine(r, seen: [r.id: now], now: now), "rowLine")
    }

    func testTheHomeScreenInGerman() {
        XCTAssertEqual(Home.Text.helpCentre, de("home.helpCentre"))
        XCTAssertEqual(Home.Text.welcomeBackName("Jamie"), de("home.welcomeBackName", ["name": "Jamie"]))
        let (before, after) = Home.Text.askQueryParts
        XCTAssertEqual("\(before)Q\(after)", de("home.askQuery", ["query": "Q"]))
        XCTAssertEqual(Home.salutation(9), de("home.goodMorning"))
        XCTAssertEqual(Home.salutation(2), de("home.hello"))

        let now: Double = 1_800_000_000_000
        let art = { (id: String, title: String) -> [String: Any] in ["_id": id, "title": title, "description": "Schritt für Schritt."] }
        let c: [String: Any] = [
            "enableInitialPage": true, "initialPageTitle": "Hi there 👋", "initialPageCardButtonText": "Chat with us",
            "logo": "https://cdn.x/logo.png", "logoText": "Acme", "homeAskBox": true,
            "homeRating": ["average": 4.8, "count": 1200],
            "replyTime": ["mode": "auto", "handover": true, "state": "online", "bucket": "few_minutes"],
        ]
        let req = RequestSummary(id: "mobile_1_abc", title: "Rechnung", status: .open, lastAt: Requests.iso(now - 3_600_000),
                                 lastFrom: .team, lastText: "Erledigt", teamName: "Ada")
        let input = Home.Input(c: c, botName: "Acme", agent: Home.Agent(displayName: "Ava", starters: ["Preise?"]),
                               categories: [["_id": "c1", "name": "Abrechnung", "articles": [art("1", "Rechnung ändern")]]],
                               recentArticles: [art("2", "Das Widget einbetten")],
                               memory: Home.Memory(name: "Jamie", topic: "Preise", session: "s1", at: now - 60_000),
                               chatSessionId: "s1", requests: [req, req], now: now, hour: 9)
        guard let m = Home.model(input) else { return XCTFail("no home") }
        XCTAssertEqual(m.title, de("home.title"))
        XCTAssertEqual(m.talk.button, de("home.chatWithUs"))
        for s in strings(of: m) { assertNoEnglish(s, "home model") }

        // The owner's own words stay as written.
        var own = c
        own["initialPageTitle"] = "Hallo zusammen"
        own["initialPageCardButtonText"] = "Schreib uns"
        let mine = Home.model(Home.Input(c: own, now: now))!
        XCTAssertEqual(mine.title, "Hallo zusammen")
        XCTAssertEqual(mine.talk.button, "Schreib uns")
    }

    func testTheGreetingLauncherIdleCallAndMascotInGerman() {
        let facts = GreetingFacts(returning: false, signedIn: false)
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "chatIconCtaText": "Hi 👋, how can I help?"], facts: facts)?.text, de("greeting.stock"))
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "chatIconCtaText": "Hallo!"], facts: facts)?.text, "Hallo!")
        XCTAssertEqual(Greeting.head(nil).name, de("home.support"))

        XCTAssertEqual(LauncherIdleCall.line("knock", nil), de("idle.knock"))
        XCTAssertEqual(LauncherIdleCall.line("psst", ""), de("idle.psst"))
        for (_, line) in LauncherIdleCall.lines { assertNoEnglish(line, "idle call") }
        XCTAssertEqual(Launcher.defaultLabel, de("home.chatWithUs"))

        XCTAssertEqual(MascotMoods.typingLabel("mascot", "Pip"), de("typing.named", ["name": "Pip"]))
        XCTAssertEqual(MascotMoods.typingLabel("dots", ""), de("typing.typing"))

        let r = Customizations.resolve(["enableTagline": true, "tagline": "We're here to help"])
        XCTAssertEqual(r.tagline, de("header.tagline"))
        XCTAssertEqual(Customizations.resolve(["enableTagline": true, "tagline": "Montags zu"]).tagline, "Montags zu")
    }
}
