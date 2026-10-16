//
//  Keyframes.swift
//  Conferbot
//
//  Web Animations, evaluated: the launcher's entrance, attention and idle
//  call (conferbot-widget src/ts/launcher/entrance.ts, attention.ts,
//  idleCall.ts) are element.animate() calls on the individual translate /
//  scale / rotate properties and opacity. Their keyframes are kept here as
//  the web wrote them, and this works out each property at time t the way
//  the browser does:
//
//    - offsets: a keyframe without one is spaced evenly between its
//      neighbours (the first defaults to 0, the last to 1);
//    - per property, only the keyframes that set it count; a missing 0% or
//      100% keyframe is the element's own value (the step from a missing 0%
//      eases with the 0% keyframe's easing, as Chrome plays it);
//    - each keyframe's `easing` eases the step that starts at it; the
//      options' easing eases the whole iteration first;
//    - delay, iterations (infinity loops) and fill (forwards / backwards /
//      both; none: the element's own value outside the animation);
//    - several animations on one element: the later one wins for the
//      properties it sets.
//
//  The same algorithm as the React Native SDK's core/keyframes.ts, which is
//  checked against Chrome's own animations frame by frame
//  (scripts/parity/launcherfx); Tests/Resources/launcherfx-golden.json is
//  that golden. Pure.
//

import Foundation

/// One keyframe, as the web passes it to element.animate(): `offset`, `easing` and the properties (strings or numbers).
public typealias Keyframe = [String: Any]

public struct TrackOptions {
    public var duration: Double
    public var delay: Double = 0
    /// `.infinity` loops forever.
    public var iterations: Double = 1
    public var easing: String?
    /// none, forwards, backwards, both, auto.
    public var fill: String = "none"
}

/// One animation: its keyframes and options. `part` names what it moves (attention).
public final class Track {
    public let keyframes: [Keyframe]
    public let options: TrackOptions
    public let part: String?

    public init(_ keyframes: [Keyframe], _ options: TrackOptions, part: String? = nil) {
        self.keyframes = keyframes
        self.options = options
        self.part = part
    }

    /// A track built as the web writes `{ duration, delay?, iterations?, easing?, fill? }`.
    public static func of(_ keyframes: [Keyframe], duration: Double, delay: Double? = nil, iterations: Double? = nil,
                          easing: String? = nil, fill: String? = nil, part: String? = nil) -> Track {
        Track(keyframes, TrackOptions(duration: duration, delay: delay ?? 0, iterations: iterations ?? 1, easing: easing, fill: fill ?? "none"), part: part)
    }

    /// The same track, its delay changed.
    public func withDelay(_ delay: Double) -> Track {
        var o = options
        o.delay = delay
        return Track(keyframes, o, part: part)
    }

    lazy var compiled: Keyframes.Compiled = Keyframes.compile(self)

    /// From the golden's JSON (iterations -1 = infinity).
    public static func fromJson(_ j: [String: Any]) -> Track {
        let o = j["options"] as? [String: Any] ?? [:]
        let it = Keyframes.number(o["iterations"])
        return Track(
            (j["keyframes"] as? [[String: Any]]) ?? [],
            TrackOptions(
                duration: Keyframes.number(o["duration"]) ?? 0,
                delay: Keyframes.number(o["delay"]) ?? 0,
                iterations: it == nil ? 1 : (it == -1 ? .infinity : it!),
                easing: o["easing"] as? String,
                fill: (o["fill"] as? String) ?? "none"),
            part: j["part"] as? String)
    }
}

/// An element's values at a moment (the channels of `Keyframes.channels`).
public struct FxValues {
    var v: [Double]

    public subscript(ch: String) -> Double {
        get { v[Keyframes.index[ch]!] }
        set { v[Keyframes.index[ch]!] = newValue }
    }

