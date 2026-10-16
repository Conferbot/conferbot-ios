//
//  PersonalizeTests.swift
//  "Greet by name" (Core/Customization/Personalize.swift): the React Native
//  SDK's personalize.test.ts cases (the web widget's tests/ownerLayout.test.js
//  personalize, personalizeCustomizations).
//

import XCTest
@testable import Conferbot

final class PersonalizeTests: XCTestCase {

    func testFillsTokensAndFallsBack() {
        let vars = Personalize.visitorVars(["name": "Sam Lee", "company": "Acme"])
        XCTAssertEqual(vars["first_name"], "Sam")
        XCTAssertEqual(Personalize.personalize("Hi {{first_name|there}} 👋", vars), "Hi Sam 👋")
        XCTAssertEqual(Personalize.personalize("Welcome, {{company}} team", vars), "Welcome, Acme team")
        let anon = Personalize.visitorVars(nil)
        XCTAssertEqual(Personalize.personalize("Hi {{first_name|there}} 👋", anon), "Hi there 👋")
        XCTAssertEqual(Personalize.personalize("Hi {{name}}!", anon), "Hi!")
        XCTAssertEqual(Personalize.personalize("No tokens here", anon), "No tokens here")
    }

    func testKeepsAValueAsTyped() {
        XCTAssertEqual(Personalize.personalize("Hi {{name}}", Personalize.visitorVars(["name": "Ann & Bo"])), "Hi Ann & Bo")
    }

    func testTakesANameTheChatAskedForFirstNameLastNameAndFirstNameToken() {
        XCTAssertEqual(Personalize.visitorVars([:], name: "Priya")["first_name"], "Priya")
        let v = Personalize.visitorVars(["firstName": "Ana", "lastName": "Ruiz"])
        XCTAssertEqual(v["name"], "Ana Ruiz")
        XCTAssertEqual(Personalize.personalize("Hey {{firstName}}", v), "Hey Ana")
        XCTAssertEqual(Personalize.visitorVars(["organization": "Globex"])["company"], "Globex")
    }

    func testTheSignedInUserAsTheSDKSendsIt() {
        let user = ConferBotUser(id: "u1", name: "Jamie Lee", email: "jamie@x.com")
        XCTAssertEqual(Personalize.personalize("Hi {{first_name|there}}", Personalize.visitorVars(user.toVisitorContext())), "Hi Jamie")
    }

    func testTouchesOnlyTheVisitorFacingTexts() {
        let c: [String: Any] = [
            "chatIconCtaText": "Hi {{first_name|there}}",
            "initialPageTitle": "Hello {{name}}",
            "initialPageDescription": "For {{company|you}}",
            "initialPageCardButtonText": "Chat, {{first_name}}",
            "logoText": "{{name}} Bot",
            "greetingRules": [["text": "Pricing for {{company|your team}}"], ["text": "Plain"]],
        ]
        let out = Personalize.customizations(c, Personalize.visitorVars(["firstName": "Ana", "company": "Globex"]))!
        XCTAssertEqual(out["chatIconCtaText"] as? String, "Hi Ana")
        XCTAssertEqual(out["initialPageTitle"] as? String, "Hello Ana")
        XCTAssertEqual(out["initialPageDescription"] as? String, "For Globex")
        XCTAssertEqual(out["initialPageCardButtonText"] as? String, "Chat, Ana")
        XCTAssertEqual(out["logoText"] as? String, "{{name}} Bot")
        let rules = out["greetingRules"] as? [[String: Any]]
        XCTAssertEqual(rules?[0]["text"] as? String, "Pricing for Globex")
        XCTAssertEqual(rules?[1]["text"] as? String, "Plain")
        XCTAssertEqual(c["chatIconCtaText"] as? String, "Hi {{first_name|there}}")
    }

    func testPassesNothingThrough() {
        XCTAssertNil(Personalize.customizations(nil, [:]))
    }
}
