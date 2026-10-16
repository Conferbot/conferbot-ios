import XCTest
@testable import Conferbot

/// The owner's mascot (art3d.ts), its moods, the greeting card's director and
/// the card's moves, as the React Native SDK's __tests__/core/mascot.test.ts.
final class MascotTests: XCTestCase {
    /// Well-formed markup: every tag closed in order, attributes quoted, nothing between the tags.
    private func wellFormed(_ xml: String) -> Bool {
        var stack: [String] = []
        let ns = xml as NSString
        var at = 0
        for m in Keyframes.regex("<(/?)([a-zA-Z]+)((?:\\s+[a-zA-Z0-9-:]+=\"[^\"<>]*\")*)\\s*(/?)>").matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            if !ns.substring(with: NSRange(location: at, length: m.range.location - at)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            at = m.range.location + m.range.length
            let close = m.range(at: 1).length > 0
            let tag = ns.substring(with: m.range(at: 2))
            if close {
                if stack.popLast() != tag { return false }
            } else if m.range(at: 4).length == 0 {
                stack.append(tag)
            }
        }
        return at == ns.length && stack.isEmpty
    }

    // MARK: - The owner's mascot (art3d mascotLookOf, mascotScaleOf)

    func testDefaultsToTheClassicBlobAndKeepsOnlyKnownValues() {
        XCTAssertEqual(MascotArt.lookOf(nil), MascotArt.Look())
        XCTAssertEqual(MascotArt.lookOf(["mascotShape": "dragon", "mascotEyes": "laser", "mascotAccessory": "cape", "mascotColor": "red", "mascotName": 42]), MascotArt.Look())
        XCTAssertEqual(
            MascotArt.lookOf(["mascotShape": "fox", "mascotEyes": "star", "mascotAccessory": "crown", "mascotColor": " #F97316 ", "mascotName": "  Pip   the  fox, the friendliest one "]),
            MascotArt.Look(shape: "fox", eyes: "star", accessory: "crown", color: "#F97316", name: "Pip the fox, the fri"))
    }

