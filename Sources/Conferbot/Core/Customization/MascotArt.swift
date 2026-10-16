//
//  MascotArt.swift
//  Conferbot
//
//  The idle call's mascot (conferbot-widget src/ts/launcher/art3d.ts
//  mascot()): the classic blob in soft clay, the launcher's colour (or the
//  owner's mascotColor), facing right in a 100 x 100 box, with the arm pose
//  the performance needs. The other shapes, eyes and accessories arrive with
//  the mascots feature; until then every call is the blob.
//
//  Drawn as layers, back to front, so each moving part is its own drawing:
//  the shadow (outside the body), then inside the body the arm behind it,
//  the body, the pupils (look), the lids, the brows, the arm in front, and
//  the three mouths. The soft blurs and the bevel (SVG filters) are left
//  out, as in RN. Ported from the React Native SDK's core/mascotArt.ts.
//  Pure: SVG markup (drawn by UI/SwiftUI/FxSvg.swift).
//

import Foundation

public enum MascotArt {
    public struct Layers: Equatable {
        public var shadow: String
        public var armBack: String?
        public var body: String
        public var look: String
        public var lids: String
        public var brows: String
        public var armFront: String?
        public var smile: String
        public var o: String
        public var grin: String
    }

    /// Each part's pivot in the drawing (CSS transform-origin): the body its feet, the arm its shoulder, the lids their top.
    public static let origins: [String: (Double, Double)] = [
        "body": (50, 94),
        "arm": (80, 64),
        "lid": (50, 39),
        "look": (50, 54),
        "brow": (50, 36),
    ]

    private static func rgb(_ hex: String) -> [Int]? {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard let m = Keyframes.firstMatch("(?i)^#([0-9a-f]{3}|[0-9a-f]{6})$", s) else {
            guard let r = Keyframes.firstMatch("^rgba?\\(\\s*(\\d+)[\\s,]+(\\d+)[\\s,]+(\\d+)", s) else { return nil }
            return [Int(r[1]) ?? 0, Int(r[2]) ?? 0, Int(r[3]) ?? 0]
        }
        let g = m[1]
        let h = Array(g.count == 3 ? g.map { "\($0)\($0)" }.joined() : g)
        return [0, 2, 4].map { Int(String(h[$0...$0 + 1]), radix: 16) ?? 0 }
    }

    /// CSS color-mix(in srgb, a p%, b).
    public static func mixColor(_ a: String, _ p: Double, _ b: String) -> String {
        let x = rgb(a) ?? [99, 102, 241]
        let y = rgb(b) ?? [255, 255, 255]
        let f = p / 100
        return "#" + (0..<3).map { i in
            let v = Int((Double(x[i]) * f + Double(y[i]) * (1 - f) + 0.5).rounded(.down))
            let s = String(v, radix: 16)
            return s.count < 2 ? "0" + s : s
        }.joined()
    }

