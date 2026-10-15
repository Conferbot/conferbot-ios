import XCTest
@testable import Conferbot

/// The greeting card as the web decides it (RN __tests__/core/greeting.test.ts).
final class GreetingTests: XCTestCase {

    private let new = GreetingFacts(returning: false, signedIn: false)
    private let now = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")!.timeIntervalSince1970 * 1000

    func testShowsNothingWhenTheGreetingIsOff() {
        XCTAssertNil(Greeting.decide(["chatIconCtaText": "Hi"], facts: new))
        XCTAssertNil(Greeting.decide(nil, facts: new))
    }

    func testShowsTheDefaultMessageAfter3sOpeningTheChatOnATap() {
        let g = Greeting.decide(["chatIconCta": true, "chatIconCtaText": " Hi there "], facts: new)
        XCTAssertEqual(g?.text, "Hi there")
        XCTAssertEqual(g?.delay, 3)
        XCTAssertEqual(g?.click, "open")
        let h = Greeting.decide(["chatIconCta": true, "chatIconCtaText": "Hi", "greetingDelay": 9999, "greetingClickAction": "send"], facts: new)
        XCTAssertEqual(h?.delay, 3600)
        XCTAssertEqual(h?.click, "send")
    }

    func testUsesARuleForEveryPageNeverOneForAGivenPage() {
        let c: [String: Any] = [
            "chatIconCta": true,
            "chatIconCtaText": "Default",
            "greetingRules": [
                ["matchType": "contains", "pattern": "/pricing", "text": "Pricing help?"],
                ["matchType": "glob", "pattern": "*", "text": "Everywhere", "delay": 1, "clickAction": "send", "starters": ["A", "B"]],
            ],
        ]
        let g = Greeting.decide(c, facts: new)
        XCTAssertEqual(g?.text, "Everywhere")
        XCTAssertEqual(g?.delay, 1)
        XCTAssertEqual(g?.click, "send")
        XCTAssertEqual(g?.starters, ["A", "B"])
    }