    func testSizesTheLauncherMascot70To150PercentOfTheButton112WhenUnset() {
        XCTAssertEqual(MascotArt.scaleOf([:]), 112)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": NSNull()]), 112)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": ""]), 112)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": "big"]), 112)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": 10]), 70)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": 999]), 150)
        XCTAssertEqual(MascotArt.scaleOf(["mascotLauncherScale": "120.4"]), 120)
    }

    func testHas27CharactersEachWithItsOwnName() {
        XCTAssertEqual(MascotArt.shapes.count, 27)
        for s in MascotArt.shapes { XCTAssertFalse((MascotArt.defaultNames[s] ?? "").isEmpty, s) }
        XCTAssertEqual(MascotArt.eyes.count, 5)
        XCTAssertEqual(MascotArt.accessories.count, 7)
    }

    func testPaintsTheOwnersColourCloudAndGhostPalerAToothPearly() {
        XCTAssertEqual(MascotArt.colorOf(MascotArt.Look(shape: "cat", color: "#ff0000"), accent: "#0000ff"), "#ff0000")
        XCTAssertEqual(MascotArt.colorOf(MascotArt.Look(shape: "cat"), accent: "#0000ff"), "#0000ff")
        XCTAssertEqual(MascotArt.colorOf(MascotArt.Look(shape: "cloud"), accent: "#000000"), MascotArt.mixColor("#000000", 45, "#ffffff"))
        XCTAssertEqual(MascotArt.colorOf(MascotArt.Look(shape: "ghost"), accent: "#000000"), MascotArt.mixColor("#000000", 22, "#ffffff"))
        XCTAssertEqual(MascotArt.colorOf(MascotArt.Look(shape: "tooth"), accent: "#000000"), MascotArt.mixColor("#000000", 12, "#ffffff"))
    }

    // MARK: - The mascot drawn in layers

    func testDrawsEveryCharacterEyesAndAccessoryAsValidSvg() {
        var drawn = 0
        for shape in MascotArt.shapes {
            for eyes in MascotArt.eyes {
                for accessory in MascotArt.accessories {
                    if eyes != "round" && accessory != "none" && shape != "robot" { continue }
                    for bust in [false, true] {
                        let l = MascotArt.layers("#4f46e5", arm: "wave", look: MascotArt.Look(shape: shape, eyes: eyes, accessory: accessory), bust: bust)
                        for (name, xml) in l.ordered {
                            guard let xml = xml else { continue }
                            XCTAssertTrue(wellFormed(xml), "\(shape) \(eyes) \(accessory) \(name)")
                            // No CSS the renderer would drop: no style, class, filter or color-mix().
                            XCTAssertNil(xml.range(of: "style=|class=|filter=|color-mix|undefined|NaN|nil", options: .regularExpression), "\(shape) \(name)")
                            drawn += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(drawn, 1500)
    }

    func testKeepsTheArmBehindOrInFrontByItsPoseAndTheBustWithoutArmsTailOrShadow() {
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "knock").armFront!.contains("<svg"))
        XCTAssertNil(MascotArt.layers("#4f46e5", arm: "knock").armBack)
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "wave").armBack!.contains("<svg"))
        let cat = MascotArt.layers("#4f46e5", arm: "wave", look: MascotArt.Look(shape: "cat"))
        XCTAssertTrue(cat.tail!.contains("<path"))
        let bust = MascotArt.layers("#4f46e5", arm: "wave", look: MascotArt.Look(shape: "cat"), bust: true)
        XCTAssertNil(bust.shadow)
        XCTAssertNil(bust.tail)
        XCTAssertNil(bust.armBack)
        XCTAssertNil(bust.armFront)
        XCTAssertTrue(bust.body.contains("viewBox=\"4 0 92 96\""))
        // The body's left arm goes with the arms.
        XCTAssertGreaterThan(cat.body.count, bust.body.count)
    }

    func testDrawsTheOwnersEyesAndAccessoryWhereTheyBelong() {
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(eyes: "sleepy")).face!.contains("<path"))
        XCTAssertNil(MascotArt.layers("#4f46e5", arm: "down").face)
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(eyes: "shades")).cover!.contains("#0b1020"))
        // Glasses and hats on top of everything; a robot's LED eyes without whites.
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(accessory: "glasses")).top!.contains("stroke=\"#1f2937\""))
        XCTAssertTrue(MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(accessory: "crown")).top!.contains("#facc15"))
        let robot = MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(shape: "robot"))
        XCTAssertFalse(robot.body.contains("url(#me)"))
        XCTAssertNil(robot.cover)
        // An industry character's props are on top, in their own paints.
        let medic = MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(shape: "medic"))
        XCTAssertTrue(medic.top!.contains("url(#mr)"))
        XCTAssertTrue(medic.top!.contains("id=\"mr\""))
    }

    func testColoursTheBodyInTheOwnersColourAndThePupilsRimInTheLaunchers() {
        let l = MascotArt.layers("#000000", arm: "down", look: MascotArt.Look(color: "#ff0000"))
        XCTAssertTrue(l.body.contains("stop-color=\"#ff0000\""))
        XCTAssertTrue(l.look.contains(MascotArt.mixColor("#000000", 45, "#0b1020")))
    }

    func testDrawsTheBlobAsRNDoesMarkupForMarkup() {
        // RN mascotLayers('#4f46e5', 'down').smile, verbatim.
        let l = MascotArt.layers("#4f46e5", arm: "down")
        XCTAssertTrue(l.smile.hasSuffix(##"<g transform="translate(0 0)"><path d="M42 72 Q50 80 58 72" fill="none" stroke="#1e1b2e" stroke-width="2.6" stroke-linecap="round"/></g></svg>"##))
        XCTAssertTrue(l.lids.contains(##"<g transform="translate(37 52) scale(1) translate(-37 -52)"><rect x="26" y="39" width="22" height="26" rx="10" fill="url(#ml)"/></g>"##))
    }

    func testTurnsEachPartAboutItsJointTheLidsAtTheCharactersEyes() {
        let o = MascotArt.blobOrigins
        XCTAssertTrue(o.body == (50, 94) && o.arm == (80, 64) && o.lid == (50, 39) && o.look == (50, 54) && o.brow == (50, 36))
        // The car's eyes are high and small: eyeY 40, scale 0.62.
        XCTAssertEqual(MascotArt.origins(MascotArt.Look(shape: "car")).lid.1, 40 - 13 * 0.62, accuracy: 1e-6)
        // The bust's 92 x 96 viewBox fitted in a square box.
        XCTAssertTrue(MascotArt.point((4, 0), 96, bust: true) == (2, 0))
        XCTAssertTrue(MascotArt.point((50, 94), 100) == (50, 94))
    }

    func testIsOneSvgPerLayer() {
        let body = MascotArt.layers("#4f46e5", arm: "down", look: MascotArt.Look(shape: "owl")).body
        XCTAssertTrue(body.hasPrefix(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">"##))
        XCTAssertFalse(wellFormed("<svg><g></svg>"))
    }

    // MARK: - The moods (art3d MASCOT_ANIM_CSS)

    func testBlinksAlwaysAndAddsTheMoodsOwnMoves() {
        XCTAssertEqual(Set(MascotMoods.plan("idle").parts.keys), ["lid"])
        XCTAssertEqual(Set(MascotMoods.plan("wave", arm: "wave").parts.keys), ["arm", "lid"])
        XCTAssertEqual(Set(MascotMoods.plan("think").parts.keys), ["body", "brow", "lid", "look"])
        XCTAssertEqual(Set(MascotMoods.plan("happy", arm: "down").parts.keys), ["arm", "body", "lid", "shadow"])
        XCTAssertTrue(MascotMoods.plan("happy").grin)
        // The bust (launcher, typing) has no arm.
        XCTAssertNil(MascotMoods.plan("happy", bust: true).parts["arm"])
    }

    func testLiftsARestingArmBeforeItWavesAndWavesASetNumberOfTimes() {
        let up = MascotMoods.plan("wave", arm: "down").parts["arm"]![0]
        XCTAssertEqual(up.options.duration, 3200)
        XCTAssertEqual(Keyframes.evaluate([up], 3200 * 0.24).r, -132, accuracy: 1e-4)
        let two = MascotMoods.plan("wave", arm: "wave", waveCount: 2)
        XCTAssertEqual(Keyframes.tracksEnd(two.parts["arm"]!), 5600)
        // The loop starts on a whole blink after the two waves.
        XCTAssertEqual(two.settle, 6400)
        XCTAssertEqual(two.period, 6400)
    }

    func testHopsTwiceWhenHappyThenBlinksOn() {
        let p = MascotMoods.plan("happy", arm: "down")
        XCTAssertEqual(Keyframes.evaluate(p.parts["body"]!, 900 * 0.45).ty, -8, accuracy: 1e-4)
        XCTAssertEqual(Keyframes.tracksEnd(p.parts["body"]!), 1800)
    }

    func testLoopsThinkAsOneLapOfAllItsParts() {
        XCTAssertEqual(MascotMoods.plan("think").period, 19200)
    }

    func testKeepsTheSmileAndNothingElseUnderReducedMotion() {
        let p = MascotMoods.plan("happy", reduced: true)
        XCTAssertTrue(p.parts.isEmpty)
        XCTAssertTrue(p.grin)
        XCTAssertEqual(p.settle, 0)
        XCTAssertEqual(p.period, 0)
    }

    func testTypesSwaysAbout50Percent90PercentBlinksGlancesThreeDots02sApart() {
        XCTAssertTrue(MascotMoods.Typing.origin == (16, 28.8))
        XCTAssertEqual(Keyframes.evaluate([MascotMoods.Typing.sway], 1200).r, 4, accuracy: 1e-6)
        XCTAssertEqual(MascotMoods.Typing.dots.map { $0.track.options.delay }, [0, 200, 400])
        XCTAssertEqual(MascotMoods.Typing.period.truncatingRemainder(dividingBy: 2400), 0)
        XCTAssertEqual(MascotMoods.Typing.period.truncatingRemainder(dividingBy: 3400), 0)
        XCTAssertTrue(MascotMoods.keyframes["cb-typing-blink"]!.contains("95%"))
        XCTAssertEqual(MascotMoods.typingLabel("mascot", "Pip"), "Pip is typing")
        XCTAssertEqual(MascotMoods.typingLabel("mascot", ""), "Typing")
        XCTAssertEqual(MascotMoods.typingLabel("dots", "Pip"), "Typing")
    }

    func testThePencilWritesItsLineAndRidesItsTip() {
        let P = MascotMoods.Pencil.self
        XCTAssertEqual(Keyframes.evaluate([P.write], 0, base: ["dash": P.dash]).dash, 60)
        XCTAssertEqual(Keyframes.evaluate([P.write], 1500, base: ["dash": P.dash]).dash, 0, accuracy: 1e-9)
        XCTAssertEqual(Keyframes.evaluate([P.write], 1990, base: ["dash": P.dash]).o, 0.05, accuracy: 1e-6)
        let tip = Keyframes.evaluate([P.pencil], 1500)
        XCTAssertEqual(tip.tx, 36, accuracy: 1e-9)
        XCTAssertEqual(tip.ty, 8, accuracy: 1e-9)
    }

    // MARK: - The greeting card's figure (mascotMotion.ts), on a fake clock

    private final class Log: MascotStage {
        var log: [(String, Double, Double)] = []
        var names: [String] { log.map { $0.0 } }
        func play(_ g: String, amp: Double, delay: Double) { log.append(("play:\(g)", amp, delay)) }
        func breathe(_ on: Bool) { log.append((on ? "breathe" : "exhale", 0, 0)) }
        func talk(_ on: Bool, amp: Double) { log.append((on ? "talk" : "quiet", amp, 0)) }
        func lean(_ x: Double, amp: Double) { log.append(("lean", x, amp)) }
        func ping(_ on: Bool) { log.append((on ? "ping" : "ping-off", 0, 0)) }
        func words() { log.append(("words", 0, 0)) }
        func reset() { log.append(("reset", 0, 0)) }
    }

    private typealias Clock = LauncherFxControllersTests.FakeClock

    private func make(mode: String = "lively", reduced: Bool = false, alive: (() -> Bool)? = nil) -> (Clock, MascotMotion.Director, Log) {
        let c = Clock()
        let stage = Log()
        let d = MascotMotion.Director(mode: mode, stage: stage, scheduler: c, reduced: { reduced }, random: { 0.5 }, alive: alive)
        return (c, d, stage)
    }

    private let idleGap = MascotMotion.idleGapMin + 0.5 * MascotMotion.idleGapSpread
    private typealias E = MascotMotion.Entrance

    func testIsLivelyUnlessTheOwnerChoseSubtleOrOff() {
        XCTAssertEqual(MascotMotion.normalize(nil), "lively")
        XCTAssertEqual(MascotMotion.normalize("wild"), "lively")
        XCTAssertEqual(MascotMotion.normalize("subtle"), "subtle")
        XCTAssertEqual(MascotMotion.normalize("off"), "off")
    }

    func testLivelyWordsPopWavePingNodThenABreath() {
        let (c, d, s) = make()
        d.show()
        XCTAssertEqual(s.names, ["reset", "words", "play:pop"])
        XCTAssertEqual(s.log[2].2, E.livelyPop)
        c.advance(E.livelyWave)
        XCTAssertEqual(s.names.last, "play:wave")
        c.advance(E.livelyPing - E.livelyWave)
        XCTAssertEqual(s.names.last, "ping")
        c.advance(E.livelyNod - E.livelyPing)
        XCTAssertEqual(s.names.last, "play:nod")
        c.advance(E.livelyIdle - E.livelyNod)
        XCTAssertEqual(d.state, .living)
        XCTAssertTrue(s.names.contains("breathe"))
        c.advance(MascotMotion.pingMs)
        XCTAssertTrue(s.names.contains("ping-off"))
    }

    func testThreeIdleGesturesAtMostThenStillForGoodWithNoTimerLeft() {
        let (c, d, s) = make()
        d.show()
        c.advance(E.livelyIdle)
        for _ in 0..<6 { c.advance(idleGap) }
        XCTAssertEqual(d.gestures, 3)
        c.advance(MascotMotion.settleAfter)
        XCTAssertEqual(d.state, .settled)
        XCTAssertEqual(s.names.last, "exhale")
        XCTAssertEqual(d.pending, 0)
        c.advance(120_000)
        XCTAssertEqual(d.gestures, 3)
    }

    func testSubtleARiseThePingOneTiltNoWordsNoWave() {
        let (c, d, s) = make(mode: "subtle")
        d.show()
        c.advance(E.subtleIdle)
        for _ in 0..<4 { c.advance(idleGap) }
        c.advance(MascotMotion.settleAfter)
        for n in ["play:rise", "ping", "play:tilt"] { XCTAssertTrue(s.names.contains(n), n) }
        XCTAssertFalse(s.names.contains("words"))
        XCTAssertFalse(s.names.contains("play:wave"))
        XCTAssertEqual(d.state, .settled)
    }

    func testReducedMotionAFadeNothingElseOffNothingAtAll() {
        let (rc, rd, rs) = make(reduced: true)
        rd.show()
        rd.hide("open")
        rc.advance(60000)
        XCTAssertEqual(rs.names, ["reset", "play:fadeIn", "reset"])
        let (oc, od, os) = make(mode: "off")
        od.show()
        oc.advance(60000)
        XCTAssertEqual(os.names, ["reset"])
    }

    func testAVoiceNoteTalksInPlaceOfTheWaveThenQuiet() {
        let (c, d, s) = make()
        d.show()
        d.talkFor(3600)
        c.advance(E.livelyWave)
        XCTAssertEqual(s.names.last, "talk")
        c.advance(3600 - E.livelyWave)
        XCTAssertEqual(s.names.last, "quiet")
    }

    func testHandsOffWhenTheChatOpensFromTheCardBowsAtTheXNothingMoreAfter() {
        let (_, od, os) = make()
        od.show()
        od.hide("open")
        XCTAssertEqual(os.names.last, "play:handoff")
        XCTAssertEqual(od.pending, 0)
        let (_, cd, cs) = make(mode: "subtle")
        cd.show()
        cd.hide("close")
        XCTAssertEqual(cs.log.last!.0, "play:bow")
        XCTAssertEqual(cs.log.last!.1, 0.6)
        XCTAssertEqual(cs.log.last!.2, 0)
    }

    func testWaitsInTheBackgroundAndGivesWayToTheCardLeaving() {
        let (c, d, _) = make()
        d.show()
        c.advance(E.livelyIdle)
        d.pageHidden(true)
        c.advance(60000)
        XCTAssertEqual(d.gestures, 0)
        d.pageHidden(false)
        c.advance(idleGap)
        XCTAssertEqual(d.gestures, 1)
        var alive = true
        let (gc, gd, _) = make(alive: { alive })
        gd.show()
        alive = false
        gc.advance(E.livelyWave)
        XCTAssertEqual(gd.state, .destroyed)
        XCTAssertEqual(gd.pending, 0)
    }

    func testMovesAMascotAllTheWayAPhotoAndInitialsLess() {
        XCTAssertEqual([MascotMotion.figureAmp("mascot"), MascotMotion.figureAmp("avatar"), MascotMotion.figureAmp("initials"), MascotMotion.figureAmp(nil)], [1, 0.75, 0.55, 1])
        XCTAssertTrue(MascotMotion.ownsText("typewriter") && MascotMotion.ownsText("imessage") && !MascotMotion.ownsText("card"))
    }

    // MARK: - The greeting card's own moves (polish-home.css)

    func testSpringsUpWhenLivelyComesInAsAlwaysOtherwiseTheNotificationAndNeonKeepTheirs() {
        XCTAssertEqual(MascotMotion.cardEnterTrack("lively", "card")!.options.duration, 620)
        XCTAssertEqual(MascotMotion.cardEnterTrack("subtle", "card")!.options.duration, 450)
        XCTAssertEqual(MascotMotion.cardEnterTrack("off", "note")!.options.duration, 450)
        XCTAssertNil(MascotMotion.cardEnterTrack("lively", "notification"))
        XCTAssertNil(MascotMotion.cardEnterTrack("lively", "neon"))
        XCTAssertNil(MascotMotion.cardEnterTrack("lively", "card", reduced: true))
        let spring = MascotMotion.cardEnterTrack("lively", "card")!
        let a = Keyframes.evaluate([spring], 0)
        XCTAssertEqual([a.o, a.ty, a.sx], [0, 14, 0.94])
        let b = Keyframes.evaluate([spring], 620)
        XCTAssertEqual([b.o, b.ty, b.sx], [1, 0, 1])
    }

    func testCollapsesTowardTheLauncherWhenOpenedFromTheCardFadesWhenClosed() {
        let open = MascotMotion.cardLeaveTrack("lively", "open")!.options
        XCTAssertEqual(open.duration, 240)
        XCTAssertEqual(open.delay, 40)
        XCTAssertEqual(MascotMotion.cardLeaveTrack("off", "open")!.options.duration, 220)
        XCTAssertEqual(MascotMotion.cardLeaveTrack("subtle", "close")!.options.duration, 220)
        XCTAssertNil(MascotMotion.cardLeaveTrack("lively", "open", reduced: true))
    }

    func testFadesTheWordsUpWithinASecond() {
        XCTAssertNil(MascotMotion.wordFade("Hi"))
        let f = MascotMotion.wordFade("Hi there, how can we help you today?")!
        XCTAssertEqual(f.words.count, 8)
        XCTAssertEqual(f.step, 55)
        let long = MascotMotion.wordFade((0..<40).map { "w\($0)" }.joined(separator: " "))!
        XCTAssertEqual(long.step, 13)
        XCTAssertLessThan(Keyframes.tracksEnd([long.tracks[39]]), 1250)
        XCTAssertEqual(MascotMotion.voicePlayMs(), 3660)
    }

    func testPlaysEachGestureAsTheWebDoesTheLeavingOnesHoldTheirEnd() {
        XCTAssertEqual(MascotMotion.gestureTrack("handoff", 1).options.fill, "forwards")
        let pop = MascotMotion.gestureTrack("pop", 1, delay: 140)
        XCTAssertEqual(pop.options.delay, 140)
        XCTAssertEqual(pop.options.fill, "backwards")
        let v = Keyframes.evaluate([pop], 0)
        XCTAssertEqual(v.o, 0)
        XCTAssertEqual(v.sx, 0.3, accuracy: 1e-9)
    }

    // MARK: - The mascot settings, resolved

    func testReadsThemIntoTheCustomizationsAndTheLauncher() {
        let c: [String: Any] = ["mascotShape": "owl", "mascotInGreeting": true, "mascotMotion": "subtle", "mascotLauncherScale": 130, "widgetIconBgColor": "#123456", "launcherStyle": "mascot"]
        let r = Customizations.resolve(c)
        XCTAssertEqual(r.mascot.shape, "owl")
        XCTAssertTrue(r.mascotInGreeting)
        XCTAssertEqual(r.mascotMotion, "subtle")
        XCTAssertEqual(r.mascotLauncherScale, 130)
        XCTAssertEqual(r.mascotAccent, "#123456")
        let d = Customizations.resolve([:])
        XCTAssertFalse(d.mascotInGreeting)
        XCTAssertEqual(d.mascotMotion, "lively")
        XCTAssertEqual(d.mascotLauncherScale, 112)
        let l = Launcher.resolve(c, screenWidth: 390)
        XCTAssertEqual(l.style, "mascot")
        XCTAssertEqual(l.mascot.scale, 130)
        XCTAssertEqual(l.mascot.accent, "#123456")
        XCTAssertEqual(l.mascot.light, MascotArt.mixColor("#123456", 14, "#ffffff"))
        XCTAssertEqual(l.mascot.look.shape, "owl")
    }
}
