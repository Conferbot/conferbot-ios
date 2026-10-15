//
//  LauncherMotion.swift
//  Conferbot
//
//  The launcher's motion as the web widget plays it (conferbot-widget
//  src/svg/launcher/motion.ts and ts/launcher/launcherMotion.ts):
//
//    - which parts of an icon move, and how, at a moment of an "idle" or
//      "msg" (new message) moment: iconFrame() evaluates the CSS keyframes,
//      easing, delays, iterations and fill modes at time t;
//    - when the moments play: nextIdleDelay();
//    - the ripple: rippleRing().
//
//  Pure: the launcher view drives the clock. The same algorithm as the React
//  Native SDK's core/launcherMotion.ts, which is checked frame by frame
//  against Chrome's own animation of the web icons.
//

import Foundation

public struct MotionRing: Equatable {
    public var scale: Double
    public var opacity: Double
}

/// One op mid-moment: the transform to draw it with, its clip's, and its
/// animated layers (group id, opacity), outer first.
public struct OpFrame: Equatable {
    public var m: [Double]
    public var clipM: [Double]?
    public var layers: [LayerOpacity]
}

public struct LayerOpacity: Equatable {
    public var g: Int
    public var o: Double
}

public enum LauncherMotion {
    /// How long a moment lasts (the longest keyframes are 2.4s).
    public static let momentMs = 2600.0
    /// The first idle moment, after the launcher shows.
    public static let firstIdleMs = 2000.0
    /// An opening rests the idle moments this long.
    public static let openedRestMs = 30.0 * 60 * 1000

    /// Milliseconds until the next idle moment after `played` of them, or nil when there are no more.
    public static func nextIdleDelay(_ mode: String, played: Int, random: () -> Double = { Double.random(in: 0..<1) }) -> Double? {
        if mode == "off" { return nil }
        let lively = mode == "lively"
        let every = lively ? 20000.0 : 30000.0, jitter = lively ? 8000.0 : 0, plays = lively ? 10 : 4
        if played <= 0 { return firstIdleMs }
        if played >= plays { return nil }
        return every + (random() * jitter).rounded()
    }

    // The ripple (polish.css cb-ripple): two rings, the second 0.6s behind, each 1.8s, three times after 2.5s.
    public static let rippleDelay = 2.5, rippleGap = 0.6, rippleDur = 1.8
    public static let rippleIter = 3

    /// A ring's scale and opacity at t seconds into the ripple (nil when it is not showing).
    public static func rippleRing(_ t: Double, ring: Int, iterations: Int = rippleIter, delay: Double = rippleDelay) -> MotionRing? {
        let lt = t - delay - Double(ring) * rippleGap
        if lt < 0 || lt >= rippleDur * Double(iterations) { return nil }
        let p = cubicBezier([0, 0, 0.2, 1], lt.truncatingRemainder(dividingBy: rippleDur) / rippleDur)
        return MotionRing(scale: 1 + 0.7 * p, opacity: 0.45 * (1 - p))
    }

    /// CSS cubic-bezier timing: the y for a given x (Newton, then bisection).
    public static func cubicBezier(_ e: [Double], _ x: Double) -> Double {
        let x1 = e[0], y1 = e[1], x2 = e[2], y2 = e[3]
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bx(_ t: Double) -> Double { 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t }
        func by(_ t: Double) -> Double { 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t }
        var t = x
        for _ in 0..<8 {
            let d = (bx(t + 1e-6) - bx(t)) / 1e-6
            if abs(d) < 1e-6 { break }
            t -= (bx(t) - x) / d
        }
        if t < 0 || t > 1 || abs(bx(t) - x) > 1e-4 {
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 {
                t = (lo + hi) / 2
                if bx(t) < x { lo = t } else { hi = t }
            }
        }
        return by(t)
    }

    // MARK: - Data

    struct Frame {
        var at: Double
        var tx: Any?, ty: Any?
        var sx: Double?, sy: Double?, r: Double?, o: Double?
        var hasTransform: Bool { tx != nil || ty != nil || sx != nil || sy != nil || r != nil }
        var usesVars: Bool { tx is String || ty is String }
    }

    struct Rule {
        var part: String, kf: String, dur: Double, delay: Double, iter: Int, ease: [Double], fill: String
    }

    struct Family {
        var idle: [Rule], msg: [Rule], awakeOpacity: [String: Double]?
    }

    private static let raw: [String: Any] = {
        (try? JSONSerialization.jsonObject(with: Data(LauncherMotionData.json.utf8))) as? [String: Any] ?? [:]
    }()