    func testRanksRulesByPriorityAndLetsAShowNothingRuleSilenceTheCard() {
        let rules: [[String: Any]] = [
            ["matchType": "contains", "pattern": "/", "text": "Low", "priority": 10],
            ["matchType": "contains", "pattern": "/", "text": "High", "priority": 90],
        ]
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "greetingRules": rules], facts: new)?.text, "High")
        let silent = rules + [["matchType": "contains", "pattern": "/", "text": "", "action": ["type": "none"], "signedIn": "yes"]]
        XCTAssertNil(Greeting.decide(["chatIconCta": true, "greetingRules": silent], facts: GreetingFacts(returning: false, signedIn: true)))
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "greetingRules": silent], facts: new)?.text, "High")
    }

    func testHonoursWhoAndWhenSkipsWhatOnlyABrowserKnows() {
        func r(_ extra: [String: Any]) -> [String: Any] {
            var rule: [String: Any] = ["matchType": "contains", "pattern": "/", "text": "Rule"]
            extra.forEach { rule[$0.key] = $0.value }
            return ["chatIconCta": true, "chatIconCtaText": "Default", "greetingRules": [rule]]
        }
        XCTAssertEqual(Greeting.decide(r(["visitors": "returning"]), facts: new)?.text, "Default")
        XCTAssertEqual(Greeting.decide(r(["visitors": "returning"]), facts: GreetingFacts(returning: true, signedIn: false))?.text, "Rule")
        XCTAssertEqual(Greeting.decide(r(["endsAt": "2026-10-01T00:00:00Z"]), facts: GreetingFacts(returning: false, signedIn: false, now: now))?.text, "Default")
        XCTAssertEqual(Greeting.decide(r(["endsAt": "2026-10-01T00:00:00.000Z"]), facts: GreetingFacts(returning: false, signedIn: false, now: now))?.text, "Default")
        XCTAssertEqual(Greeting.decide(r(["startsAt": "2026-10-01"]), facts: GreetingFacts(returning: false, signedIn: false, now: now))?.text, "Rule")
        XCTAssertEqual(Greeting.decide(r(["countries": ["GB"]]), facts: new)?.text, "Default")
        XCTAssertEqual(Greeting.decide(r(["source": ["utmSource": "ads"]]), facts: new)?.text, "Default")
        XCTAssertEqual(Greeting.decide(r(["patterns": ["pricing"]]), facts: new)?.text, "Default")
    }

    func testCarriesTheOldProactiveTeaserOverAsTheWebDoes() {
        let g = Greeting.decide(["proactivePromptEnabled": true, "proactivePromptText": "Need help?"], facts: new)
        XCTAssertEqual(g?.text, "Need help?")
        XCTAssertEqual(g?.delay, 8)
        XCTAssertEqual(g?.click, "send")
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "chatIconCtaText": "Hi", "proactivePromptEnabled": true, "proactivePromptText": "Teaser"], facts: new)?.text, "Teaser")
        XCTAssertNil(Greeting.decide(["smartOnly": true], facts: new))
    }

    func testFollowsTheFrequency() {
        let now = 1_000_000_000_000.0
        XCTAssertTrue(Greeting.frequencyAllows([:], seen: GreetingSeen(), now: now))
        XCTAssertFalse(Greeting.frequencyAllows([:], seen: GreetingSeen(closedAt: now - 10_000), now: now))
        XCTAssertTrue(Greeting.frequencyAllows([:], seen: GreetingSeen(closedAt: now - Greeting.pageCooldownSeconds * 1000), now: now))
        XCTAssertFalse(Greeting.frequencyAllows(["greetingFrequency": "session"], seen: GreetingSeen(shownThisSession: true), now: now))
        XCTAssertFalse(Greeting.frequencyAllows(["greetingFrequency": "visitor", "greetingFrequencyDays": 2], seen: GreetingSeen(shownAt: now - 86_400_000), now: now))
        XCTAssertTrue(Greeting.frequencyAllows(["greetingFrequency": "visitor", "greetingFrequencyDays": 2], seen: GreetingSeen(shownAt: now - 3 * 86_400_000), now: now))
    }

    func testHeadsTheCardWithTheAvatarNameAndOnline() {
        XCTAssertEqual(Greeting.head(["avatar": "a.png", "logoText": "Acme"]), GreetingHead(avatar: "a.png", name: "Acme", online: true))
        XCTAssertEqual(Greeting.head(["hideAvatar": true, "avatar": "a.png", "logo": "l.png", "hideOnlineStatus": true], botName: "Bot"),
                       GreetingHead(avatar: "l.png", name: "Bot", online: false))
        XCTAssertEqual(Greeting.normalizeStyle("nope"), "imessage")
        XCTAssertEqual(Greeting.normalizeStyle("sticky"), "sticky")
    }

    func testReadsTheSmartRulesAsTheWeb() {
        let smart: [[String: Any]] = [
            ["id": "sgcust", "matchType": "contains", "pattern": "/", "text": "", "signedIn": "yes", "action": ["type": "none"], "priority": 95],
            ["id": "sgretn", "matchType": "contains", "pattern": "/", "text": "Welcome back!", "behavior": ["minVisits": 2], "priority": 24,
             "limits": ["maxShows": 1, "windowDays": 3, "quietDaysAfterDismiss": 14]],
            ["id": "sgengd", "matchType": "contains", "pattern": "/", "text": "Finding what you need?", "behavior": ["minPagesThisVisit": 3], "priority": 22],
        ]
        let c: [String: Any] = ["chatIconCta": true, "chatIconCtaText": "Default", "greetingRules": smart]
        XCTAssertEqual(Greeting.decide(c, facts: GreetingFacts(returning: false, signedIn: false, visits: 1, now: now))?.text, "Default")
        XCTAssertEqual(Greeting.decide(c, facts: GreetingFacts(returning: true, signedIn: false, visits: 2, now: now))?.text, "Welcome back!")
        XCTAssertEqual(Greeting.decide(c, facts: GreetingFacts(returning: true, signedIn: false, visits: 2, shows: ["sgretn": [now - 86_400_000]], now: now))?.text, "Default")
        XCTAssertEqual(Greeting.decide(c, facts: GreetingFacts(returning: true, signedIn: false, visits: 2, dismissed: ["sgretn": now - 5 * 86_400_000], now: now))?.text, "Default")
        // Signed-in customers: quiet, unless the owner has a rule of their own for them.
        XCTAssertNil(Greeting.decide(c, facts: GreetingFacts(returning: false, signedIn: true, now: now)))
        var own = c
        own["greetingRules"] = smart + [["matchType": "contains", "pattern": "/", "text": "Hi customer", "signedIn": "yes"]]
        XCTAssertEqual(Greeting.decide(own, facts: GreetingFacts(returning: false, signedIn: true, now: now))?.text, "Hi customer")
    }

    func testReadsJSONNullsAndBooleansAsTheWebDoes() throws {
        // The server sends "delay": null on smart rules; a boolean is never a number.
        let json = #"{"chatIconCta":true,"chatIconCtaText":"Hi","greetingRules":[{"id":"sgretn","matchType":"contains","pattern":"/","text":"Back","delay":null,"behavior":{"minVisits":2},"priority":24}]}"#
        let c = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let g = Greeting.decide(c, facts: GreetingFacts(returning: true, signedIn: false, visits: 2))
        XCTAssertEqual(g?.text, "Back")
        XCTAssertEqual(g?.delay, 3)
        XCTAssertEqual(Greeting.decide(["chatIconCta": true, "chatIconCtaText": "Hi", "greetingDelay": true], facts: new)?.delay, 3)
    }

    func testDressesTheCardInTheBotsColours() {
        XCTAssertEqual(Greeting.accent(["brandColor": "#FFFFFF", "headerBgColor": "#0F766E"]), "#0f766e")
        XCTAssertEqual(Greeting.accent(["headerBgColor": "#fef08a", "widgetIconBgColor": "#fde68a"]), "#4f46e5")
        XCTAssertEqual(Greeting.accent(["brandColor": "#1e3a8a", "headerBgColor": "#0F766E", "themeAccent": "#000"]), "#0f766e")
        XCTAssertEqual(Greeting.bubble(["widgetIconBgColor": "#0F766E"]), GreetingBubble(bg: ["#0f766e"], tail: "#0f766e", fg: "#ffffff"))
        XCTAssertEqual(Greeting.bubble(["widgetIconBgColor": "#fde68a"]).fg, "#111827")
        let g = Greeting.bubble(["widgetIconThemeType": "Gradient", "widgetGradientBgOne": "#7c3aed", "widgetGradientBgTwo": "#0d9488"])
        XCTAssertEqual(g.bg, ["#7c3aed", "#0d9488"])
        XCTAssertEqual(g.tail, "#0d9488")
        XCTAssertNil(Greeting.font(["font": "Arial, sans-serif"]))
        XCTAssertEqual(Greeting.font(["font": "Inter"]), "Inter")
    }

    func testDrawsTheVoiceNoteAndTypesAsTheWeb() {
        XCTAssertEqual(Greeting.voiceBars, [30, 93, 41, 44, 38, 65, 74, 73, 84, 47, 44, 32, 74, 37, 98, 52, 67, 38, 42, 65, 64, 94])
        XCTAssertEqual(Greeting.voiceDuration("Hi"), "0:02")
        XCTAssertEqual(Greeting.voiceDuration(Array(repeating: "word", count: 24).joined(separator: " ")), "0:10")
        XCTAssertEqual(Greeting.typeDelay(after: "!"), 204)
        XCTAssertEqual(Greeting.typeDelay(after: "a", random: { 0.5 }), 49)
        XCTAssertEqual(Greeting.width("imessage"), 270)
        XCTAssertEqual(Greeting.width("sticky"), 250)
        XCTAssertEqual(Greeting.width("card"), 296)
    }
}

