import XCTest
@testable import Conferbot

extension I18nSweepTests {

    /// The chat screens' own words (ChatText): German, no English left.
    func testTheChatScreensWordsInGerman() {
        let words: [(String, String)] = [
            ("chatTab", ChatText.chatTab), ("help", ChatText.help), ("locked", ChatText.locked),
            ("connectionLost", ChatText.connectionLost("Ada")), ("placeholder", ChatText.placeholder),
            ("repliesOff", ChatText.repliesOff), ("connecting", ChatText.connecting), ("online", ChatText.online),
            ("menu", ChatText.menu), ("supportChat", ChatText.supportChat), ("done", ChatText.done),
            ("ok", ChatText.ok), ("send", ChatText.send), ("attach", ChatText.attach), ("poweredBy", ChatText.poweredBy),
            ("browseHelp", ChatText.browseHelp), ("deleted", ChatText.deleted), ("editedAt", ChatText.editedAt("14:05")),
            ("file", ChatText.file("a.pdf")), ("audio", ChatText.audio), ("bot", ChatText.bot),
            ("openLauncher", ChatText.openLauncher), ("closeLauncher", ChatText.closeLauncher), ("openTheChat", ChatText.openTheChat),
        ]
        for (name, text) in words { assertNoEnglish(text, name) }
        XCTAssertEqual(ChatText.locked, de("system.locked"))
        XCTAssertEqual(ChatText.connectionLost("Ada"), de("agent.connectionLost", ["name": "Ada"]))
        XCTAssertEqual(ChatText.placeholder, de("chat.composer.placeholder"))
        XCTAssertEqual(ChatText.online, de("status.online"))
        // The chat's own cards' words (LiveChatCards).
        for key in ["sdk.form.invalidEmail", "leave.writeMessage", "sdk.form.notThrough", "chat.talkToPerson",
                    "sdk.queue.leaveHint", "leave.title", "leave.sub", "leave.messagePlaceholder", "leave.sentSub",
                    "lead.title", "lead.sub", "sdk.file.choose", "common.notNow", "sdk.card.learnMore",
                    "sdk.action.confirmed", "sdk.action.notThroughAsk", "sdk.kb.readArticle", "kb.helpArticle"] {
            assertNoEnglish(I18n.t(key), key)
        }
        assertNoEnglish(I18n.t("leave.sent", ["email": "a@b.co"]), "leave.sent")
        assertNoEnglish(I18n.t("file.requested", ["name": "Ada"]), "file.requested")
        assertNoEnglish(I18n.t("lead.done", ["email": "a@b.co"]), "lead.done")
    }

    /// Message times in the widget's language and region (24-hour in German).
    func testMessageTimesInTheWidgetsLocale() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "de")
        f.timeStyle = .short
        XCTAssertEqual(ChatText.time(date), f.string(from: date))
        I18n.setWidgetLanguage("en", languages: ["en-US"])
        XCTAssertTrue(ChatText.time(date).contains("M"), ChatText.time(date))
    }
}