    public var tx: Double { v[0] }
    public var ty: Double { v[1] }
    public var txp: Double { v[2] }
    public var typ: Double { v[3] }
    public var sx: Double { v[4] }
    public var sy: Double { v[5] }
    public var r: Double { v[6] }
    public var rx: Double { v[7] }
    public var ry: Double { v[8] }
    public var o: Double { v[9] }
    public var od: Double { v[10] }
    public var dash: Double { v[11] }
    public var clip: Double { v[12] }
    public var left: Double { v[13] }

    /// At rest, with `base` (the element's own values) over it.
    public static func rest(_ base: [String: Double]? = nil) -> FxValues {
        var out = FxValues(v: Keyframes.restValues)
        for (k, x) in base ?? [:] { out[k] = x }
        return out
    }
}

public enum Keyframes {
    /// The animated channels: translate in px (tx, ty) plus a share of the
    /// element's own box (txp, typ, in %), scale, rotate about z (r) and the
    /// 3D turns (rx, ry) in degrees, opacity, offset-distance (od, %),
    /// stroke-dashoffset (dash), clip-path inset from the bottom (clip, %)
    /// and `left` (%).
    public static let channels = ["tx", "ty", "txp", "typ", "sx", "sy", "r", "rx", "ry", "o", "od", "dash", "clip", "left"]
    static let restValues: [Double] = [0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0]
    static let index: [String: Int] = Dictionary(uniqueKeysWithValues: channels.enumerated().map { ($1, $0) })

    private static let ease: [String: [Double]] = [
        "linear": [0, 0, 1, 1],
        "ease": [0.25, 0.1, 0.25, 1],
        "ease-in": [0.42, 0, 1, 1],
        "ease-out": [0, 0, 0.58, 1],
        "ease-in-out": [0.42, 0, 0.58, 1],
    ]
    private static let linear: [Double] = [0, 0, 1, 1]

    // MARK: - Small helpers (regexes, JS numbers)

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    static func regex(_ p: String) -> NSRegularExpression {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let r = regexCache[p] { return r }
        let r = try! NSRegularExpression(pattern: p)
        regexCache[p] = r
        return r
    }