    /// The owner's mascot colour when it is a hex colour (art3d mascotLookOf), else the launcher's.
    public static func color(_ c: [String: Any]?, launcher: String) -> String {
        let v = ((c?["mascotColor"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        return Keyframes.firstMatch("(?i)^#([0-9a-f]{3}|[0-9a-f]{6})$", v) != nil ? v : launcher
    }

    private static let blob = "M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z"

    private static func n(_ x: Double) -> String { Keyframes.jsNum(x) }

    public static func layers(_ accent: String, arm: String, accentIn: String? = nil) -> Layers {
        let inner = accentIn ?? accent
        let light = mixColor(accent, 42, "#ffffff")
        let dark = mixColor(accent, 62, "#000000")
        let defs = "<defs>" +
            "<radialGradient id=\"b\" cx=\"0.36\" cy=\"0.28\" r=\"0.85\"><stop offset=\"0\" stop-color=\"\(light)\"/><stop offset=\"0.5\" stop-color=\"\(accent)\"/><stop offset=\"1\" stop-color=\"\(dark)\"/></radialGradient>" +
            "<linearGradient id=\"a\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(light)\"/><stop offset=\"1\" stop-color=\"\(dark)\"/></linearGradient>" +
            "<radialGradient id=\"h\" cx=\"0.35\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"\(light)\"/><stop offset=\"0.6\" stop-color=\"\(accent)\"/><stop offset=\"1\" stop-color=\"\(dark)\"/></radialGradient>" +
            "<radialGradient id=\"e\" cx=\"0.4\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#ffffff\"/><stop offset=\"0.75\" stop-color=\"#f3f5f9\"/><stop offset=\"1\" stop-color=\"#c9d0dc\"/></radialGradient>" +
            "<linearGradient id=\"l\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(light)\"/><stop offset=\"1\" stop-color=\"\(accent)\"/></linearGradient>" +
            "<radialGradient id=\"s\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\"><stop offset=\"0\" stop-color=\"#0f172a\" stop-opacity=\"0.32\"/><stop offset=\"1\" stop-color=\"#0f172a\" stop-opacity=\"0\"/></radialGradient>" +
            "<linearGradient id=\"j\" x1=\"0\" y1=\"0\" x2=\"0.4\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(mixColor(accent, 82, "#ffffff"))\"/><stop offset=\"0.5\" stop-color=\"\(accent)\"/><stop offset=\"1\" stop-color=\"\(mixColor(accent, 78, "#000000"))\"/></linearGradient>" +
            "<radialGradient id=\"p\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\"><stop offset=\"0.5\" stop-color=\"#0b1020\"/><stop offset=\"1\" stop-color=\"\(mixColor(inner, 45, "#0b1020"))\"/></radialGradient>" +
            "</defs>"
        func svg(_ body: String) -> String { "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(defs)\(body)</svg>" }

        let ex1 = 37.0, ex2 = 63.0, ey = 52.0
        let limbW = 13.0
        func mitten(_ cx: Double, _ cy: Double, _ r: Double, _ rot: Double, rim: Bool = false) -> String {
            let edge = rim ? " stroke=\"\(light)\" stroke-width=\"1.6\"" : " stroke=\"\(dark)\" stroke-width=\"0.8\" stroke-opacity=\"0.55\""
            return "<g transform=\"rotate(\(n(rot)) \(n(cx)) \(n(cy)))\"><ellipse cx=\"\(n(cx))\" cy=\"\(n(cy))\" rx=\"\(n(r))\" ry=\"\(n(r * 1.08))\" fill=\"url(#h)\"\(edge)/>" +
                "<ellipse cx=\"\(n(cx - r * 0.72))\" cy=\"\(n(cy + r * 0.25))\" rx=\"\(n(r * 0.38))\" ry=\"\(n(r * 0.5))\" fill=\"url(#h)\"\(edge) transform=\"rotate(-25 \(n(cx - r * 0.72)) \(n(cy + r * 0.25)))\"/>" +
                "<ellipse cx=\"\(n(cx - r * 0.3))\" cy=\"\(n(cy - r * 0.4))\" rx=\"\(n(r * 0.35))\" ry=\"\(n(r * 0.22))\" fill=\"#fff\" opacity=\"0.6\"/></g>"
        }
        func limb(_ d: String, _ extra: Double = 0) -> String {
            "<path d=\"\(d)\" fill=\"none\" stroke=\"\(dark)\" stroke-width=\"\(n(limbW + extra + 1.4))\" stroke-linecap=\"round\" stroke-opacity=\"0.6\"/>" +
                "<path d=\"\(d)\" fill=\"none\" stroke=\"url(#j)\" stroke-width=\"\(n(limbW + extra))\" stroke-linecap=\"round\"/>" +
                "<path d=\"\(d)\" fill=\"none\" stroke=\"#fff\" stroke-width=\"\(n((limbW + extra) * 0.22))\" stroke-linecap=\"round\" opacity=\"0.3\" transform=\"translate(-0.8 -1.2)\"/>"
        }
        let arms = [
            "down": limb("M79 66 Q88 72 89 80") + mitten(90, 84, 8.5, -10),
            "whisper": limb("M79 70 Q80 79 71 77") + mitten(65, 74, 8, 35),
            "wave": limb("M79 62 Q88 54 90 44") + mitten(92, 35, 9.5, 12),
            "reach": limb("M78 66 Q88 63 96 61", 2) + mitten(102, 60, 11.5, 90, rim: true),
            "knock": limb("M78 67 Q88 69 92 62", 2) + mitten(96, 57, 12, 60, rim: true),
        ]
        let front = arm == "whisper" || arm == "knock" || arm == "reach"
        func pupil(_ cx: Double) -> String {
            let r = 6.2
            return "<circle cx=\"\(n(cx + 1))\" cy=\"54\" r=\"\(n(r))\" fill=\"url(#p)\"/>" +
                "<path d=\"M\(n(cx + 1 - r * 0.62)) \(n(54 + r * 0.42)) Q\(n(cx + 1)) \(n(54 + r * 0.92)) \(n(cx + 1 + r * 0.62)) \(n(54 + r * 0.42))\" fill=\"none\" stroke=\"#fff\" stroke-width=\"\(n(r * 0.16))\" stroke-linecap=\"round\" opacity=\"0.28\"/>" +
                "<ellipse cx=\"\(n(cx - 1.2))\" cy=\"51.2\" rx=\"2.5\" ry=\"2.2\" fill=\"#fff\" transform=\"rotate(-20 \(n(cx - 1.2)) 51.2)\"/>" +
                "<circle cx=\"\(n(cx + 2.6))\" cy=\"57\" r=\"0.9\" fill=\"#fff\" opacity=\"0.85\"/>"
        }
        func white(_ cx: Double) -> String {
            "<ellipse cx=\"\(n(cx))\" cy=\"52\" rx=\"9.5\" ry=\"11.5\" fill=\"url(#e)\" stroke=\"\(dark)\" stroke-width=\"0.8\" stroke-opacity=\"0.35\"/>" +
                "<path d=\"M\(n(cx - 8)) 46 Q\(n(cx)) 38.5 \(n(cx + 8)) 46\" fill=\"none\" stroke=\"\(dark)\" stroke-width=\"1.6\" stroke-linecap=\"round\" opacity=\"0.14\"/>"
        }
        func lid(_ cx: Double) -> String { "<rect x=\"\(n(cx - 11))\" y=\"39\" width=\"22\" height=\"26\" rx=\"10\" fill=\"url(#l)\"/>" }
        let cheeks = "<ellipse cx=\"25\" cy=\"70\" rx=\"6\" ry=\"3.6\" fill=\"#fb7185\" opacity=\"0.4\"/><ellipse cx=\"75\" cy=\"70\" rx=\"6\" ry=\"3.6\" fill=\"#fb7185\" opacity=\"0.4\"/>" +
            "<ellipse cx=\"23\" cy=\"68.6\" rx=\"1.7\" ry=\"1\" fill=\"#fff\" opacity=\"0.5\"/><ellipse cx=\"73\" cy=\"68.6\" rx=\"1.7\" ry=\"1\" fill=\"#fff\" opacity=\"0.5\"/>"
        let body = [
            limb("M22 68 Q12 74 13 82"),
            mitten(13, 84, 7.5, 10),
            "<path d=\"M49 23 C46 14 51 7.5 57 9.5 C61.5 11 61 17 56.5 17\" fill=\"none\" stroke=\"url(#a)\" stroke-width=\"4.4\" stroke-linecap=\"round\"/>",
            "<path d=\"\(blob)\" fill=\"url(#b)\"/>",
            "<path d=\"M22 80 C32 90 68 90 78 80\" fill=\"none\" stroke=\"\(light)\" stroke-width=\"3\" stroke-linecap=\"round\" opacity=\"0.3\"/>",
            "<path d=\"M24 38 C30 28 40 23 50 23\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\" opacity=\"0.4\"/>",
            "<ellipse cx=\"35\" cy=\"33\" rx=\"8\" ry=\"4.5\" fill=\"#fff\" opacity=\"0.55\" transform=\"rotate(-28 35 33)\"/>",
            white(ex1),
            white(ex2),
            cheeks,
        ].joined()
        return Layers(
            shadow: svg("<ellipse cx=\"50\" cy=\"95\" rx=\"32\" ry=\"5\" fill=\"url(#s)\"/><ellipse cx=\"50\" cy=\"95\" rx=\"17.6\" ry=\"2.2\" fill=\"url(#s)\" opacity=\"0.7\"/>"),
            armBack: front ? nil : svg(arms[arm] ?? arms["down"]!),
            body: svg(body),
            look: svg(pupil(ex1) + pupil(ex2)),
            lids: svg(lid(ex1) + lid(ex2)),
            brows: svg("<path d=\"M\(n(ex1 - 8)) \(n(ey - 16)) q8 -5 15 -1 M\(n(ex2 - 7)) \(n(ey - 17)) q7 -4 15 1\" fill=\"none\" stroke=\"\(dark)\" stroke-width=\"2.6\" stroke-linecap=\"round\"/>"),
            armFront: front ? svg(arms[arm]!) : nil,
            smile: svg("<path d=\"M42 72 Q50 80 58 72\" fill=\"none\" stroke=\"#1e1b2e\" stroke-width=\"2.6\" stroke-linecap=\"round\"/>"),
            o: svg("<ellipse cx=\"50\" cy=\"74\" rx=\"3.4\" ry=\"4\" fill=\"#3b1d2e\"/>"),
            grin: svg("<path d=\"M40 70 Q50 84 60 70 Z\" fill=\"#3b1d2e\"/><path d=\"M44 76 Q50 80 56 76 Q50 83 44 76 Z\" fill=\"#fb7185\"/>"))
    }
}