/// The card's memory per bot (RN useGreeting.ts).
final class GreetingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GreetingStoreTests"
    private let c: [String: Any] = ["chatIconCta": true, "chatIconCtaText": "Hi", "greetingStyle": "sticky", "logoText": "Acme",
                                    "greetingRules": [["id": "sgretn", "matchType": "contains", "pattern": "/", "text": "Welcome back!",
                                                       "behavior": ["minVisits": 2], "priority": 24, "limits": ["maxShows": 1, "windowDays": 3, "quietDaysAfterDismiss": 14]]]]

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        GreetingStore.resetSession()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        GreetingStore.resetSession()
        super.tearDown()
    }

    func testCountsAVisitOncePerAppSessionAndKeepsItPerBot() {
        let s = GreetingStore(botId: "b1", defaults: defaults)
        s.countVisit()
        s.countVisit()
        XCTAssertEqual(s.stored.visits, 1)
        XCTAssertEqual(GreetingStore(botId: "b1", defaults: defaults).stored.visits, 1)
        XCTAssertNotNil(defaults.string(forKey: "conferbot.greeting.b1"))
        XCTAssertEqual(GreetingStore(botId: "b2", defaults: defaults).stored.visits, 0)
        // The next app session is a returning visit.
        GreetingStore.resetSession()
        let next = GreetingStore(botId: "b1", defaults: defaults)
        next.countVisit()
        XCTAssertEqual(next.stored.visits, 2)
        XCTAssertEqual(next.decide(c, signedIn: false)?.text, "Welcome back!")
    }

    func testDismissRecordsTheRuleAndTapOnlyRests() {
        let s = GreetingStore(botId: "b1", defaults: defaults)
        s.countVisit()
        let now = 1_000_000_000_000.0
        let g = try! XCTUnwrap(s.decide(c, signedIn: false, now: now))
        let card = s.show(c, g, agentBot: nil, now: now)
        XCTAssertEqual(card.style, "sticky")
        XCTAssertEqual(card.head.name, "Acme")
        XCTAssertTrue(card.firstShow)
        XCTAssertEqual(s.stored.shows["Hi"], [now])
        XCTAssertEqual(s.stored.last, "Hi")
        XCTAssertFalse(s.show(c, g, agentBot: nil, now: now).firstShow)

        s.closeForNow(now: now + 1000)
        XCTAssertEqual(s.stored.closedAt, now + 1000)
        XCTAssertTrue(s.stored.dismissed.isEmpty)
        XCTAssertNil(s.decide(c, signedIn: false, now: now + 2000))
        XCTAssertNotNil(s.decide(c, signedIn: false, now: now + 1000 + 300_000))

        s.dismiss(now: now + 5000)
        XCTAssertEqual(s.stored.dismissed, ["Hi": now + 5000])
    }

    func testOpeningTheChatSetsChattedAndRestsAShowingCard() {
        let s = GreetingStore(botId: "b1", defaults: defaults)
        s.chatOpened(showing: false, now: 10)
        XCTAssertTrue(s.stored.chatted)
        XCTAssertNil(s.stored.closedAt)
        s.chatOpened(showing: true, now: 20)
        XCTAssertEqual(s.stored.closedAt, 20)
        XCTAssertTrue(GreetingStore(botId: "b1", defaults: defaults).stored.chatted)
    }

    func testSignedInMeansAnIdOrAnEmail() {
        XCTAssertFalse(GreetingStore.signedIn(nil))
        XCTAssertFalse(GreetingStore.signedIn(["name": "Jane"]))
        XCTAssertTrue(GreetingStore.signedIn(["id": "u1"]))
        XCTAssertTrue(GreetingStore.signedIn(["email": "jane@example.com"]))
        XCTAssertFalse(GreetingStore.signedIn(["email": ""]))
    }

    func testReadsWhatRNStoredShapeLooksLike() {
        defaults.set(#"{"visits":3,"chatted":true,"shows":{"sgretn":[1]},"dismissed":{},"closedAt":5,"last":"sgretn"}"#, forKey: "conferbot.greeting.b1")
        let s = GreetingStore(botId: "b1", defaults: defaults)
        XCTAssertEqual(s.stored.visits, 3)
        XCTAssertTrue(s.stored.chatted)
        XCTAssertEqual(s.stored.shows["sgretn"], [1])
        XCTAssertEqual(s.stored.closedAt, 5)
        XCTAssertNil(s.stored.shownAt)
        defaults.set("not json", forKey: "conferbot.greeting.b1")
        XCTAssertEqual(GreetingStore(botId: "b1", defaults: defaults).stored, GreetingStore.Stored())
    }
}
