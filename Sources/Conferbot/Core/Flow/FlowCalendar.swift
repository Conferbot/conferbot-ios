//
//  FlowCalendar.swift
//  Conferbot
//
//  Calendar step rules, ported from the web widget
//  (conferbot-widget/src/ts/chat/nodeLogic.ts: expandSlots, futureSlots,
//  dayKeyInZone, noonInZone; displayStep.ts calendar-node) through the React
//  Native SDK (src/core/flow/calendar.ts). Slot times are the bot's clock
//  (data.timeZone); the visitor sees their own.
//

import Foundation

public enum FlowCalendar {

    public struct Slot: Equatable {
        public let start: String
        public let end: String
    }

    private static func toMinutes(_ hhmm: Any?) -> Int? {
        guard let m = Re("^([0-9]{1,2}):([0-9]{2})$").match(JS.text(hhmm)), let h = Int(m[1] ?? ""), let mi = Int(m[2] ?? "") else { return nil }
        return h * 60 + mi
    }

    private static func toHhmm(_ minutes: Int) -> String {
        "\(String(minutes / 60).padStart(2)):\(String(minutes % 60).padStart(2))"
    }

    /// A day's windows cut into slotDuration-minute slots with bufferMinutes between.
    public static func expandSlots(_ windows: Any?, _ slotDuration: Any?, _ bufferMinutes: Any?) -> [Slot] {
        let list = JS.dicts(windows)
        let lengthN = JS.toNumber(slotDuration)
        let length = lengthN.isFinite ? Int(lengthN.rounded(.down)) : 0
        let bufferN = JS.toNumber(bufferMinutes)
        let buffer = max(0, bufferN.isFinite ? Int(bufferN.rounded(.down)) : 0)
        if length <= 0 {
            return list.filter { JS.truthy($0["start"]) && JS.truthy($0["end"]) }.map { Slot(start: JS.str($0["start"]), end: JS.str($0["end"])) }
        }
        var out: [Slot] = []
        for w in list {
            guard let from = toMinutes(w["start"]), let to = toMinutes(w["end"]), to > from else { continue }
            var t = from
            while t + length <= to {
                out.append(Slot(start: toHhmm(t), end: toHhmm(t + length)))
                t += length + buffer
            }
        }
        return out
    }

    public static func slotLabel(_ slot: Slot) -> String { "\(slot.start) - \(slot.end)" }

    /// The slots already taken on a day, as "HH:MM - HH:MM" on the bot's
    /// clock (web displayStep.ts daySlotsFor `booked`; RN flow/calendar.ts
    /// bookedLabels): the bot's bookings (the bot data's calendarBookings,
    /// populated by the server) plus any the node carries itself
    /// (data.bookings), for this node only (a booking with no nodeId counts
    /// for every calendar), on this day in the bot's zone.
    public static func bookedLabels(_ calendarBookings: Any?, nodeId: String?, nodeData: [String: Any]?, dayKey: String, timeZone: String) -> [String] {
        let own = JS.dicts(nodeData?["bookings"]).filter { JS.truthy($0["date"]) }
        return (JS.dicts(calendarBookings) + own)
            .filter { b in JS.text(b["nodeId"]).isEmpty || JS.text(b["nodeId"]) == (nodeId ?? "") }
            .filter { b in
                guard let d = bookingDate(b["date"]) else { return false }
                return dayKeyInZone(d, timeZone) == dayKey
            }
            .map { JS.text($0["timeSlotSelected"]).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func bookingDate(_ v: Any?) -> Date? {
        if let d = v as? Date { return d }
        if let s = v as? String { return Flow.parseISO(s) }
        if let n = v as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000) }
        return nil
    }

    /// Every slot of the day taken (web nodeLogic.ts isDayFullyBooked): the day is not offered.
    public static func isDayFullyBooked(_ slots: [Slot], _ booked: [String]) -> Bool {
        guard !slots.isEmpty else { return false }
        let taken = Set(booked.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return slots.allSatisfy { taken.contains(slotLabel($0)) }
    }

    static func zone(_ id: String) -> TimeZone { TimeZone(identifier: id) ?? TimeZone(identifier: "UTC")! }

    static func calendar(_ id: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone(id)
        return cal
    }

    /// "YYYY-MM-DD" of an instant on a zone's clock.
    public static func dayKeyInZone(_ date: Date, _ timeZone: String) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return "\(String(c.year!).padStart(4))-\(String(c.month!).padStart(2))-\(String(c.day!).padStart(2))"
    }

    /// Today's slots that have not started yet (bot's clock); other days keep all.
    public static func futureSlots(_ slots: [Slot], _ dayKey: String, _ timeZone: String, now: Date) -> [Slot] {
        if dayKey != dayKeyInZone(now, timeZone) { return slots }
        let c = calendar(timeZone).dateComponents([.hour, .minute], from: now)
        let nowMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return slots.filter { (toMinutes($0.start) ?? 0) > nowMin }
    }

    /// The instant it is hh:mm on `dateString` on `timeZone`'s clock.
    public static func wallTimeInZone(_ dateString: String, _ hhmm: String, _ timeZone: String) -> Date {
        let p = dateString.split(separator: "-").map { Int($0) ?? 1 }
        let mins = toMinutes(hhmm) ?? 12 * 60
        let comps = DateComponents(year: p.count > 0 ? p[0] : 1970, month: p.count > 1 ? p[1] : 1, day: p.count > 2 ? p[2] : 1, hour: mins / 60, minute: mins % 60)
        return calendar(timeZone).date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// 12:00 on that day on that zone's clock.
    public static func noonInZone(_ dateString: String, _ timeZone: String) -> Date { wallTimeInZone(dateString, "12:00", timeZone) }

    /// "HH:MM" of an instant on a zone's clock.
    public static func hhmmInZone(_ date: Date, _ timeZone: String) -> String {
        let c = calendar(timeZone).dateComponents([.hour, .minute], from: date)
        return "\(String(c.hour ?? 0).padStart(2)):\(String(c.minute ?? 0).padStart(2))"
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// "Tuesday, October 20, 2026" (en-US), or the date in another locale
    /// ("Dienstag, 20. Oktober 2026").
    public static func longDate(_ date: Date, _ timeZone: String, _ locale: String = "en-US") -> String {
        if locale != "en-US" {
            let f = DateFormatter()
            f.locale = Locale(identifier: locale)
            f.timeZone = zone(timeZone)
            f.setLocalizedDateFormatFromTemplate("EEEEyMMMMd")
            return f.string(from: date)
        }
        let c = calendar(timeZone).dateComponents([.year, .month, .day, .weekday], from: date)
        return "\(FlowLogic.dayNames[(c.weekday ?? 1) - 1]), \(monthNames[(c.month ?? 1) - 1]) \(c.day ?? 1), \(c.year ?? 1970)"
    }

    /// The locale a visitor's own date is written in: the widget's (web
    /// displayStep.ts formattedVisitorDate uses widgetLocale()), "en-US" for
    /// English. The bot's date stays en-US, as the web keeps it.
    public static func visitorLocale() -> String { I18n.isEnglish ? "en-US" : I18n.localeTag }

    /// The weekday name of a day on the bot's clock. The owner's day names
    /// (weeklyHours.dayName, excludeDays) are English: kept so here.
    public static func dayNameInZone(_ date: Date, _ timeZone: String) -> String {
        FlowLogic.dayNames[(calendar(timeZone).component(.weekday, from: date)) - 1]
    }

    /// The visitor's own time zone.
    public static func visitorTimeZone() -> String { TimeZone.current.identifier }
}
