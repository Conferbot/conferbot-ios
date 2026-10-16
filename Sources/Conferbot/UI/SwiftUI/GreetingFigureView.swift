//
//  GreetingFigureView.swift
//  Conferbot
//
//  The greeting card's figure alive (Core/Customization/MascotMotion.swift;
//  the React Native SDK's components/Mascot/useGreetingMotion.ts): the web's
//  director on this card, its stage on the clock. The figure (the owner's
//  mascot, or the bot's avatar) pops (or rises), waves, nods, breathes and
//  gives at most three small gestures, then stands still; when the card
//  goes it hands off toward the launcher (opened) or bows (the x). A voice
//  note talks while its waveform plays. Nothing while the app is in the
//  background; Reduce Motion: a fade. The card's own moves (spring, ping,
//  words) are played by GreetingCardView on its clock.
//

import SwiftUI

/// A CSS transform as a SwiftUI effect: the matrix about a pivot (transform-origin, a share of the view's box).
@available(iOS 15.0, *)
struct FxTransformEffect: GeometryEffect {
    var v: FxValues
    var order: String
    var anchor: UnitPoint = .center

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let m = Keyframes.transformMatrix(v, order)
        let pivot = CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
        let t = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5]))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        return ProjectionTransform(t)
    }
}

/// The director's stage: what plays on the figure, and since when. Main thread only.
@available(iOS 15.0, *)
final class GreetingFigureModel: ObservableObject, MascotStage {
    /// Something moves (the figure's clock runs).
    @Published private(set) var live = false
    private(set) var gesture: (track: Track, start: Date)?
    private(set) var breath: (start: Date, end: Date?)?
    private(set) var talk: (track: Track, start: Date, end: Date?)?
    /// Where the launcher's centre is from the figure's (the hand-off).
    var toward: () -> (x: Double, y: Double)? = { nil }
    var hasFigure = false
    /// The card's height (pt), for the hand-off's aim.
    var cardHeight = 120.0
    private(set) var director: MascotMotion.Director?
    private var gestureDone: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    /// Starts the director as the card shows (once).
    func start(mode: String, style: String, figure: String?, reduced: Bool) {
        guard director == nil else { return }
        hasFigure = figure != nil
        let d = MascotMotion.Director(mode: mode, stage: self, reduced: { reduced },
                                      amp: { MascotMotion.figureAmp(figure) }, ownText: { MascotMotion.ownsText(style) })
        director = d
        d.show()
        if style == "voice" && !reduced { d.talkFor(MascotMotion.voicePlayMs()) }
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.director?.pageHidden(true)
            },
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.director?.pageHidden(false)
            },
        ]
    }

    func stop() {
        director?.destroy()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    /// The card is going: the figure's hand-off or bow (how long it lasts, ms).
    func hide(_ reason: String) -> Double {
        let moving = director.map { $0.state != .hidden && $0.state != .destroyed } ?? false
        director?.hide(reason)
        return moving && hasFigure && gesture != nil ? (reason == "close" ? 300 : 280) : 0
    }

    private func refresh() {
        let now = Date()
        live = gesture != nil || breath.map { $0.end.map { $0 > now } ?? true } == true || talk != nil
    }

    // MARK: MascotStage

    func play(_ g: String, amp: Double, delay: Double) {
        guard hasFigure else { return }
        let tr = MascotMotion.gestureTrack(g, amp, delay: delay, toward: g == "handoff" ? toward() : nil)
        talk = nil
        gesture = (tr, Date())
        gestureDone?.cancel()
        // The leaving ones hold their end (fill forwards).
        if g != "handoff" && g != "bow" {
            let w = DispatchWorkItem { [weak self] in
                guard let self = self, self.gesture?.track === tr else { return }
                self.gesture = nil
                self.refresh()
            }
            gestureDone = w
            DispatchQueue.main.asyncAfter(deadline: .now() + Keyframes.tracksEnd([tr]) / 1000 + 0.05, execute: w)
        }
        refresh()
    }

    func breathe(_ on: Bool) {
        do {
            if on {
                self.breath = (Date(), nil)
            } else if let b = self.breath, b.end == nil {
                // It ends on its next exhale.
                let lap = MascotMotion.breathMs / 1000
                let laps = (Date().timeIntervalSince(b.start) / lap).rounded(.up)
                let end = b.start.addingTimeInterval(max(1, laps) * lap)
                self.breath = (b.start, end)
                DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow + 0.05) { [weak self] in self?.refresh() }
            }
            self.refresh()
        }
    }

    func talk(_ on: Bool, amp: Double) {
        do {
            if on {
                self.gesture = nil
                self.talk = (MascotMotion.talkTrack(amp), Date(), nil)
            } else if let t = self.talk {
                // The syllable in flight ends first.
                let lap = MascotMotion.talkMs / 1000
                let end = t.start.addingTimeInterval((Date().timeIntervalSince(t.start) / lap).rounded(.up) * lap)
                self.talk = (t.track, t.start, end)
                DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow + 0.02) { [weak self] in
                    guard let self = self, self.talk?.end == end else { return }
                    self.talk = nil
                    self.refresh()
                }
            }
            self.refresh()
        }
    }

    // A touch screen has no pointer to lean toward.
    func lean(_ x: Double, amp: Double) {}
    // The ping and the words are played by the card on its own clock.
    func ping(_ on: Bool) {}
    func words() {}

    func reset() {
        do {
            self.gesture = nil
            self.breath = nil
            self.talk = nil
            self.gestureDone?.cancel()
            self.refresh()
        }
    }
}

/// The figure moved by the director: the breath outside, the gesture, then the talk, each about its feet.
@available(iOS 15.0, *)
struct GreetingFigure<Content: View>: View {
    @ObservedObject var model: GreetingFigureModel
    let size: CGFloat
    let content: Content

    init(model: GreetingFigureModel, size: CGFloat, @ViewBuilder content: () -> Content) {
        self.model = model
        self.size = size
        self.content = content()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.live)) { tl in
            let now = tl.date
            let feet = UnitPoint(x: 0.5, y: 1)
            let g = model.gesture.map { Keyframes.evaluate([$0.track], now.timeIntervalSince($0.start) * 1000) } ?? FxValues.rest()
            let gOrder = model.gesture.map { Keyframes.transformOrder($0.track) } ?? "trs"
            let b = model.breath.flatMap { br -> FxValues? in
                if let end = br.end, now >= end { return nil }
                return Keyframes.evaluate([MascotMotion.breath], now.timeIntervalSince(br.start) * 1000)
            } ?? FxValues.rest()
            let k = model.talk.flatMap { tk -> FxValues? in
                if let end = tk.end, now >= end { return nil }
                return Keyframes.evaluate([tk.track], now.timeIntervalSince(tk.start) * 1000)
            } ?? FxValues.rest()
            content
                .modifier(FxTransformEffect(v: k, order: "ts", anchor: feet))
                .opacity(min(1, max(0, g.o)))
                .modifier(FxTransformEffect(v: g, order: gOrder, anchor: feet))
                .modifier(FxTransformEffect(v: b, order: "trs", anchor: feet))
        }
    }
}
