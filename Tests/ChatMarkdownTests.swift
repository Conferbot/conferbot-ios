//
//  ChatMarkdownTests.swift
//  What the web's agentHtml.ts draws, as the React Native SDK's
//  chatMarkdown.test.ts (#49): tables, h3-h6 (# and ## as 4), and from a
//  person's HTML blockquote, pre and strikethrough.
//

import XCTest
@testable import Conferbot

final class ChatMarkdownTests: XCTestCase {

    private func kinds(_ blocks: [ChatMarkdown.Block]) -> [String] {
        blocks.map {
            switch $0 {
            case .paragraph: return "paragraph"
            case .bullet: return "bullet"
            case .numbered: return "number"
            case .heading: return "heading"
            case .quote: return "quote"
            case .pre: return "pre"
            case .table: return "table"
            }
        }
    }

    func testListsHeadingsAndParagraphs() {
        let blocks = ChatMarkdown.parse("## Plans\nWe have:\n- Pro\n+ Plus\n2. Team\n\nBye")
        XCTAssertEqual(kinds(blocks), ["heading", "paragraph", "bullet", "bullet", "number", "paragraph"])
        XCTAssertEqual(ChatMarkdown.plainText(blocks), "Plans\nWe have:\n• Pro\n• Plus\n2. Team\nBye")
    }

    func testHashAndDoubleHashAreLevelFourThreeToSixKeepTheirs() {
        let levels = ChatMarkdown.parse("# A\n## B\n### C\n#### D\n##### E\n###### F").compactMap { block -> Int? in
            if case .heading(let level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(levels, [4, 4, 3, 4, 5, 6])
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<h2>Plans</h2><h3>Pro</h3><h6>small</h6>"), "#### Plans\n\n### Pro\n\n###### small")
        XCTAssertEqual(kinds(ChatMarkdown.parse("#hashtag")), ["paragraph"])
    }

    func testTablesAsTheWebDrawsMarkdownTables() {
        guard case .table(let head, let rows)? = ChatMarkdown.parse("| Plan | Price |\n|---|:---:|\n| **Pro** | $49 |\n| Team |").first else {
            return XCTFail("not a table")
        }
        XCTAssertEqual(head, [[.plain("Plan")], [.plain("Price")]])
        XCTAssertEqual(rows, [
            [[.bold("Pro")], [.plain("$49")]],
            // A short row is filled to the head's width.
            [[.plain("Team")], []],
        ])
        // A row without its rule is not a table.
        XCTAssertEqual(kinds(ChatMarkdown.parse("| a | b |\n| c | d |")), ["paragraph"])
    }

    func testAPersonsHTMLTableKeepsItsCellsPipes() {
        let md = ChatMarkdown.htmlToMarkdown("<table><thead><tr><th>Plan</th><th>Note</th></tr></thead><tbody><tr><td><b>Pro</b></td><td>a | b</td></tr></tbody></table>")
        XCTAssertEqual(md, "| Plan | Note |\n| --- | --- |\n| **Pro** | a \\| b |")
        guard case .table(_, let rows)? = ChatMarkdown.parse(md).first else { return XCTFail("not a table") }
        XCTAssertEqual(rows[0][1], [.plain("a | b")])
        XCTAssertEqual(ChatMarkdown.tableCells("| a \\| b | c |"), ["a | b", "c"])
    }

    func testBlockquotePreAndStrikethroughFromAPersonsHTML() {
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<blockquote><p>Quoted</p><p>twice</p></blockquote><p>After</p>"), "> Quoted\n> twice\n\nAfter")
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<pre>npm i\n  **x**</pre>"), "```\nnpm i\n  **x**\n```")
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<p><s>$59</s> <del>old</del> $49</p>"), "~~$59~~ ~~old~~ $49")
        let blocks = ChatMarkdown.parse("> Quoted\n> twice\n\n```\nnpm i\n  **x**\n```\nok ~~no~~")
        XCTAssertEqual(kinds(blocks), ["quote", "pre", "paragraph"])
        XCTAssertEqual(blocks[0], .quote([.plain("Quoted\ntwice")]))
        XCTAssertEqual(blocks[1], .pre("npm i\n  **x**"))
        XCTAssertEqual(blocks[2], .paragraph([.plain("ok "), .strike("no")]))
        XCTAssertEqual(ChatMarkdown.plainText(blocks), "Quoted\ntwice\nnpm i\n  **x**\nok no")
    }

    func testTheOldSubsetStillReadsTheSame() {
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<p>Hi <strong>Sam</strong></p><p>See <a href=\"https://a.co/x\">this</a> &amp; that</p>"),
                       "Hi **Sam**\n\nSee [this](https://a.co/x) & that")
        XCTAssertEqual(ChatMarkdown.htmlToMarkdown("<a href=\"javascript:alert(1)\">click</a>"), "click")
        XCTAssertEqual(ChatMarkdown.parseInline("a **b** _c_ `d` [e](https://e.co)"), [
            .plain("a "), .bold("b"), .plain(" "), .italic("c"), .plain(" "), .code("d"), .plain(" "), .link(text: "e", url: "https://e.co"),
        ])
    }
}
