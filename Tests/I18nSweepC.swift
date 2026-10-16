//
//  I18nSweepC.swift
//  ConferbotTests
//
//  The flow steps in German (React Native's __tests__/core/i18nCore.test.ts
//  step checks and the fixture part of __tests__/components/i18nSweep.test.tsx):
//  the step checks' texts, then every flow fixture played through the
//  engine under "de", with the fixture's own (English) owner text taken out
//  before the check.
//

import XCTest
@testable import Conferbot

extension I18nSweepTests {

    // MARK: - The step checks

    func testTheStepChecksInGerman() {
        XCTAssertEqual(FlowInputs.EN.emailInvalid, de("validation.email"))
        XCTAssertEqual(FlowInputs.numberProblem("abc", [:]), de("validation.numberLike"))
        XCTAssertEqual(FlowInputs.numberProblem("1", ["enableConditions": ["minVal": 5]]), de("validation.numberMin", ["min": 5]))
        XCTAssertEqual(FlowInputs.numberProblem("9", ["enableConditions": ["minVal": 1, "maxVal": 5]]), de("validation.numberBetween", ["min": 1, "max": 5]))
        XCTAssertEqual(FlowInputs.fileTypesWords(["image/", "pdf"]), "\(de("file.images")) \(de("common.or")) PDF")
        XCTAssertEqual(FlowInputs.fileUploadProblem(["size": 9 * 1024 * 1024], [:]), de("upload.overSize", ["mb": 5]))
        // An owner text that is the stock English shows in German; the owner's own words as written.
        XCTAssertEqual(FlowInputs.ownerTextOr("Please enter a valid email address", FlowInputs.EN.emailInvalid), de("validation.email"))
        XCTAssertEqual(FlowInputs.ownerTextOr("Please enter a valid email", FlowInputs.EN.emailInvalid, ["Please enter a valid email"]), de("validation.email"))
        XCTAssertEqual(FlowInputs.ownerTextOr("Bitte prüfen", FlowInputs.EN.emailInvalid), "Bitte prüfen")
        XCTAssertEqual(FlowInputs.phoneErrorText([:]), de("validation.phone"))
        XCTAssertEqual(FlowI18n.t("otp.resend"), de("otp.resend"))
        XCTAssertEqual(InputValidation.email.errorMessage, de("validation.email"))
        XCTAssertEqual(Rating.words("smiley", 5), (1...5).map { de("rating.face.\($0)") })
        XCTAssertEqual(Rating.words(nil, 3), [de("rating.bad"), de("rating.okay"), de("rating.great")])
        XCTAssertEqual(Rating.words(nil, 10)[0], de("rating.outOf", ["n": 1, "max": 10]))
        XCTAssertEqual(FlowRich.weekdaysName(6), "Samstag")
        XCTAssertEqual(FlowCalendar.longDate(Date(timeIntervalSince1970: 1_792_058_400), "UTC", FlowCalendar.visitorLocale()), "Donnerstag, 15. Oktober 2026")
        for text in [FlowInputs.EN.done, FlowInputs.EN.skipped, FlowInputs.EN.uploadRetry, FlowInputs.EN.link, FlowInputs.EN.emailTypo("a@b.co")] {
            assertNoEnglish(text, "step check")
        }
    }

    // MARK: - Every flow fixture under "de"

    /// Every string in the fixture (the owner's flow, the server's answers,
    /// the visitor's input), and the text inside its HTML and markdown.
    private static func ownerOf(_ fx: [String: Any]) -> [String] {
        var out: [String] = []
        func walk(_ v: Any?) {
            if let s = v as? String {
                out.append(s)
                let text = s.replacingOccurrences(of: "<[^>]*>", with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "**", with: "\n")
                out += text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                out.append(FlowText.plainText(s))
            } else if let a = v as? [Any] {
                a.forEach(walk)
            } else if let d = v as? [String: Any] {
                d.values.forEach(walk)
            }
        }
        walk([fx["flow"] ?? NSNull(), fx["server"] ?? NSNull(), fx["inputs"] ?? NSNull(), fx["customizations"] ?? NSNull()])
        return Array(Set(out.filter { $0.count >= 2 })).sorted { $0.count > $1.count }
    }

