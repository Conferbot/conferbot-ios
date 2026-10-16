import XCTest
@testable import Conferbot

/// The launcher entrance, attention and idle call, and the mascot's moods,
/// typing, greeting card and gestures, against Chrome: the React Native
/// SDK's golden (scripts/parity/launcherfx/golden.json, copied to
/// Tests/Resources/launcherfx-golden.json) holds Chrome's own values of
/// every track, paused at each sample. Each sample keeps only the channels
/// away from rest; iterations -1 is infinity. A transform list (`matrix`)
/// is read back as its CSS matrix (ma..mf).
final class LauncherFxGoldenTests: XCTestCase {
    private static let golden: [String: Any] = {
        let url = Bundle.module.url(forResource: "launcherfx-golden", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private var cases: [[String: Any]] { Self.golden["cases"] as! [[String: Any]] }

    private func num(_ m: [String: Any], _ k: String) -> Double { Keyframes.number(m[k])! }
    private func doubles(_ m: Any?) -> [String: Double] { ((m as? [String: Any]) ?? [:]).compactMapValues { Keyframes.number($0) } }

    /// Keyframes and options in one comparable form: options with their defaults filled in.
    private func norm(_ tracks: [[String: Any]]) -> [[String: Any]] {
        tracks.map { j in
            let o = j["options"] as! [String: Any]
            var out: [String: Any] = [:]
            if let p = j["part"] { out["part"] = p }
            out["keyframes"] = (j["keyframes"] as! [[String: Any]]).map { $0.filter { !($0.value is NSNull) } }
            out["options"] = [
                "duration": o["duration"]!,
                "delay": o["delay"] ?? 0,
                "iterations": o["iterations"] ?? 1,
                "easing": o["easing"] ?? "linear",
                "fill": o["fill"] ?? "none",
            ] as [String: Any]
            return out
        }
    }

    private let numberPattern = "-?\\d+(?:\\.\\d+)?(?:e[-+]?\\d+)?"

    /// Deep equality, numbers (also inside strings such as "12.5px 3px") within a hair: sin / cos can differ from V8's in the last bit.
    private func same(_ a: Any?, _ b: Any?) -> Bool {
        if let x = Keyframes.number(a), let y = Keyframes.number(b), !(a is String), !(b is String) {
            return abs(x - y) <= 1e-9 * max(1, abs(x))
        }
        if let x = a as? String, let y = b as? String {
            let rx = Keyframes.regex(numberPattern)
            func shape(_ s: String) -> String { rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "#") }
            if shape(x) != shape(y) { return false }
            let nx = Keyframes.allMatches(numberPattern, x).map { Double($0[0])! }
            let ny = Keyframes.allMatches(numberPattern, y).map { Double($0[0])! }
            return same(nx, ny)
        }
        if let x = a as? [Any], let y = b as? [Any] {
            return x.count == y.count && x.indices.allSatisfy { same(x[$0], y[$0]) }
        }
        if let x = a as? [String: Any], let y = b as? [String: Any] {
            return x.count == y.count && x.keys.allSatisfy { y[$0] != nil && same(x[$0], y[$0]) }
        }
        return false
    }

    func testEvaluatesEveryGoldenCaseWithinAHairOfChrome() {
        var worst: [String: Double] = [:]
        var samples = 0
        for c in cases {
            let tracks = (c["tracks"] as! [[String: Any]]).map { Track.fromJson($0) }
            let base = doubles(c["base"])
            let box = c["box"] as! [String: Any]
            let matrix = (c["matrix"] as? Bool) == true
            let order = tracks.isEmpty ? "trs" : Keyframes.transformOrder(tracks[0])
            for s in c["samples"] as! [[String: Any]] {
                let v = s["v"] as! [String: Any]
                let t = num(s, "t")
                let got = Keyframes.evaluate(tracks, t, base: base)
                if matrix {
                    // A transform list: its matrix, in the order the list draws it.
                    let m = Keyframes.transformMatrix(got, order)
                    let d = doubles(v)
                    for (i, ch) in ["ma", "mb", "mc", "md", "me", "mf"].enumerated() {
                        worst["matrix"] = max(worst["matrix"] ?? 0, abs(m[i] - (d[ch] ?? [1, 0, 0, 1, 0, 0][i])))
                    }
                    worst["o"] = max(worst["o"] ?? 0, abs(got.o - (d["o"] ?? 1)))
                    worst["dash"] = max(worst["dash"] ?? 0, abs(got.dash - (d["dash"] ?? 0)))
                    samples += 1
                    continue
                }
                let want = FxValues.rest(doubles(v).filter { $0.key != "px" && $0.key != "py" })
                for ch in Keyframes.channels { worst[ch] = max(worst[ch] ?? 0, abs(got[ch] - want[ch])) }
                if let path = c["path"] as? String, let px = Keyframes.number(v["px"]) {
                    let x = num(box, "x"), y = num(box, "y"), w = num(box, "w"), h = num(box, "h")
                    let f = LauncherEntrance.spriteFrame(FxSprite(x: x, y: y, w: w, h: h, tracks: tracks, path: path), t, values: got)
                    let ex = x + w / 2 + f.tx - px
                    let ey = y + h / 2 + f.ty - Keyframes.number(v["py"])!
                    worst["path"] = max(worst["path"] ?? 0, (ex * ex + ey * ey).squareRoot())
                }
                samples += 1
            }
        }
        let report = worst.keys.sorted().map { "\($0)=\(String(format: "%.5f", worst[$0]!))" }.joined(separator: " ")
        print("launcherfx golden: \(cases.count) cases, \(samples) samples; max error \(report)")
        XCTAssertEqual(cases.count, 499)
        XCTAssertEqual(samples, 22123)
        for ch in ["tx", "ty", "txp", "typ", "r", "rx", "ry", "od", "dash", "clip"] { XCTAssertLessThan(worst[ch]!, 0.01, ch) }
        for ch in ["sx", "sy", "o"] { XCTAssertLessThan(worst[ch]!, 0.001, ch) }
        // The mascot's transform lists (moods, typing, the card, the gestures), as matrices.
        XCTAssertLessThan(worst["matrix"]!, 0.001)
        // Chrome lays `left` out on a 1/64 px grid; the motion path is flattened.
        XCTAssertLessThan(worst["left"]!, 0.05)
        XCTAssertLessThan(worst["path"]!, 0.6)
    }

    func testBuildsTheSameTracksTheGoldenWasSampledFrom() throws {
        var want: [String: [[String: Any]]] = [:]
        for c in cases { want[c["src"] as! String] = (c["tracks"] as! [[String: Any]]) }
        let geometry = Self.golden["geometry"] as! [String: [String: Any]]
        let g = geometry["right"]!
        let seed = Int(Keyframes.number(Self.golden["seed"])!)
        var checked = 0
        func check(_ src: String, _ tracks: [Track]) {
            guard let chrome = want[src] else { return XCTFail("not in the golden: \(src)") }
            // Through JSON, as the golden was read.
            let data = try! JSONSerialization.data(withJSONObject: tracks.map { Keyframes.toJson($0) })
            let ours = norm(try! JSONSerialization.jsonObject(with: data) as! [[String: Any]])
            XCTAssertTrue(same(ours, norm(chrome)), "\(src)\nours:   \(ours)\nchrome: \(norm(chrome))")
            checked += 1
        }

        for m in LauncherAttention.modes where m != "off" {
            for t in LauncherAttention.tracks(m) { check("attention:\(m):\(t.part!)", [t]) }
        }
        for t in LauncherAttention.tracks("pulse", clipped: true) { check("attention:pulse-clipped:\(t.part!)", [t]) }
        for t in LauncherAttention.tracks("pulse", wide: true) { check("attention:pulse-wide:\(t.part!)", [t]) }
        for pos in ["right", "left"] {
            for card in [false, true] {
                for m in LauncherIdleCall.modes where m != "off" {
                    if (pos == "left" || card) && m != "peek" && m != "knock" { continue }
                    let p = LauncherIdleCall.performance(m, LauncherIdleCall.geometry(num(g, "width"), num(g, "height"), pos, card))
                    let tag = "idle:\(m)@\(pos)\(card ? "+card" : "")"
                    check("\(tag):self", p.selfTracks)
                    for (part, tracks) in p.parts { check("\(tag):\(part)", tracks) }
                    for (i, t) in p.launcher.enumerated() { check("\(tag):launcher\(i)", [t]) }
                    for (i, r) in p.ripples.enumerated() { check("\(tag):ripple\(i)", [r.track]) }
                    check("\(tag):bubble", [p.bubble])
                }
            }
        }
        for label in ["right", "left"] {
            let geo = geometry[label]!
            let stage = LauncherEntrance.stage(
                width: num(geo, "width"), height: num(geo, "height"), position: geo["position"] as! String,
                screenWidth: num(geo, "screenWidth"), screenHeight: num(geo, "screenHeight"),
                side: num(geo, "side"), bottom: num(geo, "bottom"), accent: geo["accent"] as! String)
            for m in LauncherEntrance.modes where m != "classic" {
                if label == "left" && !["ufo", "confetti", "magic", "plane", "meteor"].contains(m) { continue }
                let p = try XCTUnwrap(LauncherEntrance.plan(m, stage, seed: seed))
                check("entrance:\(m)@\(label):arrive", [p.arrive.withDelay(p.revealAt)])
                func walk(_ sp: FxSprite, _ at: String) {
                    if !sp.tracks.isEmpty { check("entrance:\(m)@\(label):\(at)", sp.tracks) }
                    for (i, k) in sp.children.enumerated() { walk(k, "\(at).\(i)") }
                }
                for (i, sp) in p.sprites.enumerated() { walk(sp, "s\(i)") }
            }
        }
        check("entrance:settle", [LauncherEntrance.settleReveal])
        // The mascot: its moods, the typing mascot and pencil, the card's moves, the figure's gestures.
        let moods: [(String, String?, Double?)] = [("wave", "wave", 2), ("wave", "down", nil), ("think", nil, nil), ("happy", "down", nil)]
        for (mood, arm, count) in moods {
            let plan = MascotMoods.plan(mood, arm: arm, waveCount: count)
            for (part, tracks) in plan.parts where part != "lid" || mood == "wave" {
                check("mascot:mood-\(mood)\(arm.map { "@\($0)" } ?? ""):\(part)", tracks)
            }
        }
        check("mascot:typing:sway", [MascotMoods.Typing.sway])
        check("mascot:typing:blink", [MascotMoods.Typing.blink])
        check("mascot:typing:glance", [MascotMoods.Typing.glance])
        for (i, d) in MascotMoods.Typing.dots.enumerated() { check("mascot:typing:dot\(i)", [d.track]) }
        check("mascot:pencil:line", [MascotMoods.Pencil.write])
        check("mascot:pencil:pencil", [MascotMoods.Pencil.pencil])
        check("mascot:card:spring", [MascotMotion.cardEnterTrack("lively", "card")!])
        check("mascot:card:in", [MascotMotion.cardEnterTrack("subtle", "card")!])
        check("mascot:card:collapse", [MascotMotion.cardLeaveTrack("lively", "open")!])
        check("mascot:card:out", [MascotMotion.cardLeaveTrack("off", "close")!])
        check("mascot:card:ping-dot", [MascotMotion.Ping.dot])
        check("mascot:card:ping-ring", [MascotMotion.Ping.ring])
        check("mascot:card:word3", [MascotMotion.wordFade("Hi there, how can we help you today?")!.tracks[3]])
        for amp in [1, 0.75, 0.55] {
            for g in ["pop", "rise", "fadeIn", "wave", "tilt", "nod", "hop", "handoff", "bow"] {
                if amp != 1 && (g == "rise" || g == "fadeIn") { continue }
                let tr = MascotMotion.gestureTrack(g, g == "fadeIn" ? 0 : amp, delay: g == "pop" ? 140 : g == "rise" ? 80 : 0,
                                                   toward: g == "handoff" ? (x: -40, y: 60) : nil)
                check("mascot:gesture:\(g)@\(Keyframes.jsNum(amp))", [tr])
            }
            check("mascot:gesture:talk@\(Keyframes.jsNum(amp))", [MascotMotion.talkTrack(amp)])
        }
        check("mascot:gesture:breath", [MascotMotion.breath])
        // Every case in the golden is one this SDK builds.
        XCTAssertEqual(checked, cases.count)
    }

    func testReadsTheOwnersSettingsAsTheWebDoes() {
        let off = Launcher.resolve(["widgetIconBgColor": "#000000"])
        XCTAssertEqual(off.entrance, "classic")
        XCTAssertEqual(off.attention, "off")
        XCTAssertEqual(off.idleCall, "off")
        XCTAssertEqual(off.idleCallDelay, 12)
        let on = Launcher.resolve([
            "launcherEntrance": "rocket",
            "launcherAttention": "orbit",
            "launcherIdleCall": "knock",
            "launcherIdleCallDelay": "2.5",
            "launcherIdleCallText": "  Hello   there, anybody home today?  ",
        ])
        XCTAssertEqual(on.entrance, "rocket")
        XCTAssertEqual(on.attention, "orbit")
        XCTAssertEqual(on.idleCall, "knock")
        XCTAssertEqual(on.idleCallDelay, 5)
        XCTAssertEqual(on.idleCallText, "Hello there, anybody hom")
        XCTAssertEqual(LauncherEntrance.normalize("warp"), "classic")
        XCTAssertEqual(LauncherIdleCall.normalizeDelay(999), 120)
        XCTAssertEqual(LauncherIdleCall.normalizeDelay(12.5), 13)
        XCTAssertEqual(LauncherIdleCall.line("knock", "   "), "Knock knock!")
        XCTAssertEqual(LauncherAttention.target("float"), "greeting")
        XCTAssertEqual(LauncherAttention.target("pulse"), "launcher")
    }

    func testPrintsNumbersAsJavaScriptDoes() {
        XCTAssertEqual(Keyframes.jsNum(1), "1")
        XCTAssertEqual(Keyframes.jsNum(-0.0), "0")
        XCTAssertEqual(Keyframes.jsNum(0.1 + 0.2), "0.30000000000000004")
        XCTAssertEqual(Keyframes.jsNum(0.00001), "0.00001")
        XCTAssertEqual(Keyframes.jsNum(1e-7), "1e-7")
        XCTAssertEqual(Keyframes.fixed(0.125, 2), "0.13")
        XCTAssertEqual(Keyframes.fixed(-0.125, 2), "-0.13")
        XCTAssertEqual(Keyframes.fixed(1.005, 2), "1")
        XCTAssertEqual(Keyframes.fixed(12.3456, 1), "12.3")
    }
}
