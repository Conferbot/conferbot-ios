//
//  MascotArt.swift
//  Conferbot
//
//  The owner's mascot (conferbot-widget src/ts/launcher/art3d.ts mascot(),
//  mascotLookOf, mascotScaleOf, mascotColorOf): ten originals and seventeen
//  industry characters in soft clay, in the owner's colour (or the
//  launcher's), with the owner's eyes and accessory, facing right in a
//  100 x 100 box with the arm pose a performance needs. The bust (typing,
//  the launcher) is the head and body only, framed tight (viewBox 4 0 92 96).
//
//  Drawn as layers, back to front, so each part the web animates
//  (.cb-m-body, .cb-m-arm, .cb-m-look, .cb-m-lid, .cb-m-brow, the three
//  mouths) is its own drawing: the shadow (outside the body); then inside
//  the body the tail, the arm behind it, the body (left arm, what is behind
//  the head, the silhouette, its shine, what is under the face, the eye
//  whites), the pupils (look), the sleepy lids (face), the blinking lids,
//  the shades and cheeks (cover), the brows, the arm in front, the three
//  mouths, and on top what the character holds and wears. Stacked in this
//  order they are the web's drawing, element for element.
//
//  No filters (as in RN): the bevel, the soft glows on the shine and the
//  cheeks and the LED glow are left out (the shine and cheeks a touch
//  lighter instead). color-mix() is worked out to a hex colour. Ported from
//  the React Native SDK's core/mascotArt.ts, markup for markup. Pure: SVG
//  markup (drawn by UI/SwiftUI/FxSvg.swift).
//

import Foundation

public enum MascotArt {
    public static let shapes = [
        "blob", "cat", "fox", "bear", "bunny", "owl", "robot", "ghost", "dino", "cloud",
        "medic", "tooth", "piggy", "shield", "house", "justice", "bag", "chef", "suitcase", "scholar", "laptop", "athlete", "stylist", "car", "parcel", "civic", "heart",
    ]
    public static let eyes = ["round", "happy", "sleepy", "star", "shades"]
    public static let accessories = ["none", "headset", "bow", "cap", "crown", "flower", "glasses"]
    public static let arms = ["down", "whisper", "wave", "reach", "knock"]
    public static let nameMax = 20
    /// Each character's own name, a suggestion for owners who have not named theirs.
    public static let defaultNames: [String: String] = [
        "blob": "Bloop", "cat": "Mochi", "fox": "Rusty", "bear": "Bruno", "bunny": "Clover",
        "owl": "Hoot", "robot": "Bolt", "ghost": "Boo", "dino": "Rex", "cloud": "Puff",
        "medic": "Doc", "tooth": "Pearl", "piggy": "Penny", "shield": "Shelby", "house": "Haven", "justice": "Justin",
        "bag": "Tote", "chef": "Basil", "suitcase": "Jet", "scholar": "Sage", "laptop": "Pixel", "athlete": "Flex",
        "stylist": "Glam", "car": "Revvy", "parcel": "Dash", "civic": "Civvy", "heart": "Hope",
    ]
    /// The mascot's size in the launcher, as a share of the button (%).
    public static let scaleMin: Double = 70
    public static let scaleMax: Double = 150
    public static let scaleDefault: Double = 112

    /// The mascot the owner designed: every field defaulted (the classic blob).
    public struct Look: Equatable {
        public var shape = "blob"
        public var eyes = "round"
        public var accessory = "none"
        /// The owner's colour; empty = the launcher's.
        public var color = ""
        public var name = ""

        public init(shape: String = "blob", eyes: String = "round", accessory: String = "none", color: String = "", name: String = "") {
            self.shape = shape
            self.eyes = eyes
            self.accessory = accessory
            self.color = color
            self.name = name
        }
    }

    public struct Layers: Equatable {
        public var shadow: String?
        public var tail: String?
        public var armBack: String?
        public var body: String
        public var look: String
        public var face: String?
        public var lids: String
        public var cover: String?
        public var brows: String
        public var armFront: String?
        public var smile: String
        public var o: String
        public var grin: String
        public var top: String?

        /// The layers back to front (the order they are stacked in), nil where a layer is not drawn.
        public var ordered: [(String, String?)] {
            [("shadow", shadow), ("tail", tail), ("armBack", armBack), ("body", body), ("look", look), ("face", face), ("lids", lids),
             ("cover", cover), ("brows", brows), ("armFront", armFront), ("smile", smile), ("o", o), ("grin", grin), ("top", top)]
        }
    }

    /// The layers' names back to front.
    public static let layerOrder = ["shadow", "tail", "armBack", "body", "look", "face", "lids", "cover", "brows", "armFront", "smile", "o", "grin", "top"]

    private static let hex = "(?i)^#([0-9a-f]{3}|[0-9a-f]{6})$"

    private static func oneOf(_ v: Any?, _ all: [String], _ d: String) -> String {
        (v as? String).flatMap { all.contains($0) ? $0 : nil } ?? d
    }

