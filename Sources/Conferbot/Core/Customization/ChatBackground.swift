//
//  ChatBackground.swift
//  Conferbot
//
//  The chat background as the web widget draws it (conferbot-widget
//  ts/chatBackground/chatBackground.ts): solid, gradient (linear, radial,
//  mesh, blur), image with an optional mask, or one of 13 pattern tiles.
//  Pure: UI/SwiftUI/ChatBackgroundView.swift draws it.
//

import Foundation

public enum ChatBackground: Equatable {
    case solid(color: String)
    case gradient(color: String, stops: [String], angle: Int, style: String)
    case image(color: String, url: String, maskColor: String?, maskAlpha: Double)
    case pattern(color: String, pattern: String, ink: String, alpha: Double)
}

/// One shape of a tile: a path, circle or rect, filled or stroked, maybe rotated about a point.
public struct PatternShape {
    public var t: String
    public var fill: Bool
    public var sw: Double = 1.2
    public var d: String? = nil
    public var cx: Double = 0, cy: Double = 0, r: Double = 0
    public var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0, rx: Double = 0
    public var rot: [Double]? = nil
}

public struct PatternTile {
    public var w: Double
    public var h: Double
    public var noise: Bool = false
    public var shapes: [PatternShape]
}

public enum ChatBackgrounds {
    public static let gradientStyles = ["linear", "radial", "mesh", "blur"]

