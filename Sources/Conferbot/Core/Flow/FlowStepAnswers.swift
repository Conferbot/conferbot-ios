//
//  FlowStepAnswers.swift
//  Conferbot
//
//  The answers the chat's step views send, in the flow-node spec's shapes
//  (conferbot-react-native scripts/parity/flows/nodes.spec.json): what each
//  step's handleResponse takes. The stock SwiftUI views build their answers
//  here, the tests play the fixtures through these same builders, and a
//  custom UI can use them with ConferBot.answerStep(_:forNodeId:).
//
//  Pure: no UI, so it builds and tests on Linux too.
//

import Foundation

public enum FlowStepAnswer {

    // MARK: Scores and values

    /// A rating (1...n), an opinion scale's number or a slider's value.
    public static func value(_ v: Double) -> [String: Any] { ["value": JS.num(v)] }

    /// A date / time step's pick: "2026-10-19", "14:30" or "2026-10-19T14:30".
    public static func dateTime(_ iso: String) -> [String: Any] { ["value": iso] }

    /// A picked moment as the date / time step's value for its mode
    /// ("date", "time", "datetime"), on the visitor's clock.
    public static func dateTimeValue(_ date: Date, mode: String, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let ymd = "\(String(c.year ?? 1970).padStart(4))-\(String(c.month ?? 1).padStart(2))-\(String(c.day ?? 1).padStart(2))"
        let hm = "\(String(c.hour ?? 0).padStart(2)):\(String(c.minute ?? 0).padStart(2))"
        return mode == "time" ? hm : mode == "datetime" ? "\(ymd)T\(hm)" : ymd
    }

    /// A calendar step's day ("YYYY-MM-DD") and, with time selection, the
    /// slot's start on the bot's clock ("HH:MM").
    public static func calendar(date: String, slot: String? = nil) -> [String: Any] {
        var r: [String: Any] = ["date": date]
        if let s = slot, !s.isEmpty { r["slot"] = s }
        return r
    }

    /// A day as the calendar step names it, on the visitor's clock.
    public static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateTimeValue(date, mode: "date", timeZone: timeZone)
    }

    // MARK: Files

    /// A picked file (a local copy): the step checks it and uploads it.
    public static func file(url: URL, name: String, type: String, size: Int) -> [String: Any] {
        ["file": ["uri": url.absoluteString, "name": name, "type": type, "size": size]]
    }

    /// Skip an optional upload.
    public static var skip: [String: Any] { ["skip": true] }

    // MARK: Several options

    /// The ticked options of an n-check-options step (any order: the step
    /// saves them in its own list order).
    public static func checked(_ ids: [String]) -> [String: Any] { ["buttonIds": ids] }

    /// A ranking's items, best first.
    public static func ranking(_ order: [String]) -> [String: Any] { ["order": order] }

    // MARK: Cards

    /// A card's path button (carousel, product card).
    public static func cardButton(_ buttonId: String, cardId: String? = nil) -> [String: Any] {
        var r: [String: Any] = ["buttonId": buttonId]
        if let c = cardId { r["cardId"] = c }
        return r
    }

    /// Continue under cards that only have link buttons.
    public static var cardsContinue: [String: Any] { ["action": "continue"] }

    // MARK: Matrix

    /// A matrix's picks: row id -> column ids (one each in single mode).
    public static func matrix(_ picks: MatrixPicks) -> [String: Any] {
        var cells: [String: Any] = [:]
        for (row, cols) in picks.selection where !cols.isEmpty { cells[row] = picks.mode == "single" ? cols[0] as Any : cols as Any }
        return ["cells": cells]
    }

    // MARK: Rich steps

    /// The consent box, ticked or not, then Continue.
    public static func consent(agreed: Bool) -> [String: Any] { ["agreed": agreed] }

    public static func otpSend(_ email: String) -> [String: Any] { ["action": "send", "email": email] }
    public static func otpVerify(_ code: String) -> [String: Any] { ["action": "verify", "code": code] }
    public static var otpResend: [String: Any] { ["action": "resend"] }
    public static var otpSkip: [String: Any] { ["action": "skip"] }

    public static func addressSearch(_ q: String) -> [String: Any] { ["action": "search", "q": q] }
    public static func addressPick(_ index: Int) -> [String: Any] { ["action": "pick", "index": index] }
    public static func addressManual(line1: String, city: String = "", region: String = "", postal: String = "", country: String = "") -> [String: Any] {
        func v(_ s: String) -> Any { s.trimmed.isEmpty ? NSNull() : s.trimmed }
        return ["action": "manual", "line1": v(line1), "city": v(city), "region": v(region), "postal": v(postal), "country": v(country)]
    }

    /// A typed signature (and the full name when the step asks for it).
    public static func signTyped(_ name: String, fullName: String? = nil) -> [String: Any] {
        var r: [String: Any] = ["action": "sign", "method": "typed", "name": name]
        if let f = fullName, !f.trimmed.isEmpty { r["fullName"] = f }
        return r
    }

    /// A drawn signature as a PNG.
    public static func signDrawn(png: Data, width: Int, height: Int, fullName: String? = nil) -> [String: Any] {
        var r: [String: Any] = ["action": "sign", "method": "drawn", "image": png, "width": width, "height": height]
        if let f = fullName, !f.trimmed.isEmpty { r["fullName"] = f }
        return r
    }

    /// The payment card's buttons: "open" (Checkout), "check" (I've paid), "cancel".
    public static func payment(_ action: String) -> [String: Any] { ["action": action] }
}

// MARK: - The views' own state

/// A ranking being reordered: the items' ids, best first.
public struct RankingOrder: Equatable {
    public private(set) var ids: [String]

    public init(_ ids: [String]) { self.ids = ids }

    /// Move an item up (-1) or down (+1); at either end nothing moves.
    public mutating func move(_ id: String, by dir: Int) {
        guard let i = ids.firstIndex(of: id) else { return }
        let j = i + dir
        guard j >= 0, j < ids.count else { return }
        ids.swapAt(i, j)
    }
}

/// A matrix being filled in: one column per row (single) or several (multiple).
public struct MatrixPicks: Equatable {
    public let mode: String
    public private(set) var selection: [String: [String]] = [:]

    public init(mode: String) { self.mode = mode == "multiple" ? "multiple" : "single" }

    public func isOn(_ row: String, _ col: String) -> Bool { selection[row]?.contains(col) ?? false }

    /// A tap on a cell: single picks it (in place of the row's other), multiple ticks or unticks it.
    public mutating func tap(_ row: String, _ col: String) {
        selection = FlowRich.matrixToggle(selection, row, col, mode, on: !(mode == "multiple" && isOn(row, col)))
    }

    public var isEmpty: Bool { selection.values.allSatisfy { $0.isEmpty } }
}