    /// What in `strings` is English, with the owner's own strings taken out first.
    private func englishIn(_ strings: [String], owner: [String]) -> [String] {
        // An owner text with {placeholders} ("Not verified ({var})") as it is drawn filled in.
        let templates: [NSRegularExpression] = owner.filter { $0.range(of: "\\{\\w+\\}", options: .regularExpression) != nil }.compactMap { o in
            let marked = o.replacingOccurrences(of: "\\{\\w+\\}", with: "\u{1}", options: .regularExpression)
            let pattern = marked.components(separatedBy: "\u{1}").map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: ".+?")
            return try? NSRegularExpression(pattern: pattern)
        }
        var bad: [String] = []
        for raw in strings {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 || owner.contains(where: { $0.contains(trimmed) }) { continue }
            // The web's own record words a step says for the visitor:
            // a carousel's "Continue" (nodeKit.ts CAROUSEL_CONTINUE, English there too).
            if trimmed == Carousel.continueLabel { continue }
            var s = raw
            for o in owner { s = s.replacingOccurrences(of: o, with: " ") }
            for re in templates { s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ") }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if Self.englishWords.contains(s) { bad.append("\"\(raw)\""); continue }
            if let hit = Self.englishOnly.first(where: { s.contains($0) }) { bad.append("\"\(raw)\" (\(hit))") }
        }
        return bad
    }

    /// What a waiting step draws from its state: the placeholder, the labels.
    private static func stringsOf(_ ui: NodeUIState?) -> [String] {
        switch ui {
        case .textInput(let placeholder, let validation, _)?: return [placeholder ?? "", validation?.errorMessage ?? ""]
        case .buttons(let buttons, _)?: return buttons.map { $0.label }
        case .singleChoice(let options, _)?, .multiChoice(let options, _)?, .quickReplies(let options, _)?: return options.map { $0.label }
        case .cards(let cards, _)?: return cards.flatMap { $0.buttons.map { $0.label } }
        case .opinionScale(_, _, let a, let b, _)?: return [a ?? "", b ?? ""]
        case .message(let text, _)?: return [text]
        case .humanHandover(let m)?, .liveChat(let m)?: return [m ?? ""]
        default: return []
        }
    }

    @MainActor
    func testEveryFlowFixtureUnderGermanDrawsNoEnglishOfItsOwn() async {
        I18n.setWidgetLanguage("de", languages: [])
        var bad: [String] = []
        for c in FlowFixtureTests.cases {
            let fx = FlowFixtureTests.load(JS.text(c["file"]))
            let id = JS.text(fx["id"])
            let owner = Self.ownerOf(fx)
            var drawn: [String] = []
            let result = await FlowFixtureDriver.run(fx) { _, ui, _, _ in
                drawn += Self.stringsOf(ui)
                return (false, nil)
            }
            for r in JS.dicts(result.outcome["rendered"]) { drawn.append(JS.text(r["plain"])) }
            for t in JS.dicts(result.outcome["transcript"]) { drawn.append(JS.text(t["message"])) }
            bad += englishIn(drawn, owner: owner).map { "\(id): \($0)" }
        }
        XCTAssertEqual(Array(Set(bad)).sorted(), [])
    }

    // MARK: - Every key the sources use is in the table

    /// I18n.t("key") / tPlural("base") / FlowI18n.t("key") in the SDK's
    /// sources: each key (each plural's .one and .other) is in the English table.
    func testEveryKeyTheSourcesUseIsInTheTable() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Conferbot")
        guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("the sources are not beside the tests")
        }
        let re = try NSRegularExpression(pattern: "(?:I18n|FlowI18n)\\.(t|tPlural|ownerTextOr\\([^,()]*,|stockText\\([^,()]*,)\\(?\\s*\"([A-Za-z0-9_.]+)\"")
        var missing: [String] = []
        var seen = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let fr = Range(m.range(at: 1), in: text), let kr = Range(m.range(at: 2), in: text) else { continue }
                let key = String(text[kr])
                seen += 1
                let keys = text[fr] == "tPlural" ? ["\(key).one", "\(key).other"] : [key]
                for k in keys where I18n.english[k] == nil { missing.append("\(url.lastPathComponent): \(k)") }
            }
        }
        XCTAssertGreaterThan(seen, 50)
        XCTAssertEqual(Array(Set(missing)).sorted(), [], "keys not in Resources/i18n-strings.json")
    }
}