    /// The mascot the owner designed (art3d mascotLookOf): junk falls back to the blob, round eyes, nothing worn.
    public static func lookOf(_ c: [String: Any]?) -> Look {
        let color = ((c?["mascotColor"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var name = ""
        if let n = c?["mascotName"] as? String {
            name = String(n.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(nameMax))
        }
        return Look(
            shape: oneOf(c?["mascotShape"], shapes, "blob"),
            eyes: oneOf(c?["mascotEyes"], eyes, "round"),
            accessory: oneOf(c?["mascotAccessory"], accessories, "none"),
            color: Keyframes.firstMatch(hex, color) != nil ? color : "",
            name: name)
    }

    /// The mascot's size in the launcher (%), clamped; the default when unset.
    public static func scaleOf(_ c: [String: Any]?) -> Double {
        let v = c?["mascotLauncherScale"]
        var n: Double?
        if let d = Keyframes.number(v), !(v is String) { n = d }
        if let s = v as? String { n = Double(s.trimmingCharacters(in: .whitespaces)) }
        guard let x = n, x.isFinite, !(v is NSNull) else { return scaleDefault }
        // Math.round: halves up.
        return (min(scaleMax, max(scaleMin, x)) + 0.5).rounded(.down)
    }

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
        return Keyframes.firstMatch(hex, v) != nil ? v : launcher
    }

    /// The body's colour: the owner's, else the launcher's (cloud, ghost and tooth: paler).
    public static func colorOf(_ look: Look?, accent: String) -> String {
        let base = (look?.color ?? "").isEmpty ? accent : look!.color
        switch look?.shape {
        case "cloud": return mixColor(base, 45, "#ffffff")
        case "ghost": return mixColor(base, 22, "#ffffff")
        // A tooth stays pearly: the brand is a tint on white.
        case "tooth": return mixColor(base, 12, "#ffffff")
        default: return rgb(base) != nil ? base : mixColor(base, 100, "#ffffff")
        }
    }

    /// The drawing's viewBox: the whole figure, or the bust framed tight.
    public static func viewBox(bust: Bool = false) -> (Double, Double, Double, Double) { bust ? (4, 0, 92, 96) : (0, 0, 100, 100) }

    /// Where a point of the drawing (its own units) lands in a size x size box (xMidYMid meet).
    public static func point(_ pt: (Double, Double), _ size: Double, bust: Bool = false) -> (Double, Double) {
        let (x, y, w, h) = viewBox(bust: bust)
        let s = min(size / w, size / h)
        return ((pt.0 - x) * s + (size - w * s) / 2, (pt.1 - y) * s + (size - h * s) / 2)
    }

    /// Points per unit of the drawing in a size x size box.
    public static func unit(_ size: Double, bust: Bool = false) -> Double {
        let (_, _, w, h) = viewBox(bust: bust)
        return min(size / w, size / h)
    }

    struct Spec {
        var body: String
        var behind: String?
        var tail: String?
        var under: String?
        var over: String?
        var eyeX: (Double, Double)?
        var eyeY: Double?
        var eyeScale: Double?
        var mouthY: Double?
        var shadow: Double?
        var whites: Bool?
        var led: Bool?
        var cheeks: Bool?
        var brows: Bool?
        var smile: String?
        var mouthInk: String?
        /// mitten (unset), nub or metal.
        var limbs: String?
    }

    private static let blob = "M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z"

    /// Each character (art3d.ts SPECS), its paints by id: b body, a/d deeper, w white, k gold, r red, n ink, t glass, c hair, q pink, m metal.
    /// Generated from RN's core/mascotArt.ts specs.
    static func spec(_ shape: String, accent: String, light: String, dark: String, pale: String) -> Spec {
        switch shape {
        case "blob": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M49 23 C46 14 51 7.5 57 9.5 C61.5 11 61 17 56.5 17" fill="none" stroke="url(#ma)" stroke-width="4.4" stroke-linecap="round"/>"##)
        case "cat": return Spec(
            body: ##"<path d="M50 26 C75 26 90 40 90 60 C90 82 72 93 50 93 C28 93 10 82 10 60 C10 40 25 26 50 26 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M15 47 L19 11 L44 28 Z" fill="url(#mb)"/><path d="M22 38 L24 19 L36 29 Z" fill="#fda4af" opacity="0.8"/><path d="M85 47 L81 11 L56 28 Z" fill="url(#mb)"/><path d="M78 38 L76 19 L64 29 Z" fill="#fda4af" opacity="0.8"/>"##,
            tail: ##"<path d="M22 84 C3 88 -2 66 9 55 C13 52 18 56 14 61 C8 68 11 80 23 78 Z" fill="url(#mb)"/><path d="M6 64 l6 2 M5 72 l7 1" stroke="\##(dark)" stroke-width="2.2" stroke-linecap="round" opacity="0.45"/>"##,
            under: ##"<ellipse cx="50" cy="85" rx="19" ry="8" fill="\##(pale)" opacity="0.8"/>"##,
            over: ##"<path d="M44 31 l2 7 M50 29 v8 M56 31 l-2 7" stroke="\##(dark)" stroke-width="2.4" stroke-linecap="round" opacity="0.45"/><path d="M46.5 64 L53.5 64 L50 67.5 Z" fill="#fb7185"/><path d="M5 64 L24 67 M4 71 L24 71 M6 78 L24 75 M95 64 L76 67 M96 71 L76 71 M94 78 L76 75" stroke="\##(dark)" stroke-width="1.4" stroke-linecap="round" opacity="0.6"/>"##,
            eyeX: (36, 64),
            eyeY: 53,
            smile: "M42 70 Q46 75 50 70 Q54 75 58 70")
        case "fox": return Spec(
            body: ##"<path d="M50 22 C70 22 84 34 88 50 L97 64 L85 67 C80 84 66 93 50 93 C34 93 20 84 15 67 L3 64 L12 50 C16 34 30 22 50 22 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M17 44 L19 3 L45 23 Z" fill="url(#mb)"/><path d="M23 35 L24 14 L38 24 Z" fill="#fda4af" opacity="0.8"/><path d="M19 3 L18.5 15 L28 11 Z" fill="\##(dark)"/><path d="M83 44 L81 3 L55 23 Z" fill="url(#mb)"/><path d="M77 35 L76 14 L62 24 Z" fill="#fda4af" opacity="0.8"/><path d="M81 3 L81.5 15 L72 11 Z" fill="\##(dark)"/>"##,
            tail: ##"<path d="M24 86 C1 93 -8 66 4 46 C8 62 15 72 29 76 Z" fill="url(#mb)"/><path d="M4 46 C-1 55 0 62 4 67 C8 59 8 52 4 46 Z" fill="#fff7ed"/>"##,
            under: ##"<path d="M50 57 C63 57 78 65 82 79 C74 90 62 93 50 93 C38 93 26 90 18 79 C22 65 37 57 50 57 Z" fill="#fff7ed" opacity="0.96"/>"##,
            over: ##"<ellipse cx="50" cy="66" rx="4.4" ry="3.2" fill="#1e1b2e"/><ellipse cx="48.8" cy="65" rx="1.4" ry="0.8" fill="#fff" opacity="0.7"/>"##,
            eyeX: (35, 65),
            eyeY: 50,
            eyeScale: 0.92,
            mouthY: 76)
        case "bear": return Spec(
            body: ##"<path d="M50 24 C76 24 90 40 90 60 C90 82 72 93 50 93 C28 93 10 82 10 60 C10 40 24 24 50 24 Z" fill="url(#mb)"/>"##,
            behind: ##"<circle cx="22" cy="28" r="12" fill="url(#mb)"/><circle cx="22" cy="28" r="6" fill="\##(dark)" opacity="0.35"/><circle cx="78" cy="28" r="12" fill="url(#mb)"/><circle cx="78" cy="28" r="6" fill="\##(dark)" opacity="0.35"/>"##,
            under: ##"<ellipse cx="50" cy="71" rx="17" ry="13" fill="\##(pale)"/>"##,
            over: ##"<path d="M44.5 63 Q50 59.5 55.5 63 Q53.5 68.5 50 69 Q46.5 68.5 44.5 63 Z" fill="#1e1b2e"/><ellipse cx="48.5" cy="62.6" rx="1.8" ry="0.9" fill="#fff" opacity="0.6"/>"##,
            eyeX: (37, 63),
            eyeY: 49,
            eyeScale: 0.78,
            mouthY: 76)
        case "bunny": return Spec(
            body: ##"<path d="M50 30 C72 30 86 44 86 62 C86 82 70 93 50 93 C30 93 14 82 14 62 C14 44 28 30 50 30 Z" fill="url(#mb)"/>"##,
            behind: ##"<g transform="rotate(-10 38 32)"><ellipse cx="38" cy="14" rx="8.5" ry="21" fill="url(#mb)"/><ellipse cx="38" cy="16" rx="4.2" ry="14" fill="#fda4af" opacity="0.8"/></g><g transform="rotate(24 62 32)"><ellipse cx="62" cy="15" rx="8.5" ry="20" fill="url(#mb)"/><ellipse cx="62" cy="17" rx="4.2" ry="13" fill="#fda4af" opacity="0.8"/></g>"##,
            under: ##"<ellipse cx="50" cy="84" rx="16" ry="8" fill="#fff" opacity="0.55"/>"##,
            over: ##"<ellipse cx="50" cy="65" rx="3.4" ry="2.6" fill="#fb7185"/><rect x="47" y="75.5" width="6" height="5.5" rx="1.6" fill="#fff" stroke="#e2e8f0" stroke-width="0.6"/><path d="M50 75.5 V81" stroke="#e2e8f0" stroke-width="0.6"/>"##,
            eyeX: (38, 62),
            eyeY: 55,
            eyeScale: 0.88,
            mouthY: 72)
        case "owl": return Spec(
            body: ##"<path d="M50 18 C74 18 88 36 88 60 C88 82 72 93 50 93 C28 93 12 82 12 60 C12 36 26 18 50 18 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M17 36 L14 10 L35 24 Z" fill="url(#mb)"/><path d="M83 36 L86 10 L65 24 Z" fill="url(#mb)"/>"##,
            under: ##"<circle cx="35" cy="50" r="15.5" fill="\##(pale)"/><circle cx="65" cy="50" r="15.5" fill="\##(pale)"/><path d="M34 79 q4 4 8 0 q4 4 8 0 q4 4 8 0 q4 4 8 0 M38 86 q4 4 8 0 q4 4 8 0 q4 4 8 0" fill="none" stroke="\##(light)" stroke-width="2" stroke-linecap="round" opacity="0.8"/>"##,
            over: ##"<path d="M45.5 59 L54.5 59 L50 68 Z" fill="#f59e0b"/><path d="M45.5 59 L54.5 59 L50 62 Z" fill="#fbbf24"/>"##,
            eyeX: (35, 65),
            eyeY: 50,
            eyeScale: 1.08,
            mouthY: 75,
            cheeks: false,
            smile: "M47 73 Q50 75.5 53 73")
        case "robot": return Spec(
            body: ##"<rect x="13" y="24" width="74" height="69" rx="18" fill="url(#mb)"/><path d="M24 87 H76" stroke="\##(dark)" stroke-width="1.6" stroke-linecap="round" opacity="0.35"/>"##,
            behind: ##"<path d="M50 24 V11" stroke="\##(dark)" stroke-width="3.2" stroke-linecap="round"/><circle cx="50" cy="8" r="5" fill="#fde047" stroke="\##(dark)" stroke-width="1.4"/><rect x="5" y="50" width="9" height="16" rx="3" fill="\##(dark)"/><rect x="86" y="50" width="9" height="16" rx="3" fill="\##(dark)"/>"##,
            under: ##"<rect x="20" y="37" width="60" height="32" rx="14" fill="#0b1020"/><path d="M26 42 H44" stroke="#fff" stroke-width="2" stroke-linecap="round" opacity="0.25"/>"##,
            eyeX: (37, 63),
            eyeY: 53,
            eyeScale: 0.9,
            mouthY: 80,
            whites: false,
            led: true,
            cheeks: false,
            brows: false,
            smile: "M42 78 Q50 84 58 78",
            mouthInk: "#67e8f9",
            limbs: "metal")
        case "ghost": return Spec(
            body: ##"<path d="M50 16 C74 16 88 34 88 58 V84 q-6.4 9 -12.8 0 q-6.4 9 -12.8 0 q-6.4 9 -12.8 0 q-6.4 9 -12.8 0 q-6.4 9 -12.8 0 V58 C12 34 26 16 50 16 Z" fill="url(#mb)"/>"##,
            eyeX: (38, 62),
            eyeY: 50,
            eyeScale: 1.05,
            mouthY: 70,
            shadow: 22,
            whites: false,
            brows: false,
            limbs: "nub")
        case "dino": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M28 27 L32 11 L39 22 L46 6 L52 20 L58 6 L63 21 L69 11 L73 27 Z" fill="\##(dark)"/>"##,
            tail: ##"<path d="M20 86 C4 91 -5 80 1 70 C7 77 14 80 23 78 Z" fill="url(#mb)"/><path d="M1 70 l4 -6 l3 8 Z" fill="\##(dark)"/>"##,
            under: ##"<ellipse cx="50" cy="82" rx="21" ry="10" fill="#fef9c3" opacity="0.75"/>"##,
            over: ##"<ellipse cx="45" cy="64" rx="1.6" ry="1.1" fill="\##(dark)"/><ellipse cx="55" cy="64" rx="1.6" ry="1.1" fill="\##(dark)"/><circle cx="22" cy="63" r="1.2" fill="\##(dark)" opacity="0.4"/><circle cx="26" cy="66" r="1.2" fill="\##(dark)" opacity="0.4"/><circle cx="78" cy="63" r="1.2" fill="\##(dark)" opacity="0.4"/><circle cx="74" cy="66" r="1.2" fill="\##(dark)" opacity="0.4"/><path d="M53 73.5 l2 3.2 l2 -3.2 Z" fill="#fff"/>"##,
            eyeX: (36, 64),
            eyeY: 50,
            eyeScale: 0.95,
            mouthY: 72)
        case "cloud": return Spec(
            body: ##"<circle cx="27" cy="46" r="17" fill="url(#mb)"/><circle cx="44" cy="31" r="18" fill="url(#mb)"/><circle cx="62" cy="32" r="17" fill="url(#mb)"/><circle cx="76" cy="48" r="15" fill="url(#mb)"/><path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/><circle cx="28" cy="86" r="8" fill="url(#mb)"/><circle cx="72" cy="86" r="8" fill="url(#mb)"/>"##,
            eyeX: (38, 62),
            eyeY: 56,
            eyeScale: 0.85,
            mouthY: 73,
            brows: false,
            limbs: "nub")
        case "medic": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M12.5 68 C15 84 30 93 50 93 C70 93 85 84 87.5 68 L63 71 L50 88 L37 71 Z" fill="url(#mw)"/><path d="M37 71 L50 88 L43 73 Z M63 71 L50 88 L57 73 Z" fill="#cbd5e1" opacity="0.75"/><rect x="29.5" y="74" width="2.6" height="7" rx="1.2" fill="#3b82f6"/><rect x="25" y="78" width="11" height="8" rx="2" fill="#fff" stroke="#cbd5e1" stroke-width="0.9"/><rect x="65" y="78.5" width="11.5" height="6" rx="1.6" fill="#fff" stroke="#cbd5e1" stroke-width="0.9"/><path d="M67.5 81.5 H74" stroke="\##(dark)" stroke-width="1.4" stroke-linecap="round"/>"##,
            over: ##"<path d="M31 70 C29 81 40 86 50 85 C60 86 71 81 69 70" fill="none" stroke="url(#mn)" stroke-width="2.6" stroke-linecap="round"/><circle cx="31" cy="69.5" r="1.9" fill="#94a3b8"/><circle cx="69" cy="69.5" r="1.9" fill="#94a3b8"/><path d="M50 85 V88" stroke="url(#mn)" stroke-width="2.6" stroke-linecap="round"/><circle cx="50" cy="90.5" r="4.4" fill="url(#mm)" stroke="#64748b" stroke-width="1"/><circle cx="50" cy="90.5" r="2.2" fill="#cbd5e1"/><circle cx="48.6" cy="89.2" r="1.1" fill="#fff"/><g transform="rotate(-9 50 26)"><path d="M31 33 L34.5 15.5 C35 13.2 36.6 12 39 12 H61 C63.4 12 65 13.2 65.5 15.5 L69 33 C57 30 43 30 31 33 Z" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.8"/><path d="M31 33 C43 30 57 30 69 33 L68.4 37.4 C57 34.4 43 34.4 31.6 37.4 Z" fill="#e2e8f0" stroke="#cbd5e1" stroke-width="0.8"/><path d="M39.5 13.5 L37 31 M60.5 13.5 L63 31" stroke="#cbd5e1" stroke-width="1" stroke-linecap="round"/><path d="M47.8 15.5 h4.4 v3.6 h3.6 v4.4 h-3.6 v3.6 h-4.4 v-3.6 h-3.6 v-4.4 h3.6 Z" fill="url(#mr)"/><ellipse cx="40.5" cy="16" rx="2.6" ry="1.3" fill="#fff"/></g>"##,
            eyeY: 55,
            eyeScale: 0.92,
            mouthY: 70)
        case "tooth": return Spec(
            body: ##"<path d="M50 25 C57 19 70 16 80 22 C91 29 91 48 85 61 C81 70 80 80 77 90 C75 97 67 97 66 90 C64 82 60 77 50 77 C40 77 36 82 34 90 C33 97 25 97 23 90 C20 80 19 70 15 61 C9 48 9 29 20 22 C30 16 43 19 50 25 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M26 26 C33 22 42 23 47 28" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round" opacity="0.85"/>"##,
            over: ##"<path d="M86 10 l2.2 5.4 l5.4 2.2 l-5.4 2.2 l-2.2 5.4 l-2.2 -5.4 l-5.4 -2.2 l5.4 -2.2 Z" fill="url(#mk)"/><path d="M92 30 l1.2 2.8 l2.8 1.2 l-2.8 1.2 l-1.2 2.8 l-1.2 -2.8 l-2.8 -1.2 l2.8 -1.2 Z" fill="#fde68a"/>"##,
            eyeX: (37, 63),
            eyeY: 45,
            eyeScale: 0.9,
            mouthY: 63,
            shadow: 26)
        case "piggy": return Spec(
            body: ##"<path d="M50 26 C76 26 91 42 91 61 C91 82 73 93 50 93 C27 93 9 82 9 61 C9 42 24 26 50 26 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M16 42 L13 16 C22 17 33 24 38 32 Z" fill="url(#mb)"/><path d="M19 36 L17.5 22.5 C23 24.5 28 28 31 32 Z" fill="#fda4af" opacity="0.75"/><path d="M84 42 L87 16 C78 17 67 24 62 32 Z" fill="url(#mb)"/><path d="M81 36 L82.5 22.5 C77 24.5 72 28 69 32 Z" fill="#fda4af" opacity="0.75"/><g transform="rotate(-8 50 17)"><circle cx="50" cy="17" r="10.5" fill="url(#mk)" stroke="#b45309" stroke-width="1"/><circle cx="50" cy="17" r="7.6" fill="none" stroke="#fef3c7" stroke-width="1.2" opacity="0.8"/><path d="M53.2 13.4 C51.8 12.2 47 12.2 47 14.9 C47 17.7 53.2 16.5 53.2 19.4 C53.2 22.1 48.4 22 46.8 20.7 M50 10.8 V23.2" fill="none" stroke="#92400e" stroke-width="1.7" stroke-linecap="round"/><ellipse cx="45.5" cy="12" rx="2.6" ry="1.4" fill="#fff" opacity="0.85" transform="rotate(-30 45.5 12)"/></g>"##,
            tail: ##"<path d="M12 70 C2 70 2 60 8 60 C13 60 12 67 6 66" fill="none" stroke="url(#ma)" stroke-width="3.6" stroke-linecap="round"/>"##,
            under: ##"<rect x="38.5" y="27" width="23" height="4.8" rx="2.4" fill="\##(dark)" opacity="0.85"/><path d="M41 33.2 H59" stroke="#fff" stroke-width="1.2" stroke-linecap="round" opacity="0.45"/>"##,
            over: ##"<ellipse cx="50" cy="67" rx="12.5" ry="9" fill="\##(light)" stroke="\##(dark)" stroke-width="0.9" stroke-opacity="0.35"/><ellipse cx="47" cy="63.4" rx="6.5" ry="2.6" fill="#fff" opacity="0.45"/><ellipse cx="45.5" cy="67.8" rx="2.1" ry="3" fill="\##(dark)"/><ellipse cx="54.5" cy="67.8" rx="2.1" ry="3" fill="\##(dark)"/><path d="M76 9 l1.8 4.4 l4.4 1.8 l-4.4 1.8 l-1.8 4.4 l-1.8 -4.4 l-4.4 -1.8 l4.4 -1.8 Z" fill="#fde68a"/><path d="M86 24 l1 2.4 l2.4 1 l-2.4 1 l-1 2.4 l-1 -2.4 l-2.4 -1 l2.4 -1 Z" fill="#fef3c7"/>"##,
            eyeX: (34, 66),
            eyeY: 50,
            eyeScale: 0.82,
            mouthY: 80,
            smile: "M44 78 Q50 83 56 78")
        case "shield": return Spec(
            body: ##"<path d="M50 13 C61 21 75 24 88 24 C89 58 77 82 50 95 C23 82 11 58 12 24 C25 24 39 21 50 13 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M50 20 C60 27 72 29.5 82 30 C82 58 71 78 50 88.5 C29 78 18 58 18 30 C28 29.5 40 27 50 20 Z" fill="none" stroke="\##(light)" stroke-width="2.4" opacity="0.75"/>"##,
            over: ##"<path d="M50 5.5 l2.4 4.9 l5.4 0.8 l-3.9 3.8 l0.9 5.4 l-4.8 -2.5 l-4.8 2.5 l0.9 -5.4 l-3.9 -3.8 l5.4 -0.8 Z" fill="url(#mk)" stroke="#b45309" stroke-width="0.8" stroke-linejoin="round"/>"##,
            eyeX: (37, 63),
            eyeY: 48,
            eyeScale: 0.9,
            mouthY: 67,
            shadow: 26)
        case "house": return Spec(
            body: ##"<rect x="17" y="42" width="66" height="51" rx="9" fill="url(#mb)"/>"##,
            behind: ##"<rect x="66" y="12" width="10" height="20" rx="2.5" fill="url(#md)"/><rect x="64.5" y="10" width="13" height="4.5" rx="2" fill="\##(light)"/><path d="M50 11 C52 11 53.5 12 55 13.2 L91 42 C95 45.5 92.5 51 88 51 L12 51 C7.5 51 5 45.5 9 42 L45 13.2 C46.5 12 48 11 50 11 Z" fill="url(#md)"/><path d="M14 45 L48 18" stroke="#fff" stroke-width="2.4" stroke-linecap="round" opacity="0.35"/>"##,
            under: ##"<rect x="17" y="49" width="66" height="4" fill="\##(dark)" opacity="0.18"/>"##,
            over: ##"<rect x="65" y="76" width="11" height="17" rx="5.5" fill="url(#mn)"/><circle cx="73.4" cy="85" r="1.2" fill="#fbbf24"/><path d="M22 93 H80" stroke="\##(dark)" stroke-width="1.4" opacity="0.3"/>"##,
            eyeX: (37, 63),
            eyeY: 60,
            eyeScale: 0.84,
            mouthY: 75,
            cheeks: false,
            smile: "M43 73 Q50 79 57 73")
        case "justice": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M50 6 V24" stroke="url(#mk)" stroke-width="3" stroke-linecap="round"/><circle cx="50" cy="4.6" r="2.8" fill="url(#mk)" stroke="#b45309" stroke-width="0.7"/><path d="M24 11.6 L76 6.4" stroke="url(#mk)" stroke-width="2.6" stroke-linecap="round"/><circle cx="50" cy="9" r="2" fill="#fde68a" stroke="#b45309" stroke-width="0.7"/><path d="M24 11.6 L17.5 25.5 M24 11.6 L30.5 25.5 M76 6.4 L69.5 20.3 M76 6.4 L82.5 20.3" stroke="#b45309" stroke-width="0.9"/><path d="M15 25.5 H33 C32 30.6 28 33 24 33 C20 33 16 30.6 15 25.5 Z" fill="url(#mk)" stroke="#b45309" stroke-width="0.7"/><path d="M67 20.3 H85 C84 25.4 80 27.8 76 27.8 C72 27.8 68 25.4 67 20.3 Z" fill="url(#mk)" stroke="#b45309" stroke-width="0.7"/><path d="M17.5 27 H25 M69.5 21.8 H77" stroke="#fff" stroke-width="1.2" stroke-linecap="round" opacity="0.7"/>"##,
            under: ##"<path d="M12.5 69 C15 84 30 93 50 93 C70 93 85 84 87.5 69 L62 73 L50 93 L38 73 Z" fill="url(#mn)"/><path d="M38 73 L62 73 L50 93 Z" fill="url(#mw)"/><path d="M38 73 L45 86 L41 75.5 Z M62 73 L55 86 L59 75.5 Z" fill="#fff" opacity="0.14"/><path d="M50 80 L42.5 75.6 Q41 80 42.5 84.4 Z M50 80 L57.5 75.6 Q59 80 57.5 84.4 Z" fill="url(#mr)"/><rect x="47.6" y="77.4" width="4.8" height="5.2" rx="1.6" fill="#b91c1c"/><path d="M43.6 77.6 L46.4 78.6" stroke="#fff" stroke-width="1" stroke-linecap="round" opacity="0.6"/>"##,
            eyeY: 50,
            eyeScale: 0.9,
            mouthY: 66)
        case "bag": return Spec(
            body: ##"<path d="M20 34 H80 C83 34 85 36 85.3 39 L89 86 C89.4 90 86.5 93 83 93 H17 C13.5 93 10.6 90 11 86 L14.7 39 C15 36 17 34 20 34 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M34 40 V26 C34 12 66 12 66 26 V40" fill="none" stroke="\##(dark)" stroke-width="5.4" stroke-linecap="round"/><path d="M34 40 V26 C34 12 66 12 66 26 V40" fill="none" stroke="\##(light)" stroke-width="3" stroke-linecap="round"/><path d="M36 26 C37 16 50 14 56 16" fill="none" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.35"/><path d="M30 36 C27 30 31 24.5 37 26 C38 20 46 18.5 49 23.5 C52 18 61 19.5 62 26 C68 24.5 73 30 70 36 Z" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.7"/><path d="M40 36 C38.5 31.5 42 28 46 29.5 C47.5 25.5 54 25.5 55.5 29.5 C59 28.5 62 32 60.5 36 Z" fill="url(#mq)"/><path d="M35 28.5 C36.5 26.6 38.6 26.2 40.4 26.8 M50.5 23 C52.4 21.4 55 21.2 57 22.4" fill="none" stroke="#fff" stroke-width="1.3" stroke-linecap="round" opacity="0.9"/>"##,
            under: ##"<path d="M15.2 36 H84.8 L85.3 42 H14.7 Z" fill="\##(light)" opacity="0.8"/><circle cx="34" cy="40" r="2.6" fill="\##(dark)"/><circle cx="66" cy="40" r="2.6" fill="\##(dark)"/><circle cx="33.4" cy="39.4" r="0.8" fill="#fff" opacity="0.6"/><circle cx="65.4" cy="39.4" r="0.8" fill="#fff" opacity="0.6"/>"##,
            over: ##"<path d="M66 40 C72 41 77 44 80 49" fill="none" stroke="#475569" stroke-width="0.9"/><g transform="rotate(14 83 56)"><path d="M77 50.5 L83 46 L89 50.5 V65 C89 66.2 88.2 67 87 67 H79 C77.8 67 77 66.2 77 65 Z" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.8"/><circle cx="83" cy="50.6" r="1.4" fill="#475569"/><circle cx="80.8" cy="56.4" r="1.6" fill="none" stroke="#e11d48" stroke-width="1.2"/><circle cx="85.2" cy="62" r="1.6" fill="none" stroke="#e11d48" stroke-width="1.2"/><path d="M86 55 L80 63.4" stroke="#e11d48" stroke-width="1.3" stroke-linecap="round"/></g><path d="M14 16 l1.6 4 l4 1.6 l-4 1.6 l-1.6 4 l-1.6 -4 l-4 -1.6 l4 -1.6 Z" fill="#fde68a"/>"##,
            eyeX: (37, 63),
            eyeY: 58,
            eyeScale: 0.88,
            mouthY: 76)
        case "chef": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M15.5 76 C20 87 33 93 50 93 C67 93 80 87 84.5 76 C72 82 60 84 50 84 C40 84 28 82 15.5 76 Z" fill="url(#mw)"/><circle cx="40" cy="88" r="1.5" fill="#cbd5e1"/><circle cx="60" cy="88" r="1.5" fill="#cbd5e1"/><path d="M42 82 L58 82 L50 89 Z" fill="url(#mr)"/><circle cx="50" cy="82.6" r="2.6" fill="#dc2626"/>"##,
            over: ##"<circle cx="34" cy="20" r="11" fill="url(#mw)"/><circle cx="66" cy="20" r="11" fill="url(#mw)"/><circle cx="50" cy="13" r="13" fill="url(#mw)"/><rect x="30" y="20" width="40" height="15" rx="4" fill="url(#mw)"/><path d="M40 22 V33 M50 22 V33 M60 22 V33" stroke="#cbd5e1" stroke-width="1.3" stroke-linecap="round"/><ellipse cx="44" cy="9" rx="5" ry="2.6" fill="#fff" opacity="0.9"/>"##,
            eyeY: 53,
            eyeScale: 0.92,
            mouthY: 71)
        case "suitcase": return Spec(
            body: ##"<rect x="12" y="30" width="76" height="61" rx="14" fill="url(#mb)"/>"##,
            behind: ##"<path d="M38 31 V22 C38 18 40 16 44 16 H56 C60 16 62 18 62 22 V31" fill="none" stroke="#64748b" stroke-width="6" stroke-linecap="round"/><path d="M38 31 V22 C38 18 40 16 44 16 H56 C60 16 62 18 62 22 V31" fill="none" stroke="url(#mm)" stroke-width="3.6" stroke-linecap="round"/>"##,
            tail: ##"<circle cx="26" cy="93" r="4.5" fill="url(#mn)"/><circle cx="74" cy="93" r="4.5" fill="url(#mn)"/>"##,
            under: ##"<rect x="20" y="30" width="5.5" height="61" fill="\##(dark)" opacity="0.3"/><rect x="74.5" y="30" width="5.5" height="61" fill="\##(dark)" opacity="0.3"/><rect x="19" y="73" width="7.5" height="5" rx="1.5" fill="url(#mm)"/><rect x="73.5" y="73" width="7.5" height="5" rx="1.5" fill="url(#mm)"/><circle cx="17.5" cy="35.5" r="1.6" fill="url(#mm)"/><circle cx="82.5" cy="35.5" r="1.6" fill="url(#mm)"/><circle cx="17.5" cy="85.5" r="1.6" fill="url(#mm)"/><circle cx="82.5" cy="85.5" r="1.6" fill="url(#mm)"/>"##,
            over: ##"<g transform="rotate(-14 24 81)"><circle cx="24" cy="81" r="7.4" fill="#fff"/><circle cx="24" cy="81" r="5.8" fill="#38bdf8"/><path d="M20.5 77.5 C23 77 24 79 22.6 80.6 C21.4 82 22.4 84 20.4 84.4 C19 82.4 19 79.4 20.5 77.5 Z M25.6 76.4 C27.6 77 29.4 79 29.6 81 C28 81.6 26.4 80.6 26.6 79 C26.8 78 25.6 77.6 25.6 76.4 Z M26 83.2 C27.4 83 28.6 83.6 28.2 84.6 C27 85.8 25.4 86 24.6 85.6 C24.8 84.6 25 83.4 26 83.2 Z" fill="#22c55e"/><ellipse cx="22" cy="78" rx="2" ry="1.1" fill="#fff" opacity="0.7"/></g><g transform="rotate(12 77 82)"><rect x="69.5" y="76.5" width="15" height="11" rx="1.6" fill="#fff" stroke="#e2e8f0" stroke-width="0.6" stroke-dasharray="1.4 1"/><path d="M72 84.5 L82 79.5 M78 79 L82 79.5 L80.6 83 M74.4 80 L77 82.6" fill="none" stroke="#0ea5e9" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></g><path d="M81.5 50 L83.6 54.6 L88.6 55.2 L84.9 58.6 L85.9 63.6 L81.5 61.1 L77.1 63.6 L78.1 58.6 L74.4 55.2 L79.4 54.6 Z" fill="#f43f5e" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/><path d="M61 24 C66 25 70 27 72.5 30.5" fill="none" stroke="#475569" stroke-width="0.9"/><g transform="rotate(-24 72 34)"><rect x="66.5" y="30" width="11" height="15" rx="2.4" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.7"/><rect x="66.5" y="36" width="11" height="3.4" fill="#0ea5e9"/><circle cx="72" cy="32.6" r="1.1" fill="#475569"/></g>"##,
            eyeX: (38, 62),
            eyeY: 55,
            eyeScale: 0.88,
            mouthY: 71,
            shadow: 34)
        case "scholar": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            over: ##"<path d="M31 27 L69 27 L68 38 C58 34 42 34 32 38 Z" fill="url(#mn)"/><path d="M50 7 L91 20 L50 33 L9 20 Z" fill="url(#mn)"/><path d="M50 9.5 L84 20 L50 11.8 L16 20 Z" fill="#fff" opacity="0.14"/><circle cx="50" cy="20" r="2.2" fill="url(#mk)"/><path d="M50 20 L80 26 V38" fill="none" stroke="url(#mk)" stroke-width="1.8" stroke-linecap="round"/><path d="M77.5 37 H82.5 L83.5 45 H76.5 Z" fill="url(#mk)"/>"##,
            eyeY: 54,
            eyeScale: 0.92,
            mouthY: 72)
        case "laptop": return Spec(
            body: ##"<rect x="15" y="20" width="70" height="57" rx="10" fill="url(#mb)"/><path d="M5 79 H95 L89 90 C88 92 86.5 93 84 93 H16 C13.5 93 12 92 11 90 Z" fill="url(#mm)"/><path d="M5 79 H95" stroke="#fff" stroke-width="1" opacity="0.8"/><path d="M17 82.5 H83 M20 86 H80" stroke="#64748b" stroke-width="1.8" stroke-dasharray="3.4 1.4" opacity="0.65"/><rect x="41" y="88.4" width="18" height="3" rx="1.5" fill="#94a3b8"/>"##,
            under: ##"<rect x="21" y="26" width="58" height="45" rx="6" fill="#0b1020"/><path d="M25 30 L44 30 L28 50 Z" fill="#fff" opacity="0.07"/><circle cx="50" cy="23" r="1.1" fill="#0b1020" opacity="0.6"/><circle cx="26.5" cy="31" r="1.4" fill="#f87171"/><circle cx="31" cy="31" r="1.4" fill="#fbbf24"/><circle cx="35.5" cy="31" r="1.4" fill="#34d399"/><path d="M66 31 H74" stroke="#334155" stroke-width="1.6" stroke-linecap="round"/>"##,
            over: ##"<path d="M70 4 H90 C93 4 95 6 95 9 V15 C95 18 93 20 90 20 H76 L71 24 L72 20 H70 C67 20 65 18 65 15 V9 C65 6 67 4 70 4 Z" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.8"/><path d="M74.4 8.6 L70.8 12 L74.4 15.4 M85.6 8.6 L89.2 12 L85.6 15.4 M81.8 7.6 L78.2 16.4" fill="none" stroke="\##(dark)" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>"##,
            eyeX: (38, 62),
            eyeY: 47,
            eyeScale: 0.8,
            mouthY: 66,
            shadow: 38,
            whites: false,
            led: true,
            cheeks: false,
            brows: false,
            smile: "M43 70 Q50 76 57 70",
            mouthInk: "#67e8f9",
            limbs: "metal")
        case "athlete": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M83 43 C90 44 94 52 91 58 M85 46 C92 50 93 58 88 62" fill="none" stroke="url(#mw)" stroke-width="3.4" stroke-linecap="round"/><path d="M15 41 C28 28 72 28 85 41 L87.5 49.5 C72 37 28 37 12.5 49.5 Z" fill="url(#mw)"/><path d="M15.8 43.4 C29 32 71 32 84.2 43.4 M16.6 46.4 C30 35 70 35 83.4 46.4" fill="none" stroke="#ef4444" stroke-width="1.3"/>"##,
            over: ##"<path d="M24 50 C21 54 22 57 24.5 57 C27 57 28 54 24 50 Z" fill="#7dd3fc" opacity="0.95"/><g transform="rotate(-8 14 88)"><rect x="4" y="86.2" width="20" height="3.6" rx="1.8" fill="url(#mm)"/><rect x="0" y="80" width="6.5" height="16" rx="2.4" fill="url(#mn)"/><rect x="21.5" y="80" width="6.5" height="16" rx="2.4" fill="url(#mn)"/><rect x="1.4" y="81.5" width="1.8" height="10" rx="0.9" fill="#fff" opacity="0.3"/><rect x="22.9" y="81.5" width="1.8" height="10" rx="0.9" fill="#fff" opacity="0.3"/></g>"##,
            eyeY: 57,
            eyeScale: 0.88,
            mouthY: 74)
        case "stylist": return Spec(
            body: ##"<path d="M50 20 C75 20 89 39 89 60 C89 81 72 93 50 93 C28 93 11 81 11 60 C11 39 25 20 50 20 Z" fill="url(#mb)"/>"##,
            behind: ##"<path d="M13 64 C2 36 20 8 50 9 C80 8 98 36 88 64 C86 50 80 42 72 38 L28 38 C20 42 15 50 13 64 Z" fill="url(#mc)"/>"##,
            under: ##"<path d="M14 52 C13 31 30 17 51 17 C71 17 87 30 87 47 C81 38 72 33 63 32 C57 39 46 43 35 42 C27 42 20 46 14 52 Z" fill="url(#mc)"/><path d="M63 32 C66 37 66 42 62 45" fill="none" stroke="#2a1608" stroke-width="1.4" stroke-linecap="round" opacity="0.5"/><path d="M23 34 C31 25 43 21 56 22" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" opacity="0.4"/><path d="M68 25 C74 27 79 31 82 36" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.3"/><path d="M29.4 48.4 l-3.4 -2.4 M31 45.6 l-2.2 -3.2 M70.6 48.4 l3.4 -2.4 M69 45.6 l2.2 -3.2" stroke="#1e1b2e" stroke-width="1.7" stroke-linecap="round"/>"##,
            over: ##"<path d="M64 26 Q60.6 28.6 61.4 32.4 M68.6 29 Q65.6 32 67 35.4 M60 22.6 Q56.4 24 56 27.6" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.9"/><g transform="rotate(-32 80 15)"><rect x="83" y="16" width="6.4" height="15" rx="3.2" fill="url(#mq)"/><rect x="66" y="9" width="24" height="13" rx="6.5" fill="url(#mw)" stroke="#cbd5e1" stroke-width="0.8"/><rect x="62" y="11" width="6" height="9" rx="1.8" fill="url(#mn)"/><circle cx="89" cy="15.5" r="4.6" fill="url(#mq)"/><circle cx="89" cy="15.5" r="2" fill="#fff" opacity="0.5"/><path d="M71 12.4 H83" stroke="#fff" stroke-width="1.6" stroke-linecap="round"/></g><path d="M14 15 l1.6 4 l4 1.6 l-4 1.6 l-1.6 4 l-1.6 -4 l-4 -1.6 l4 -1.6 Z" fill="#fde68a"/><path d="M8 32 l1 2.4 l2.4 1 l-2.4 1 l-1 2.4 l-1 -2.4 l-2.4 -1 l2.4 -1 Z" fill="#fff"/>"##,
            eyeY: 55,
            eyeScale: 0.92,
            mouthY: 73,
            mouthInk: "#be185d")
        case "car": return Spec(
            body: ##"<path d="M22 44 C26 30 34 25 50 25 C66 25 74 30 78 44 L88 47.5 C94 49.5 96 55 96 61 V75 C96 79.5 93 82 89 82 H11 C7 82 4 79.5 4 75 V61 C4 55 6 49.5 12 47.5 Z" fill="url(#mb)"/><circle cx="25" cy="83" r="10" fill="url(#mn)"/><circle cx="25" cy="83" r="4.6" fill="url(#mm)"/><circle cx="75" cy="83" r="10" fill="url(#mn)"/><circle cx="75" cy="83" r="4.6" fill="url(#mm)"/>"##,
            under: ##"<path d="M27 46 C30 35 37 31 50 31 C63 31 70 35 73 46 Z" fill="url(#mt)"/><path d="M33 43 L42 34" stroke="#fff" stroke-width="2.2" stroke-linecap="round" opacity="0.6"/><ellipse cx="11" cy="60" rx="4" ry="3.2" fill="#fef9c3"/><ellipse cx="89" cy="60" rx="4" ry="3.2" fill="#fef9c3"/><path d="M4 69 H96" stroke="\##(dark)" stroke-width="1.4" opacity="0.3"/>"##,
            eyeX: (39, 61),
            eyeY: 40,
            eyeScale: 0.62,
            mouthY: 62,
            shadow: 42,
            brows: false,
            smile: "M40 60 Q50 68 60 60",
            limbs: "nub")
        case "parcel": return Spec(
            body: ##"<rect x="14" y="34" width="72" height="59" rx="8" fill="url(#mb)"/>"##,
            behind: ##"<path d="M18 36 L28 20 H72 L82 36 Z" fill="\##(light)"/><path d="M28 20 L18 36 H50 L44 20 Z" fill="#fff" opacity="0.18"/><rect x="44" y="20" width="12" height="16" fill="url(#mk)" opacity="0.9"/>"##,
            under: ##"<rect x="44" y="34" width="12" height="8" fill="url(#mk)" opacity="0.9"/><rect x="14" y="34" width="72" height="4" fill="\##(dark)" opacity="0.2"/>"##,
            over: ##"<rect x="20" y="78" width="15" height="10" rx="1.5" fill="#fff" opacity="0.92"/><path d="M24 86 V81 M24 81 l-1.8 2 M24 81 l1.8 2 M31 86 V81 M31 81 l-1.8 2 M31 81 l1.8 2" stroke="#334155" stroke-width="1" stroke-linecap="round"/>"##,
            eyeX: (37, 63),
            eyeY: 55,
            eyeScale: 0.88,
            mouthY: 73)
        case "civic": return Spec(
            body: ##"<rect x="15" y="36" width="70" height="52" rx="6" fill="url(#mb)"/>"##,
            behind: ##"<path d="M50 2 V14" stroke="url(#mn)" stroke-width="1.6" stroke-linecap="round"/><path d="M50 2.5 H62 L59 5.5 L62 8.5 H50 Z" fill="url(#mr)"/><path d="M50 12 C51.5 12 52.5 12.5 54 13.3 L88 32 C91 34 90 39 86 39 H14 C10 39 9 34 12 32 L46 13.3 C47.5 12.5 48.5 12 50 12 Z" fill="url(#mw)" stroke="#cbd5e1" stroke-width="1"/><circle cx="50" cy="28" r="3.2" fill="url(#mk)"/>"##,
            tail: ##"<rect x="9" y="87" width="82" height="5" rx="2.5" fill="url(#mw)"/><rect x="4" y="91.5" width="92" height="5" rx="2.5" fill="url(#mw)"/>"##,
            under: ##"<rect x="15" y="36" width="70" height="5" fill="\##(dark)" opacity="0.2"/><rect x="18" y="44" width="7" height="42" rx="3" fill="url(#mw)" opacity="0.92"/><rect x="75" y="44" width="7" height="42" rx="3" fill="url(#mw)" opacity="0.92"/>"##,
            eyeX: (38, 62),
            eyeY: 56,
            eyeScale: 0.84,
            mouthY: 73)
        case "heart": return Spec(
            body: ##"<path d="M50 92 C37 84 9 67 9 42 C9 27 20 17 33 17 C41 17 47 21 50 27 C53 21 59 17 67 17 C80 17 91 27 91 42 C91 67 63 84 50 92 Z" fill="url(#mb)"/>"##,
            under: ##"<path d="M20 30 C24 24 31 22 36 23" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity="0.6"/>"##,
            over: ##"<path d="M50 85.6 C45.6 82.6 41.6 80 41.6 76.4 C41.6 73.9 43.4 72.2 45.7 72.2 C47.6 72.2 49.1 73.2 50 74.7 C50.9 73.2 52.4 72.2 54.3 72.2 C56.6 72.2 58.4 73.9 58.4 76.4 C58.4 80 54.4 82.6 50 85.6 Z" fill="url(#mw)" stroke="#fecdd3" stroke-width="0.8"/><ellipse cx="45.6" cy="75.2" rx="1.8" ry="1.1" fill="#fda4af"/><g transform="rotate(28 39.5 80.5)"><ellipse cx="39.5" cy="80.5" rx="5" ry="4.4" fill="\##(light)" stroke="\##(dark)" stroke-width="0.9" stroke-opacity="0.5"/><ellipse cx="43.4" cy="77.8" rx="1.8" ry="2.4" fill="\##(light)" stroke="\##(dark)" stroke-width="0.8" stroke-opacity="0.5"/><ellipse cx="38" cy="78.8" rx="1.8" ry="1" fill="#fff" opacity="0.7"/></g><g transform="rotate(-28 60.5 80.5)"><ellipse cx="60.5" cy="80.5" rx="5" ry="4.4" fill="\##(light)" stroke="\##(dark)" stroke-width="0.9" stroke-opacity="0.5"/><ellipse cx="56.6" cy="77.8" rx="1.8" ry="2.4" fill="\##(light)" stroke="\##(dark)" stroke-width="0.8" stroke-opacity="0.5"/><ellipse cx="59" cy="78.8" rx="1.8" ry="1" fill="#fff" opacity="0.7"/></g><path d="M86 8 C84 5 79 6 80 10 C80.5 12.5 84 14.5 86 16 C88 14.5 91.5 12.5 92 10 C93 6 88 5 86 8 Z" fill="url(#mr)"/><path d="M93 24 C92 22.5 89.5 23 90 25 C90.3 26.3 92 27.3 93 28 C94 27.3 95.7 26.3 96 25 C96.5 23 94 22.5 93 24 Z" fill="#fda4af"/><path d="M12 12 C11 10.5 8.5 11 9 13 C9.3 14.3 11 15.3 12 16 C13 15.3 14.7 14.3 15 13 C15.5 11 13 10.5 12 12 Z" fill="#fecdd3"/>"##,
            eyeX: (36, 64),
            eyeY: 46,
            eyeScale: 0.9,
            mouthY: 63,
            shadow: 24)
        default: return spec("blob", accent: accent, light: light, dark: dark, pale: pale)
        }
    }

    private static func known(_ v: String?, _ all: [String], _ d: String) -> String { v.flatMap { all.contains($0) ? $0 : nil } ?? d }

    /// Each moving part's pivot in the drawing (CSS transform-origin, in its own
    /// units): the body its feet, the arm its shoulder, the lids their top edge,
    /// the pupils and brows their centre. The lids sit where the character's eyes are.
    public struct Origins: Equatable {
        public var body: (Double, Double)
        public var arm: (Double, Double)
        public var lid: (Double, Double)
        public var look: (Double, Double)
        public var brow: (Double, Double)

        public static func == (a: Origins, b: Origins) -> Bool {
            [a.body, a.arm, a.lid, a.look, a.brow].map { [$0.0, $0.1] } == [b.body, b.arm, b.lid, b.look, b.brow].map { [$0.0, $0.1] }
        }

        /// A part's pivot by its name (body, arm, lid, look, brow); the centre for the rest.
        public func of(_ part: String) -> (Double, Double) {
            switch part {
            case "body": return body
            case "arm": return arm
            case "lid": return lid
            case "look": return look
            case "brow": return brow
            default: return (50, 50)
            }
        }
    }

    /// The joints of a look's character.
    public static func origins(_ look: Look? = nil) -> Origins {
        let sp = spec(known(look?.shape, shapes, "blob"), accent: "#000000", light: "#000000", dark: "#000000", pale: "#000000")
        let ex = sp.eyeX ?? (37, 63)
        let ey = sp.eyeY ?? 52
        let es = sp.eyeScale ?? 1
        return Origins(body: (50, 94), arm: (80, 64), lid: ((ex.0 + ex.1) / 2, ey + (39 - 52) * es), look: ((ex.0 + ex.1) / 2, ey + 2 * es), brow: (50, ey - 16))
    }

    /// The classic blob's pivots.
    public static let blobOrigins = origins()

    private static func n(_ x: Double) -> String { Keyframes.jsNum(x) }

    /// The owner's mascot as layers (art3d mascot(accentIn, arm, look, opts)):
    /// `accentIn` is the launcher's colour, the body is the owner's colour when
    /// set (colorOf). `bust`: head and body only, framed tight, without arms,
    /// tail or shadow (typing, the launcher).
    public static func layers(_ accentIn: String, arm armIn: String, look lookIn: Look? = nil, bust: Bool = false) -> Layers {
        let shape = known(lookIn?.shape, shapes, "blob")
        let eyes = known(lookIn?.eyes, self.eyes, "round")
        let accessory = known(lookIn?.accessory, accessories, "none")
        let arm = known(armIn, arms, "down")
        var l = lookIn ?? Look()
        l.shape = shape
        let accent = colorOf(l, accent: accentIn)
        let light = mixColor(accent, 42, "#ffffff")
        let dark = mixColor(accent, 62, "#000000")
        let pale = mixColor(accent, 26, "#ffffff")
        let sp = spec(shape, accent: accent, light: light, dark: dark, pale: pale)
        let industry = (shapes.firstIndex(of: shape) ?? 0) >= 10
        let (ex1, ex2) = sp.eyeX ?? (37, 63)
        let ey = sp.eyeY ?? 52
        let es = sp.eyeScale ?? 1
        let whites = sp.whites != false
        let led = sp.led == true
        let ledInk = mixColor(accentIn, 25, "#a5f3fc")
        let pupilInk = led ? ledInk : "#0b1020"
        let my = (sp.mouthY ?? 72) - 72

        // Clay paints for the industry characters' props (white coat, gold, red, ink, glass, hair, pink, a deeper brand).
        let paints =
            ##"<radialGradient id="mw" cx="0.35" cy="0.3" r="0.85"><stop offset="0" stop-color="#ffffff"/><stop offset="0.65" stop-color="#eef1f6"/><stop offset="1" stop-color="#b9c2d1"/></radialGradient>"## +
            ##"<linearGradient id="mk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fde68a"/><stop offset="0.55" stop-color="#f59e0b"/><stop offset="1" stop-color="#b45309"/></linearGradient>"## +
            ##"<radialGradient id="mr" cx="0.35" cy="0.3" r="0.85"><stop offset="0" stop-color="#fca5a5"/><stop offset="0.55" stop-color="#ef4444"/><stop offset="1" stop-color="#991b1b"/></radialGradient>"## +
            ##"<radialGradient id="mn" cx="0.35" cy="0.3" r="0.85"><stop offset="0" stop-color="#64748b"/><stop offset="0.55" stop-color="#1f2937"/><stop offset="1" stop-color="#0b1020"/></radialGradient>"## +
            ##"<linearGradient id="mt" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ecfeff"/><stop offset="0.5" stop-color="#a5f3fc"/><stop offset="1" stop-color="#0e7490"/></linearGradient>"## +
            ##"<radialGradient id="mc" cx="0.35" cy="0.25" r="0.9"><stop offset="0" stop-color="#a16207"/><stop offset="0.55" stop-color="#5b3416"/><stop offset="1" stop-color="#2a1608"/></radialGradient>"## +
            ##"<radialGradient id="mq" cx="0.35" cy="0.3" r="0.85"><stop offset="0" stop-color="#fff1f5"/><stop offset="0.55" stop-color="#f9a8d4"/><stop offset="1" stop-color="#db2777"/></radialGradient>"## +
            ##"<linearGradient id="md" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\##(accent)"/><stop offset="1" stop-color="\##(dark)"/></linearGradient>"##
        var defs = "<defs>"
        defs += ##"<radialGradient id="mb" cx="0.36" cy="0.28" r="0.85"><stop offset="0" stop-color="\##(light)"/><stop offset="0.5" stop-color="\##(accent)"/><stop offset="1" stop-color="\##(dark)"/></radialGradient>"##
        defs += ##"<linearGradient id="ma" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\##(light)"/><stop offset="1" stop-color="\##(dark)"/></linearGradient>"##
        defs += ##"<radialGradient id="mh" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="\##(light)"/><stop offset="0.6" stop-color="\##(accent)"/><stop offset="1" stop-color="\##(dark)"/></radialGradient>"##
        defs += ##"<linearGradient id="mm" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e2e8f0"/><stop offset="1" stop-color="#94a3b8"/></linearGradient>"##
        defs += ##"<radialGradient id="me" cx="0.4" cy="0.3" r="0.8"><stop offset="0" stop-color="#ffffff"/><stop offset="0.75" stop-color="#f3f5f9"/><stop offset="1" stop-color="#c9d0dc"/></radialGradient>"##
        defs += ##"<linearGradient id="ml" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\##(light)"/><stop offset="1" stop-color="\##(accent)"/></linearGradient>"##
        defs += ##"<radialGradient id="ms" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#0f172a" stop-opacity="0.32"/><stop offset="1" stop-color="#0f172a" stop-opacity="0"/></radialGradient>"##
        if industry { defs += paints }
        defs += ##"<linearGradient id="mj" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="\##(mixColor(accent, 82, "#ffffff"))"/><stop offset="0.5" stop-color="\##(accent)"/><stop offset="1" stop-color="\##(mixColor(accent, 78, "#000000"))"/></linearGradient>"##
        defs += ##"<radialGradient id="mp" cx="0.5" cy="0.5" r="0.5"><stop offset="0.5" stop-color="#0b1020"/><stop offset="1" stop-color="\##(mixColor(accentIn, 45, "#0b1020"))"/></radialGradient>"##
        defs += "</defs>"
        let (vx, vy, vw, vh) = viewBox(bust: bust)
        let head = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="\##(n(vx)) \##(n(vy)) \##(n(vw)) \##(n(vh))">"##
        func svg(_ inner: String) -> String { head + defs + inner + "</svg>" }
        func opt(_ inner: String) -> String? { inner.isEmpty ? nil : svg(inner) }

        // ---- Eyes (drawn at y 52, moved and scaled into place) ----
        func eyeAt(_ cx: Double, _ x: Double, _ inner: String) -> String {
            inner.isEmpty ? "" : ##"<g transform="translate(\##(n(x)) \##(n(ey))) scale(\##(n(es))) translate(\##(n(-cx)) -52)">"## + inner + "</g>"
        }
        func pupil(_ cx: Double) -> String {
            if eyes == "happy" {
                return ##"<path d="M\##(n(cx - 6.5)) 56 Q\##(n(cx)) 46 \##(n(cx + 6.5)) 56" fill="none" stroke="\##(pupilInk)" stroke-width="3.4" stroke-linecap="round"/>"##
            }
            if eyes == "star" {
                return ##"<path d="M\##(n(cx + 1)) 46.5 L\##(n(cx + 2.9)) 51.6 L\##(n(cx + 8.2)) 52 L\##(n(cx + 4.1)) 55.4 L\##(n(cx + 5.4)) 60.6 L\##(n(cx + 1)) 57.7 L\##(n(cx - 3.4)) 60.6 L\##(n(cx - 2.1)) 55.4 L\##(n(cx - 6.2)) 52 L\##(n(cx - 0.9)) 51.6 Z" fill="\##(pupilInk)"/>"## +
                    ##"<circle cx="\##(n(cx - 0.6))" cy="52.6" r="1.4" fill="#fde68a"/>"##
            }
            if led {
                return ##"<ellipse cx="\##(n(cx))" cy="53" rx="5.4" ry="7.2" fill="\##(pupilInk)"/><ellipse cx="\##(n(cx - 1.4))" cy="50" rx="1.6" ry="2.4" fill="#fff" opacity="0.8"/>"##
            }
            let r = whites ? 6.2 : 7.4
            return ##"<circle cx="\##(n(cx + 1))" cy="54" r="\##(n(r))" fill="url(#mp)"/>"## +
                ##"<path d="M\##(n(cx + 1 - r * 0.62)) \##(n(54 + r * 0.42)) Q\##(n(cx + 1)) \##(n(54 + r * 0.92)) \##(n(cx + 1 + r * 0.62)) \##(n(54 + r * 0.42))" fill="none" stroke="#fff" stroke-width="\##(n(r * 0.16))" stroke-linecap="round" opacity="0.28"/>"## +
                ##"<ellipse cx="\##(n(cx - 1.2))" cy="51.2" rx="\##(whites ? "2.5" : "2.9")" ry="\##(whites ? "2.2" : "2.6")" fill="#fff" transform="rotate(-20 \##(n(cx - 1.2)) 51.2)"/>"## +
                ##"<circle cx="\##(n(cx + 2.6))" cy="57" r="0.9" fill="#fff" opacity="0.85"/>"##
        }
        let lidFill = led ? "#0b1020" : "url(#ml)"
        func white(_ cx: Double) -> String {
            (whites && eyes != "happy"
                ? ##"<ellipse cx="\##(n(cx))" cy="52" rx="9.5" ry="11.5" fill="url(#me)" stroke="\##(dark)" stroke-width="0.8" stroke-opacity="0.35"/><path d="M\##(n(cx - 8)) 46 Q\##(n(cx)) 38.5 \##(n(cx + 8)) 46" fill="none" stroke="\##(dark)" stroke-width="1.6" stroke-linecap="round" opacity="0.14"/>"##
                : "") +
                // The LED's glow, without its blur.
                (led ? ##"<ellipse cx="\##(n(cx))" cy="53" rx="8" ry="10" fill="\##(ledInk)" opacity="0.2"/>"## : "")
        }
        func sleepy(_ cx: Double) -> String {
            eyes == "sleepy"
                ? ##"<path d="M\##(n(cx - 10.5)) 50 Q\##(n(cx)) 38 \##(n(cx + 10.5)) 50 L\##(n(cx + 10.5)) 40 L\##(n(cx - 10.5)) 40 Z" fill="\##(lidFill)"/><path d="M\##(n(cx - 9.5)) 50 Q\##(n(cx)) 53 \##(n(cx + 9.5)) 50" fill="none" stroke="\##(led ? ledInk : dark)" stroke-width="1.6" stroke-linecap="round"/>"##
                : ""
        }
        func lid(_ cx: Double) -> String { ##"<rect x="\##(n(cx - 11))" y="39" width="22" height="26" rx="10" fill="\##(lidFill)"/>"## }
        func both(_ f: (Double) -> String) -> String { eyeAt(37, ex1, f(37)) + eyeAt(63, ex2, f(63)) }
        let shades = eyes == "shades"
            ? ##"<g transform="translate(0 \##(n(ey - 52)))"><rect x="\##(n(ex1 - 13))" y="43" width="25" height="18" rx="7" fill="#0b1020"/><rect x="\##(n(ex2 - 12))" y="43" width="25" height="18" rx="7" fill="#0b1020"/>"## +
                ##"<path d="M\##(n(ex1 + 12)) 49 H\##(n(ex2 - 12))" stroke="#0b1020" stroke-width="3"/><path d="M\##(n(ex1 - 9)) 47 l7 0 M\##(n(ex2 - 8)) 47 l7 0" stroke="#fff" stroke-width="2.2" stroke-linecap="round" opacity="0.7"/></g>"##
            : ""

        // ---- Arms ----
        let limbW = sp.limbs == "nub" ? 9.0 : 13.0
        let metal = sp.limbs == "metal"
        let limbPaint = metal ? "url(#mm)" : "url(#mj)"
        let limbEdge = metal ? "#64748b" : dark
        let handPaint = metal ? "url(#mm)" : "url(#mh)"
        let hs = sp.limbs == "nub" ? 0.78 : 1
        func mitten(_ cx: Double, _ cy: Double, _ r0: Double, _ rot: Double, rim: Bool = false) -> String {
            let r = r0 * hs
            // A light rim on a hand that reaches out, so it reads against the body.
            let edge = rim ? ##" stroke="\##(light)" stroke-width="1.6""## : ##" stroke="\##(limbEdge)" stroke-width="0.8" stroke-opacity="0.55""##
            return ##"<g transform="rotate(\##(n(rot)) \##(n(cx)) \##(n(cy)))"><ellipse cx="\##(n(cx))" cy="\##(n(cy))" rx="\##(n(r))" ry="\##(n(r * 1.08))" fill="\##(handPaint)""## + edge + "/>" +
                (sp.limbs == "nub" ? "" : ##"<ellipse cx="\##(n(cx - r * 0.72))" cy="\##(n(cy + r * 0.25))" rx="\##(n(r * 0.38))" ry="\##(n(r * 0.5))" fill="\##(handPaint)""## + edge + ##" transform="rotate(-25 \##(n(cx - r * 0.72)) \##(n(cy + r * 0.25)))"/>"##) +
                ##"<ellipse cx="\##(n(cx - r * 0.3))" cy="\##(n(cy - r * 0.4))" rx="\##(n(r * 0.35))" ry="\##(n(r * 0.22))" fill="#fff" opacity="0.6"/></g>"##
        }
        func limb(_ d: String, _ extra: Double = 0) -> String {
            ##"<path d="\##(d)" fill="none" stroke="\##(limbEdge)" stroke-width="\##(n(limbW + extra + 1.4))" stroke-linecap="round" stroke-opacity="0.6"/>"## +
                ##"<path d="\##(d)" fill="none" stroke="\##(limbPaint)" stroke-width="\##(n(limbW + extra))" stroke-linecap="round"/>"## +
                ##"<path d="\##(d)" fill="none" stroke="#fff" stroke-width="\##(n((limbW + extra) * 0.22))" stroke-linecap="round" opacity="0.3" transform="translate(-0.8 -1.2)"/>"##
        }
        func armArt(_ a: String) -> String {
            switch a {
            case "whisper": return limb("M79 70 Q80 79 71 77") + mitten(65, 74, 8, 35)
            case "wave": return limb("M79 62 Q88 54 90 44") + mitten(92, 35, 9.5, 12)
            // A short, chunky arm and a big paw: reaching to tap, and a fist that knocks.
            case "reach": return limb("M78 66 Q88 63 96 61", 2) + mitten(102, 60, 11.5, 90, rim: true)
            case "knock": return limb("M78 67 Q88 69 92 62", 2) + mitten(96, 57, 12, 60, rim: true)
            default: return limb("M79 66 Q88 72 89 80") + mitten(90, 84, 8.5, -10)
            }
        }
        let armInFront = arm == "whisper" || arm == "knock" || arm == "reach"
        let leftArm = bust ? "" : limb("M22 68 Q12 74 13 82") + mitten(13, 84, 7.5, 10)

        // ---- What it wears ----
        var wear = ""
        switch accessory {
        case "headset":
            wear = ##"<path d="M13 58 C12 24 88 24 87 58" fill="none" stroke="#1f2937" stroke-width="5" stroke-linecap="round"/>"## +
                ##"<rect x="5" y="50" width="13" height="20" rx="6" fill="#1f2937"/><rect x="82" y="50" width="13" height="20" rx="6" fill="#1f2937"/>"## +
                ##"<path d="M88 67 C88 80 78 84 66 82" fill="none" stroke="#1f2937" stroke-width="3" stroke-linecap="round"/>"## +
                ##"<circle cx="64" cy="82" r="3.6" fill="#374151"/>"##
        case "bow":
            wear = ##"<g transform="rotate(18 72 24)"><path d="M72 24 L56 14 L57 34 Z M72 24 L88 14 L87 34 Z" fill="#f472b6"/>"## +
                ##"<path d="M60 18 L61 30 M84 18 L83 30" stroke="#fff" stroke-width="1.6" opacity="0.55" stroke-linecap="round"/>"## +
                ##"<rect x="67.5" y="19.5" width="9" height="9" rx="3" fill="#ec4899"/></g>"##
        case "cap":
            wear = ##"<path d="M20 36 C22 12 78 12 80 36 Z" fill="#1f2937"/><path d="M70 34 C84 32 97 34 99 38 C92 41 80 40 70 38 Z" fill="#111827"/>"## +
                ##"<circle cx="50" cy="16" r="2.6" fill="#374151"/><path d="M34 20 C40 16 46 15 50 15" stroke="#fff" stroke-width="2" opacity="0.25" fill="none" stroke-linecap="round"/>"##
        case "crown":
            wear = ##"<path d="M31 24 L33 6 L42 16 L50 3 L58 16 L67 6 L69 24 Z" fill="#facc15" stroke="#ca8a04" stroke-width="1.5" stroke-linejoin="round"/>"## +
                ##"<circle cx="50" cy="18" r="2.6" fill="#ef4444"/><circle cx="39" cy="20" r="1.8" fill="#3b82f6"/><circle cx="61" cy="20" r="1.8" fill="#22c55e"/>"##
        case "flower":
            let petals = [0, 72, 144, 216, 288].map { ##"<ellipse cx="27" cy="18" rx="5" ry="8" fill="#fb7185" transform="rotate(\##($0) 27 26)"/>"## }.joined()
            wear = "<g>" + petals + ##"<circle cx="27" cy="26" r="4.4" fill="#fde047"/></g>"##
        case "glasses":
            wear = ##"<g transform="translate(0 \##(n(ey - 52)))"><circle cx="\##(n(ex1))" cy="52" r="\##(n(12.5 * es))" fill="#fff" fill-opacity="0.12" stroke="#1f2937" stroke-width="3"/>"## +
                ##"<circle cx="\##(n(ex2))" cy="52" r="\##(n(12.5 * es))" fill="#fff" fill-opacity="0.12" stroke="#1f2937" stroke-width="3"/>"## +
                ##"<path d="M\##(n(ex1 + 12.5 * es)) 50 Q50 47 \##(n(ex2 - 12.5 * es)) 50" stroke="#1f2937" stroke-width="3" fill="none"/></g>"##
        default:
            break
        }

        let mouthInk = sp.mouthInk ?? "#1e1b2e"
        let smile = sp.smile ?? "M42 72 Q50 80 58 72"
        // The cheeks' soft glow without its blur: a touch lighter.
        let cheeks = sp.cheeks == false ? ""
            : ##"<g transform="translate(0 \##(n(ey - 52)))"><ellipse cx="25" cy="70" rx="6" ry="3.6" fill="#fb7185" opacity="0.4"/><ellipse cx="75" cy="70" rx="6" ry="3.6" fill="#fb7185" opacity="0.4"/>"## +
                ##"<ellipse cx="23" cy="68.6" rx="1.7" ry="1" fill="#fff" opacity="0.5"/><ellipse cx="73" cy="68.6" rx="1.7" ry="1" fill="#fff" opacity="0.5"/></g>"##
        // Characters without brows keep an invisible one: the performances raise it.
        let brows = ##"<path d="M\##(n(ex1 - 8)) \##(n(ey - 16)) q8 -5 15 -1 M\##(n(ex2 - 7)) \##(n(ey - 17)) q7 -4 15 1" fill="none" stroke="\##(dark)" stroke-width="2.6" stroke-linecap="round""## + (sp.brows == false ? ##" opacity="0""## : "") + "/>"
        let shadowRx = sp.shadow ?? 32
        let shadowY = shape == "ghost" ? 99.0 : 95.0
        func mouth(_ inner: String) -> String { ##"<g transform="translate(0 \##(n(my)))">"## + inner + "</g>" }

        let body = leftArm + (sp.behind ?? "") + sp.body +
            // The shine (without the web's glow blur).
            ##"<path d="M22 80 C32 90 68 90 78 80" fill="none" stroke="\##(light)" stroke-width="3" stroke-linecap="round" opacity="0.3"/>"## +
            ##"<path d="M24 38 C30 28 40 23 50 23" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity="0.4"/>"## +
            ##"<ellipse cx="35" cy="33" rx="8" ry="4.5" fill="#fff" opacity="0.55" transform="rotate(-28 35 33)"/>"## +
            (sp.under ?? "") + both(white)

        return Layers(
            shadow: bust ? nil : svg(##"<ellipse cx="50" cy="\##(n(shadowY))" rx="\##(n(shadowRx))" ry="5" fill="url(#ms)"/><ellipse cx="50" cy="\##(n(shadowY))" rx="\##(n(shadowRx * 0.55))" ry="2.2" fill="url(#ms)" opacity="0.7"/>"##),
            tail: bust ? nil : opt(sp.tail ?? ""),
            armBack: bust || armInFront ? nil : svg(armArt(arm)),
            body: svg(body),
            look: svg(both(pupil)),
            face: opt(both(sleepy)),
            lids: svg(both(lid)),
            cover: opt(shades + cheeks),
            brows: svg(brows),
            armFront: bust || !armInFront ? nil : svg(armArt(arm)),
            smile: svg(mouth(##"<path d="\##(smile)" fill="none" stroke="\##(mouthInk)" stroke-width="2.6" stroke-linecap="round"/>"##)),
            o: svg(mouth(##"<ellipse cx="50" cy="74" rx="3.4" ry="4" fill="#3b1d2e"/>"##)),
            grin: svg(mouth(##"<path d="M40 70 Q50 84 60 70 Z" fill="\##(led ? mouthInk : "#3b1d2e")"/>"## + (led ? "" : ##"<path d="M44 76 Q50 80 56 76 Q50 83 44 76 Z" fill="#fb7185"/>"##))),
            top: opt((sp.over ?? "") + wear))
    }
}