    private static func dbl(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? Double) }

    private static let keyframes: [String: [Frame]] = {
        var out: [String: [Frame]] = [:]
        for (k, v) in (raw["keyframes"] as? [String: Any]) ?? [:] {
            out[k] = ((v as? [[String: Any]]) ?? []).map { j in
                func tv(_ key: String) -> Any? { (j[key] as? String) ?? dbl(j[key]) }
                return Frame(at: dbl(j["at"]) ?? 0, tx: tv("tx"), ty: tv("ty"), sx: dbl(j["sx"]), sy: dbl(j["sy"]), r: dbl(j["r"]), o: dbl(j["o"]))
            }
        }
        return out
    }()

    private static func rules(_ v: Any?) -> [Rule] {
        ((v as? [[String: Any]]) ?? []).map { j in
            Rule(part: j["part"] as? String ?? "", kf: j["kf"] as? String ?? "", dur: dbl(j["dur"]) ?? 0, delay: dbl(j["delay"]) ?? 0,
                 iter: (j["iter"] as? NSNumber)?.intValue ?? 1, ease: ((j["ease"] as? [Any]) ?? []).compactMap(dbl), fill: j["fill"] as? String ?? "none")
        }
    }

    private static let families: [String: Family] = {
        var out: [String: Family] = [:]
        for (k, v) in (raw["families"] as? [String: Any]) ?? [:] {
            guard let j = v as? [String: Any] else { continue }
            let awake = (j["awakeOpacity"] as? [String: Any])?.compactMapValues(dbl)
            out[k] = Family(idle: rules(j["idle"]), msg: rules(j["msg"]), awakeOpacity: awake)
        }
        return out
    }()

    private static let origins: [String: [Double]] = ((raw["origins"] as? [String: Any]) ?? [:]).mapValues { (($0 as? [Any]) ?? []).compactMap(dbl) }
    private static let delays: [String: Double] = ((raw["delays"] as? [String: Any]) ?? [:]).compactMapValues(dbl)

    // MARK: - Evaluation

    /// 2x3 affine matrices [a, b, c, d, e, f].
    static let identity: [Double] = [1, 0, 0, 1, 0, 0]

    public static func mul(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[0] * b[0] + a[2] * b[1],
         a[1] * b[0] + a[3] * b[1],
         a[0] * b[2] + a[2] * b[3],
         a[1] * b[2] + a[3] * b[3],
         a[0] * b[4] + a[2] * b[5] + a[4],
         a[1] * b[4] + a[3] * b[5] + a[5]]
    }

    private static let base: [String: Double] = ["tx": 0, "ty": 0, "sx": 1, "sy": 1, "r": 0, "o": 1]

    private static func read(_ f: Frame, _ prop: String, _ dx: Double?, _ dy: Double?) -> Double? {
        let v: Any?
        switch prop {
        case "tx": v = f.tx
        case "ty": v = f.ty
        case "sx": v = f.sx
        case "sy": v = f.sy
        case "r": v = f.r
        default: v = f.o
        }
        if let s = v as? String { return s == "dx" ? (dx ?? 0) : (dy ?? 0) }
        return v as? Double
    }

    /// A property at progress p of one iteration: interpolated between the frames that set it, eased per segment.
    private static func valueAt(_ frames: [Frame], _ prop: String, _ p: Double, _ ease: [Double], _ dx: Double?, _ dy: Double?) -> Double {
        let b = base[prop] ?? 0
        var pts: [(Double, Double)] = frames.compactMap { f in read(f, prop, dx, dy).map { (f.at, $0) } }
        if pts.isEmpty { return b }
        if pts[0].0 > 0 { pts.insert((0, b), at: 0) }
        if pts[pts.count - 1].0 < 1 { pts.append((1, b)) }
        for i in 0..<(pts.count - 1) {
            let a = pts[i], c = pts[i + 1]
            if p >= a.0 && p <= c.0 {
                let span = c.0 - a.0
                let local = span > 0 ? cubicBezier(ease, (p - a.0) / span) : 1
                return a.1 + (c.1 - a.1) * local
            }
        }
        return pts[pts.count - 1].1
    }

    private static func progress(_ rule: Rule, _ t: Double) -> Double? {
        let lt = t - rule.delay
        let back = rule.fill == "backwards" || rule.fill == "both"
        let fwd = rule.fill == "forwards" || rule.fill == "both"
        if lt < 0 { return back ? 0 : nil }
        if rule.iter != -1 && lt >= rule.dur * Double(rule.iter) { return fwd ? 1 : nil }
        if rule.dur <= 0 { return nil }
        return lt.truncatingRemainder(dividingBy: rule.dur) / rule.dur
    }

    /// Each op of `icon` at t seconds into a `state` ("idle" or "msg") moment, or nil for "at rest".
    public static func iconFrame(_ icon: LauncherIcon, state: String, t: Double) -> [OpFrame?] {
        guard let fam = families[icon.anim] else { return icon.ops.map { _ in nil } }
        let rules = state == "msg" ? fam.msg : fam.idle
        let boxes = icon.boxes ?? [:]
        let awakeOpacity = state == "msg" ? fam.awakeOpacity : nil
        var cache: [Int: ([Double]?, Double?)?] = [:]

        func partFrame(_ classes: [String], _ gid: Int, _ dx: Double?, _ dy: Double?, _ unclassed: Bool) -> ([Double]?, Double?)? {
            if let hit = cache[gid] { return hit }
            var m: [Double]?
            var o: Double?
            // The cascade gives an element one animation: the last rule that matches it.
            var rule = rules.last { classes.contains($0.part) }
            if rule != nil {
                // A delay set on one of the element's own classes wins.
                for c in classes {
                    if let d = delays["\(icon.anim) \(c)"] ?? delays["* \(c)"] { rule?.delay = d }
                }
            }
            if let rule = rule, let p = progress(rule, t) {
                // A frame using --dx / --dy on an element without them is "none".
                let frames = (keyframes[rule.kf] ?? []).map { f -> Frame in
                    guard f.usesVars && (dx == nil || dy == nil) else { return f }
                    var n = f
                    n.tx = 0.0; n.ty = 0.0; n.sx = 1; n.sy = 1; n.r = 0
                    return n
                }
                func v(_ k: String) -> Double { valueAt(frames, k, p, rule.ease, dx, dy) }
                if frames.contains(where: { $0.hasTransform }) {
                    let box = unclassed ? [0.0, 0, 0, 0] : (boxes[String(gid)] ?? [0, 0, 24, 24])
                    let origin = origins["\(icon.anim) \(rule.part)"] ?? [0.5, 0.5]
                    let ox = box[0] + box[2] * origin[0]
                    let oy = box[1] + box[3] * origin[1]
                    let rad = v("r") * Double.pi / 180
                    // translate(origin) translate(tx, ty) rotate(r) scale(sx, sy) translate(-origin)
                    var n: [Double] = [1, 0, 0, 1, ox + v("tx"), oy + v("ty")]
                    n = mul(n, [cos(rad), sin(rad), -sin(rad), cos(rad), 0, 0])
                    n = mul(n, [v("sx"), 0, 0, v("sy"), 0, 0])
                    n = mul(n, [1, 0, 0, 1, -ox, -oy])
                    m = n
                }
                // CSS clamps opacity (an overshooting easing goes past 1).
                if frames.contains(where: { $0.o != nil }) { o = min(1, max(0, v("o"))) }
            }
            if o == nil, let awake = awakeOpacity {
                for c in classes { if let a = awake[c] { o = a } }
            }
            let out: ([Double]?, Double?)? = (m != nil || o != nil) ? (m, o) : nil
            cache[gid] = .some(out)
            return out
        }

        return icon.ops.map { op -> OpFrame? in
            let chain = [IconPart(c: ["cbl-r"], g: 0)] + (op.parts ?? [])
            var m = identity
            var clipM: [Double]?
            var layers: [LayerOpacity] = []
            var moved = false
            for (i, part) in chain.enumerated() {
                // The clip moves with the root and the parts down to the element that declared it.
                if op.clip != nil && i == (op.clipDepth ?? 0) + 1 { clipM = m }
                if let pre = part.pre { m = mul(m, pre) }
                let f = partFrame(part.c, part.g, part.dx, part.dy, part.u == 1)
                if f != nil { moved = true }
                // A CSS transform replaces the element's own transform attribute while it runs.
                m = mul(m, f?.0 ?? part.t ?? identity)
                if let o = f?.1 { layers.append(LayerOpacity(g: part.g, o: o)) }
            }
            if !moved { return nil }
            if op.clip != nil && clipM == nil { clipM = m }
            if let post = op.post { m = mul(m, post) }
            return OpFrame(m: m, clipM: op.clip != nil ? clipM : nil, layers: layers)
        }
    }
}
