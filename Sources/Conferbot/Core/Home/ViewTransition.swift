//
//  ViewTransition.swift
//  Conferbot
//
//  How the open chat moves between its views - the home screen, the
//  conversation and the help centre - from the owner's setting
//  (customizations.viewTransition, viewTransitionDirection). Ported from the
//  React Native SDK (src/core/viewTransition.ts), itself from the web widget:
//  conferbot-widget src/ts/layout/viewTransition.ts (VIEW_TRANSITIONS,
//  normalizeViewTransition, VIEW_DIRECTIONS, normalizeViewDirection,
//  sweepVector, directionBetween and the "reduced", "fade" and "slide" tracks
//  of playViewTransition).
//
//  The web lays a still copy of the old view (a "ghost") over the panel and
//  animates it away while the new view comes in. A native view has no ghost
//  to copy, so the app plays the new view's half only:
//
//    classic, none   the view switches at once;
//    fade            the new view fades up from 103.5% over 340ms, 40ms in;
//    slide           it slides in from the sweep's side over 420ms;
//    anything else   (honeycomb - the default -, iris, ripple, cards, ...):
//                    the slide, the calm move closest to the web's sweeps;
//    reduced motion  a 200ms fade, whatever the owner picked (as the web).
//
//  Pure.
//

import Foundation

public enum ViewTransition {

    public static let kinds = [
        "classic", "none", "slide", "fade", "iris", "ripple", "honeycomb", "cards", "blinds",
        "pixels", "flip", "mosaic", "diamonds", "bubbles", "stripes", "wave", "curtain", "shutter",
    ]

    /// Unset: the sliding honeycomb ("classic" stays the widget as it always was).
    public static let defaultKind = "honeycomb"

    public static func normalize(_ value: Any?) -> String {
        if let s = value as? String, kinds.contains(s) { return s }
        return defaultKind
    }

    /// Which way a transition sweeps. "auto" goes sideways by where the views
    /// sit (deeper is to the right); the others are fixed, and coming back
    /// plays them in reverse. "tap" has no tap point here and goes as "auto".
    public static let directions = ["auto", "ltr", "rtl", "ttb", "btt", "tap"]

    public static func normalizeDirection(_ value: Any?) -> String {
        if let s = value as? String, directions.contains(s) { return s }
        return "auto"
    }

    /// The sweep as a unit vector for a move forward (+1) or back (-1).
    public static func sweepVector(_ sweep: Any?, _ dir: Double) -> (x: Double, y: Double) {
        let base: (Double, Double)
        switch normalizeDirection(sweep) {
        case "rtl": base = (-1, 0)
        case "ttb": base = (0, 1)
        case "btt": base = (0, -1)
        default: base = (1, 0)
        }
        // + 0 turns -0 into 0, as JS's `|| 0`.
        return (base.0 * dir + 0, base.1 * dir + 0)
    }

    public enum Direction: Equatable { case forward, back }

    /// Where the views sit, left to right (the web's VIEW_ORDER).
    private static let order: [String: Int] = ["home": 0, "initial_page": 0, "chat": 1, "kb": 2, "help": 2, "articles": 2, "list": 3, "article": 4]

    public static func directionBetween(_ from: String, _ to: String) -> Direction {
        (order[to] ?? 1) >= (order[from] ?? 1) ? .forward : .back
    }

    public enum Motion: Equatable {
        case none
        /// The new view's opacity 0 -> 1, linear.
        case reduced(duration: Double)
        /// Opacity 0 -> 1 and scale `scaleFrom` -> 1, after `delay` (ms).
        case fade(duration: Double, delay: Double, scaleFrom: Double)
        /// In from (dx, dy) times the view's size to its place.
        case slide(duration: Double, dx: Double, dy: Double)
    }

    /// The web's easings (EASE, EASE_IO) as cubic-bezier points.
    public static let ease: [Double] = [0.22, 0.8, 0.24, 1]
    public static let easeInOut: [Double] = [0.6, 0, 0.25, 1]

    /// How the new view comes in when the chat moves from one view to another.
    public static func motion(_ kind: Any?, _ sweep: Any?, from: String, to: String, reduced: Bool = false) -> Motion {
        if from == to { return .none }
        let k = normalize(kind)
        if k == "classic" || k == "none" { return .none }
        if reduced { return .reduced(duration: 200) }
        if k == "fade" { return .fade(duration: 340, delay: 40, scaleFrom: 1.035) }
        let v = sweepVector(sweep, directionBetween(from, to) == .back ? -1 : 1)
        return .slide(duration: 420, dx: v.x, dy: v.y)
    }
}