    /// The web's tiles (generated from chatBackground.ts PATTERNS).
    public static let patterns: [String: PatternTile] = [
        "dots": PatternTile(w: 18.0, h: 18.0, noise: false, shapes: [
            PatternShape(t: "circle", fill: true, cx: 9.0, cy: 9.0, r: 1.6)
        ]),
        "grid": PatternTile(w: 24.0, h: 24.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M24 .5H.5V24")
        ]),
        "diagonal": PatternTile(w: 14.0, h: 14.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M-3.5 3.5l7-7M0 14L14 0M10.5 17.5l7-7")
        ]),
        "waves": PatternTile(w: 40.0, h: 16.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.2, d: "M0 8q5-6 10 0t10 0 10 0 10 0")
        ]),
        "topography": PatternTile(w: 220.0, h: 220.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M60 40c30-18 72-10 84 18s-8 58-40 64-70-6-74-36 6-32 30-46z"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M70 58c20-10 48-4 56 14s-6 38-28 40-46-4-48-24 4-20 20-30z"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M84 74c10-4 24 0 26 8s-4 16-14 16-20-2-20-10 2-10 8-14z"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M150 150c26-6 58 6 62 30s-22 40-52 38-50-14-48-36 12-26 38-32z"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M158 166c16-2 34 4 36 18s-14 24-30 22-30-8-28-20 8-18 22-20z"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M-10 170c20-14 50-10 58 8s-8 40-32 44"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M210 30c-6 20-2 44 16 52"),
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M0 110c30 6 44 30 36 60M220 110c-30-4-50 10-56 34")
        ]),
        "confetti": PatternTile(w: 90.0, h: 90.0, noise: false, shapes: [
            PatternShape(t: "rect", fill: true, x: 10.0, y: 12.0, w: 7.0, h: 3.0, rx: 1.5, rot: [30.0, 13.0, 13.0]),
            PatternShape(t: "rect", fill: true, x: 58.0, y: 8.0, w: 7.0, h: 3.0, rx: 1.5, rot: [-40.0, 61.0, 9.0]),
            PatternShape(t: "rect", fill: true, x: 40.0, y: 52.0, w: 7.0, h: 3.0, rx: 1.5, rot: [70.0, 43.0, 53.0]),
            PatternShape(t: "rect", fill: true, x: 72.0, y: 66.0, w: 7.0, h: 3.0, rx: 1.5, rot: [10.0, 75.0, 67.0]),
            PatternShape(t: "circle", fill: true, cx: 34.0, cy: 26.0, r: 2.2),
            PatternShape(t: "circle", fill: true, cx: 80.0, cy: 34.0, r: 1.6),
            PatternShape(t: "circle", fill: true, cx: 16.0, cy: 70.0, r: 2.0),
            PatternShape(t: "circle", fill: true, cx: 56.0, cy: 82.0, r: 1.4),
            PatternShape(t: "path", fill: true, d: "M24 44l3 5h-6z"),
            PatternShape(t: "path", fill: true, d: "M68 44l3 5h-6z", rot: [40.0, 68.0, 46.0])
        ]),
        "doodles": PatternTile(w: 128.0, h: 128.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M14 14h26a5 5 0 0 1 5 5v12a5 5 0 0 1-5 5H26l-7 6v-6h-5a5 5 0 0 1-5-5V19a5 5 0 0 1 5-5z"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M19 23h16M19 28h10"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M92 26c-3-5-11-4-11 3 0 6 11 12 11 12s11-6 11-12c0-7-8-8-11-3z"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M30 78l3 7 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z"),
            PatternShape(t: "circle", fill: false, sw: 1.4, cx: 96.0, cy: 92.0, r: 11.0),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M91 95q5 5 10 0"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M92 88v1M100 88v1"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M58 60l20-8-6 20-5-7zM67 65l11-13"),
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M60 110h.01M112 60h.01M8 58h.01M70 12h.01")
        ]),
        "paper": PatternTile(w: 180.0, h: 180.0, noise: true, shapes: [
            
        ]),
        "hexagons": PatternTile(w: 24.0, h: 42.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.0, d: "M12 0l12 7v14l-12 7-12-7V7zM12 28v14")
        ]),
        "rings": PatternTile(w: 36.0, h: 36.0, noise: false, shapes: [
            PatternShape(t: "circle", fill: false, sw: 1.1, cx: 18.0, cy: 18.0, r: 9.0)
        ]),
        "plus": PatternTile(w: 26.0, h: 26.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.4, d: "M13 9v8M9 13h8")
        ]),
        "zigzag": PatternTile(w: 24.0, h: 14.0, noise: false, shapes: [
            PatternShape(t: "path", fill: false, sw: 1.2, d: "M0 10l6-6 6 6 6-6 6 6")
        ]),
        "sparkles": PatternTile(w: 72.0, h: 72.0, noise: false, shapes: [
            PatternShape(t: "path", fill: true, d: "M18 8c1 6 3 8 9 9-6 1-8 3-9 9-1-6-3-8-9-9 6-1 8-3 9-9z"),
            PatternShape(t: "path", fill: true, d: "M54 42c.7 4 2 5.3 6 6-4 .7-5.3 2-6 6-.7-4-2-5.3-6-6 4-.7 5.3-2 6-6z"),
            PatternShape(t: "circle", fill: true, cx: 52.0, cy: 14.0, r: 1.4),
            PatternShape(t: "circle", fill: true, cx: 16.0, cy: 56.0, r: 1.6)
        ]),
    ]

    private static let colorPattern = #"^(#[0-9a-fA-F]{3,8}|rgba?\([\d\s.,%/]+\)|hsla?\([\d\s.,%/a-zA-Z]+\)|[a-zA-Z]{3,20})$"#

    /// A colour we can use, else the fallback (as the web's safeColor).
    public static func safeColor(_ value: Any?, _ fallback: String) -> String {
        let v = ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, v.range(of: colorPattern, options: .regularExpression) != nil,
              v.range(of: "url|expression", options: [.regularExpression, .caseInsensitive]) == nil else { return fallback }
        return v
    }

    private static func clamp(_ value: Any?, _ lo: Double, _ hi: Double, _ fallback: Double) -> Double {
        let n: Double?
        if let d = value as? Double { n = d } else if let i = value as? Int { n = Double(i) } else if let s = value as? String { n = Double(s.trimmingCharacters(in: .whitespaces)) } else { n = nil }
        guard let v = n, v.isFinite else { return fallback }
        return min(hi, max(lo, v))
    }

    /// The gradient's colours: the saved stops (2-4), else the legacy two.
    public static func gradientStops(_ c: [String: Any]) -> [String] {
        let stops = ((c["chatBgGradientStops"] as? [Any]) ?? []).map { safeColor($0, "") }.filter { !$0.isEmpty }.prefix(4)
        return stops.count >= 2 ? Array(stops) : [safeColor(c["gradientBgOne"], "#fffcf1"), safeColor(c["gradientBgTwo"], "#1b55f3")]
    }

    public static func resolve(_ raw: [String: Any]?) -> ChatBackground {
        let c = raw ?? [:]
        let type = ((c["chatBgType"] as? String) ?? "solid").lowercased()
        let color = safeColor(c["chatBgColor"], "#ffffff")
        switch type {
        case "gradient":
            let style = (c["chatBgGradientStyle"] as? String).flatMap { gradientStyles.contains($0) ? $0 : nil } ?? "linear"
            return .gradient(color: color, stops: gradientStops(c), angle: Int(clamp(c["chatBgGradientAngle"], 0, 360, 180).rounded()), style: style)
        case "pattern":
            let id = (c["chatBgPattern"] as? String).flatMap { patterns[$0] != nil ? $0 : nil } ?? "dots"
            return .pattern(color: color, pattern: id, ink: safeColor(c["chatBgPatternColor"], "#0f172a"), alpha: clamp(c["chatBgPatternOpacity"], 0, 100, 12) / 100)
        case "image":
            let url = (((c["chatBgImage"] ?? c["chatBgImg"]) as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if url.isEmpty || url.lowercased().hasPrefix("javascript:") { return .solid(color: color) }
            let alpha = clamp(c["chatBgMaskOpacity"], 0, 90, 0) / 100
            return .image(color: color, url: url, maskColor: alpha > 0 ? safeColor(c["chatBgMaskColor"], "#000000") : nil, maskAlpha: alpha)
        default:
            return .solid(color: color)
        }
    }

    /// A point on the rim at deg (0 = top, clockwise), as a fraction of the box.
    public static func rimPoint(_ deg: Double, reach: Double = 50) -> (Double, Double) {
        let r = (deg - 90) * .pi / 180
        return ((50 + reach * cos(r)).rounded() / 100, (50 + reach * sin(r)).rounded() / 100)
    }

    /// Seeded speckles for the paper tile (the web uses an SVG noise filter): x, y, r, alpha factor.
    public static let paperSpeckles: [[Double]] = {
        var seed: Int64 = 7
        func rand() -> Double { seed = (seed * 16807) % 2147483647; return Double(seed) / 2147483647 }
        return (0..<260).map { _ in [rand() * 180, rand() * 180, 0.4 + rand() * 0.7, 0.3 + rand() * 0.7] }
    }()
}