    /// The groups of the first match (group 0 the whole match; "" for a group that took no part), or nil.
    static func firstMatch(_ p: String, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = regex(p).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    /// The groups of every match.
    static func allMatches(_ p: String, _ s: String) -> [[String]] {
        let ns = s as NSString
        return regex(p).matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    /// The string split on a regex.
    static func split(_ s: String, _ p: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var at = 0
        for m in regex(p).matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            at = m.range.location + m.range.length
        }
        out.append(ns.substring(from: at))
        return out
    }

    /// A number in a keyframe or JSON (Int, Double, NSNumber), or nil.
    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    /// A CSS easing as cubic-bezier control points (unknown: linear).
    public static func easingOf(_ e: String?) -> [Double] {
        guard let e = e else { return linear }
        let s = e.trimmingCharacters(in: .whitespaces)
        if let k = ease[s] { return k }
        if let m = firstMatch("^cubic-bezier\\(([^)]*)\\)$", s) {
            let n = m[1].components(separatedBy: ",").map { jsParseFloat($0) }
            if n.count == 4 && n.allSatisfy({ $0.isFinite }) { return n }
        }
        return linear
    }

    private static func isLinear(_ e: [Double]) -> Bool { e[0] == 0 && e[1] == 0 && e[2] == 1 && e[3] == 1 }
    private static func apply(_ e: [Double], _ x: Double) -> Double { isLinear(e) ? x : LauncherMotion.cubicBezier(e, x) }

    /// JavaScript's parseFloat: the leading number of a string (NaN when none).
    public static func jsParseFloat(_ v: Any?) -> Double {
        if let n = number(v) { return n }
        guard let m = firstMatch("^\\s*([+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?)", (v as? String) ?? "") else { return .nan }
        return Double(m[1]) ?? .nan
    }

    /// A number as JavaScript prints it (`${n}`): 1 not 1.0, -0 as 0, no exponent for everyday sizes.
    public static func jsNum(_ d: Double) -> String {
        if d == 0 { return "0" }
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        let s = "\(d)"
        let a = abs(d)
        if s.contains("e") && a >= 1e-6 && a < 1e21 {
            // Swift writes 1e-05 where JavaScript writes 0.00001.
            if let dec = Decimal(string: s) { return "\(dec)" }
        }
        // Swift pads the exponent (1e-07); JavaScript does not (1e-7).
        if let e = s.firstIndex(of: "e"), let x = Int(s[s.index(after: e)...]) {
            return "\(s[..<e])e\(x < 0 ? "-" : "+")\(abs(x))"
        }
        return s
    }

    /// JavaScript's x.toFixed(d), back to a number as JS prints it (halves away from zero, on the exact binary value).
    public static func fixed(_ x: Double, _ d: Int) -> String {
        guard x.isFinite else { return jsNum(x) }
        let a = abs(x)
        var s = String(format: "%.\(d)f", a)
        // printf breaks an exact tie to even; toFixed takes the larger.
        let exact = String(format: "%.60f", a)
        if let dot = exact.firstIndex(of: ".") {
            let frac = exact[exact.index(after: dot)...]
            if frac.count > d {
                let next = frac[frac.index(frac.startIndex, offsetBy: d)]
                let rest = frac[frac.index(frac.startIndex, offsetBy: d + 1)...]
                if next == "5" && rest.allSatisfy({ $0 == "0" }) {
                    let p = pow(10.0, Double(d))
                    s = String(format: "%.\(d)f", (a * p).rounded(.down) / p + 1 / p)
                }
            }
        }
        let v = Double(s) ?? a
        return jsNum(x < 0 ? -v : v)
    }

    private static let groups = ["translate", "scale", "rotate", "opacity", "offsetDistance", "strokeDashoffset", "clipPath", "left", "transform"]
    private static let channelsOf: [String: [String]] = [
        "translate": ["tx", "ty", "txp", "typ"],
        "scale": ["sx", "sy"],
        "rotate": ["r", "rx", "ry"],
        "opacity": ["o"],
        "offsetDistance": ["od"],
        "strokeDashoffset": ["dash"],
        "clipPath": ["clip"],
        "left": ["left"],
        // Only "scaleY(n)" is used (the eyelids): it is the scale's y.
        "transform": ["sy"],
    ]

    /// "12px", "-160%", "0", "calc(10% + 4px)": (px, %).
    private static func length(_ v: String) -> (Double, Double) {
        let s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("calc(") {
            var px = 0.0, pc = 0.0
            let inner = String(s.dropFirst(5).dropLast())
            for m in allMatches("([+-]?)\\s*([\\d.]+)(px|%)", inner) {
                let x = (m[1] == "-" ? -1.0 : 1.0) * (Double(m[2]) ?? 0)
                if m[3] == "%" { pc += x } else { px += x }
            }
            return (px, pc)
        }
        let n = jsParseFloat(s)
        if !n.isFinite { return (0, 0) }
        return s.hasSuffix("%") ? (0, n) : (n, 0)
    }

    private static func str(_ v: Any) -> String {
        if let n = number(v) { return jsNum(n) }
        return "\(v)"
    }

    /// One keyframe's value for a group, or nil when it does not set it.
    private static func parse(_ k: Keyframe, _ g: String) -> [String: Double]? {
        guard let v = k[g], !(v is NSNull) else { return nil }
        let s = str(v).trimmingCharacters(in: .whitespaces)
        switch g {
        case "translate":
            // Split on spaces outside calc().
            let parts = split(s, "\\s+(?![^(]*\\))")
            let x = length(!parts.isEmpty && !parts[0].isEmpty ? parts[0] : "0")
            let y = length(parts.count > 1 ? parts[1] : "0")
            return ["tx": x.0, "txp": x.1, "ty": y.0, "typ": y.1]
        case "scale":
            let parts = split(s, "\\s+").map { jsParseFloat($0) }
            return ["sx": parts[0], "sy": parts.count > 1 ? parts[1] : parts[0]]
        case "rotate":
            // "45deg", "y 180deg", "x 80deg".
            let m = firstMatch("^(?:([xyz])\\s+)?(-?[\\d.]+)deg$", s)
            var a: Double
            if let m = m { a = Double(m[2]) ?? 0 } else { a = jsParseFloat(s); if a.isNaN { a = 0 } }
            let axis = (m?[1]).flatMap { $0.isEmpty ? nil : $0 } ?? "z"
            return ["r": axis == "z" ? a : 0, "rx": axis == "x" ? a : 0, "ry": axis == "y" ? a : 0]
        case "opacity":
            return ["o": number(v) ?? jsParseFloat(s)]
        case "offsetDistance":
            return ["od": jsParseFloat(s)]
        case "strokeDashoffset":
            return ["dash": number(v) ?? jsParseFloat(s)]
        case "clipPath":
            // inset(top right bottom left): the bottom inset, in %.
            let p = (firstMatch("inset\\(([^)]*)\\)", s)?[1]).map { split($0.trimmingCharacters(in: .whitespaces), "\\s+") } ?? []
            let b = p.count >= 3 ? jsParseFloat(p[2]) : 0
            return ["clip": b.isNaN ? 0 : b]
        case "left":
            return ["left": jsParseFloat(s)]
        case "transform":
            return firstMatch("scaleY\\(([^)]*)\\)", s).map { ["sy": jsParseFloat($0[1])] }
        default:
            return nil
        }
    }

    /// Offsets as the browser computes them: missing ones spaced evenly between their neighbours.
    public static func computedOffsets(_ kfs: [Keyframe]) -> [Double] {
        var out: [Double?] = kfs.map { number($0["offset"]) }
        if out.count == 1 && out[0] == nil { out[0] = 1 }
        if out.count > 1 {
            if out[0] == nil { out[0] = 0 }
            if out[out.count - 1] == nil { out[out.count - 1] = 1 }
        }
        var i = 0
        while i < out.count {
            if out[i] != nil { i += 1; continue }
            let a = i - 1
            var b = i
            while out[b] == nil { b += 1 }
            let from = out[a]!, to = out[b]!
            for j in (a + 1)..<b { out[j] = from + ((to - from) * Double(j - a)) / Double(b - a) }
            i = b
        }
        return out.map { $0! }
    }

    /// The iteration progress (0...1, eased by the options' easing) at t ms, or nil when the animation does not apply.
    public static func iterationProgress(_ o: TrackOptions, _ t: Double) -> Double? {
        let dur = o.duration
        let iterations = o.iterations
        let active = iterations == .infinity ? Double.infinity : dur * iterations
        let local = t - o.delay
        let p: Double
        if local < 0 {
            if o.fill != "backwards" && o.fill != "both" { return nil }
            p = 0
        } else if local >= active {
            if o.fill != "forwards" && o.fill != "both" { return nil }
            // Ended on a whole iteration: its end (1), else where it stopped.
            let whole = iterations - iterations.rounded(.down)
            p = iterations > 0 && whole == 0 ? 1 : whole
        } else {
            if dur <= 0 { return nil }
            p = local.truncatingRemainder(dividingBy: dur) / dur
        }
        return apply(easingOf(o.easing), p)
    }

    struct Pt {
        var at: Double
        var v: [String: Double]?
        var e: [Double]
    }

    struct Group {
        var name: String
        var pts: [Pt]
        var firstEase: [Double]
    }

    struct Compiled {
        var groups: [Group]
    }

    static func compile(_ track: Track) -> Compiled {
        let kfs = track.keyframes
        let offs = computedOffsets(kfs)
        let first = offs.firstIndex(of: 0)
        let firstEase = first.map { easingOf(kfs[$0]["easing"] as? String) } ?? linear
        var out: [Group] = []
        for g in groups {
            var pts: [Pt] = []
            for i in kfs.indices {
                if let v = parse(kfs[i], g) { pts.append(Pt(at: offs[i], v: v, e: easingOf(kfs[i]["easing"] as? String))) }
            }
            if !pts.isEmpty { out.append(Group(name: g, pts: pts, firstEase: firstEase)) }
        }
        return Compiled(groups: out)
    }

    /// One track's values at t ms: only the channels it animates, or nil when it does not apply.
    public static func trackValues(_ track: Track, _ t: Double, base: FxValues? = nil) -> [String: Double]? {
        let b = base ?? FxValues.rest()
        guard let p = iterationProgress(track.options, t) else { return nil }
        let c = track.compiled
        if c.groups.isEmpty { return nil }
        var out: [String: Double] = [:]
        for grp in c.groups {
            let chs = channelsOf[grp.name]!
            let parsed = grp.pts
            // A missing 0% or 100% keyframe is the element's own value (nil here); a missing 0% eases with the 0% keyframe's easing.
            var pts: [Pt] = []
            if parsed.first!.at != 0 { pts.append(Pt(at: 0, v: nil, e: grp.firstEase)) }
            pts.append(contentsOf: parsed)
            if parsed.last!.at != 1 { pts.append(Pt(at: 1, v: nil, e: linear)) }
            // The interval: the last keyframe at or before p (and before 1), and the next.
            var s = -1
            for i in pts.indices where pts[i].at <= p && pts[i].at < 1 { s = i }
            if s < 0 { for i in pts.indices where pts[i].at == 0 { s = i } }
            func at(_ x: Pt, _ ch: String) -> Double { x.v?[ch] ?? b[ch] }
            if p >= 1 && pts.filter({ $0.at == 1 }).count > 1 {
                for ch in chs { out[ch] = at(pts.last!, ch) }
            } else if s < 0 || s >= pts.count - 1 {
                let x = pts[max(0, min(pts.count - 1, s))]
                for ch in chs { out[ch] = at(x, ch) }
            } else {
                let a = pts[s], z = pts[s + 1]
                let span = z.at - a.at
                let local = span > 0 ? apply(a.e, (p - a.at) / span) : 1
                for ch in chs {
                    let va = at(a, ch), vb = at(z, ch)
                    out[ch] = va + (vb - va) * local
                }
            }
        }
        // The computed opacity is clamped (an overshooting easing goes past 1).
        if let o = out["o"] { out["o"] = min(1, max(0, o)) }
        return out
    }

    /// An element's values at t ms under its animations, in order (the later wins), over its own `base`.
    public static func evaluate(_ tracks: [Track], _ t: Double, base: [String: Double]? = nil) -> FxValues {
        let b = FxValues.rest(base)
        var out = b
        for tr in tracks {
            if let vals = trackValues(tr, t, base: b) { for (k, x) in vals { out[k] = x } }
        }
        return out
    }

    /// When a set of tracks is over (ms; infinity when one loops forever).
    public static func tracksEnd(_ tracks: [Track]) -> Double {
        tracks.reduce(0) { max($0, $1.options.delay + $1.options.duration * $1.options.iterations) }
    }

    /// Every option, defaults filled in, infinity as -1 (the golden's form, normalised).
    public static func toJson(_ t: Track) -> [String: Any] {
        let o = t.options
        var m: [String: Any] = [:]
        if let p = t.part { m["part"] = p }
        m["keyframes"] = t.keyframes.map { $0.filter { !($0.value is NSNull) } }
        m["options"] = [
            "duration": o.duration,
            "delay": o.delay,
            "iterations": o.iterations == .infinity ? -1.0 : o.iterations,
            "easing": o.easing ?? "linear",
            "fill": o.fill,
        ] as [String: Any]
        return m
    }
}
