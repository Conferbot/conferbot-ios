//
//  DelightViews.swift
//  Conferbot
//
//  The conversation's human touches, drawn (Core/Delight; RN
//  components/Delight/Delight.tsx; web ts/chat/delight/ and
//  css/nodes/17-delight.css, 06-rating-fx.css):
//
//    ReactionBadge     the bot's tapback on the corner of the visitor's
//                      answer facing the bot, popping in (cb-react-pop)
//    AnswerConfetti    a second of confetti in the bot's colours from the
//                      answer (cb-confetti-fly), transform and opacity only
//    RatingSparks      the rating's sparks on a pick (cbn-spark)
//    StallHintView     "No rush - ..." under a question that has waited
//    ChangeAnswerLink  "Edit" under the visitor's latest answer
//
//  Nothing moves with Reduce Motion; the confetti and the sparks are not
//  drawn at all then. No haptics.
//

import SwiftUI

private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

/// The tapback: a 26pt round badge, start corner, 14pt below the bubble.
@available(iOS 15.0, *)
struct ReactionBadge: View {
    let emoji: String
    let card: Color
    let ring: Color
    @State private var shown = reduceMotion

    var body: some View {
        Text(emoji)
            .font(.system(size: 13))
            .frame(width: 26, height: 26)
            .background(Circle().fill(card))
            .overlay(Circle().stroke(ring, lineWidth: 2))
            .shadow(color: Color(hex: "0f172a").opacity(0.18), radius: 3, x: 0, y: 2)
            .scaleEffect(shown ? 1 : 0.2)
            .rotationEffect(.degrees(shown ? 0 : -24))
            .opacity(shown ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel(Delight.reactionLabel(emoji))
            .accessibilityAddTraits(.isImage)
            .onAppear {
                guard !shown else { return }
                // The web's pop spring (cubic-bezier(0.34, 1.56, 0.64, 1), 460 ms)
                withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { shown = true }
            }
    }
}

/// The burst, from the bubble's middle: each piece flies out to (dx, dy) by
/// 55% of 1.05 s, then on and down by its fall while it fades. Colours: the
/// bot's accent, the star gold, the accent lightened, a mint.
@available(iOS 15.0, *)
struct AnswerConfetti: View {
    let accent: Color
    var onDone: () -> Void = {}
    @State private var pieces = Delight.confettiPieces()
    @State private var start = Date()

    var body: some View {
        if reduceMotion {
            Color.clear.frame(width: 0, height: 0).onAppear(perform: onDone)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSince(start) * 1000
                    let tones = [accent, Color(hex: "f5a524"), accent.opacity(0.45), Color(hex: "34d399")]
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    for p in pieces {
                        let f = min(1, max(0, (t - p.delay) / 1050))
                        guard f > 0 else { continue }
                        // cubic-bezier(0.2, 0.7, 0.3, 1), roughly: an ease-out
                        let e = 1 - pow(1 - f, 2.6)
                        let k = min(1, e / 0.55)
                        let tail = max(0, (e - 0.55) / 0.45)
                        let x = e <= 0.55 ? p.dx * k : p.dx + p.dx * 0.15 * tail
                        let y = e <= 0.55 ? p.dy * k : p.dy + p.fall * tail
                        let rot = e <= 0.55 ? p.rot * 0.6 * k : p.rot * 0.6 + p.rot * 0.4 * tail
                        let scale = e <= 0.55 ? 0.6 + 0.4 * k : 1 - 0.1 * tail
                        let opacity = e <= 0.55 ? 1 : 1 - tail
                        var c = ctx
                        c.opacity = opacity
                        c.translateBy(x: mid.x + x, y: mid.y + y)
                        c.rotate(by: .degrees(rot))
                        c.scaleBy(x: scale, y: scale)
                        let w: CGFloat = 6, h: CGFloat = p.round ? 6 : 9
                        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                        c.fill(Path(roundedRect: rect, cornerRadius: p.round ? 3 : 1.5), with: .color(tones[p.tone]))
                    }
                }
            }
            .allowsHitTesting(false)
            .frame(width: 260, height: 220)
            .accessibilityHidden(true)
            .onAppear {
                start = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + Delight.confettiMs / 1000, execute: onDone)
            }
        }
    }
}

/// Sparks round the picked star or face: out from its edge, 12pt to 36pt, fading.
@available(iOS 15.0, *)
struct RatingSparks: View {
    let top: Bool
    let color: Color
    @State private var go = false

    var body: some View {
        if !reduceMotion {
            ZStack {
                ForEach(Array(Delight.ratingSparks(top: top).enumerated()), id: \.offset) { i, angle in
                    let size: CGFloat = i % 2 == 1 ? 4 : 6
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .scaleEffect(go ? 0.3 : 0.4)
                        .offset(y: go ? -36 : -12)
                        .rotationEffect(.degrees(angle))
                        .opacity(go ? 0 : 1)
                        .animation(.timingCurve(0.2, 0.8, 0.3, 1, duration: i % 2 == 1 ? 0.6 : 0.75).delay(0.08), value: go)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { go = true }
        }
    }
}

/// "No rush - ...": a soft line under the question, a breathing dot, rising in.
@available(iOS 15.0, *)
struct StallHintView: View {
    @ObservedObject private var touches = ConferBot.shared.touches
    var accent: Color
    var muted: Color = .secondary
    @State private var shown = reduceMotion
    @State private var breathe = false

    var body: some View {
        if let hint = touches.stallHint {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 1 : (breathe ? 1 : 0.35))
                    .scaleEffect(reduceMotion ? 1 : (breathe ? 1.1 : 0.85))
                Text(hint)
                    .font(.system(size: 12.5))
                    .foregroundColor(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 40)
            .padding(.top, 4)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
            .accessibilityElement(children: .combine)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.4)) { shown = true }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { breathe = true }
            }
            .onDisappear {
                shown = reduceMotion
                breathe = false
            }
        }
    }
}

/// "Edit": a small muted link right under the latest answer, at its edge.
@available(iOS 15.0, *)
struct ChangeAnswerLink: View {
    var muted: Color = .secondary
    let action: () -> Void
    @State private var shown = reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("\u{270E}").font(.system(size: 11))
                Text(I18n.t("chat.edit"))
                    .chatFont(.body, size: 11.5, weight: .medium, relativeTo: .caption, fallback: .system(size: 11.5, weight: .medium))
            }
            .foregroundColor(muted)
            .opacity(0.85)
            .padding(2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(I18n.t("chat.changeAnswer"))
        .opacity(shown ? 1 : 0)
        .onAppear {
            guard !shown else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { shown = true }
        }
    }
}

/// The touches on one visitor answer: the tapback and the burst over the
/// bubble, "Edit" under it (MessageBubble draws this for visitor rows).
@available(iOS 15.0, *)
struct AnswerTouches: View {
    let rowId: String
    @ObservedObject private var touches = ConferBot.shared.touches
    var accent: Color
    var card: Color
    var ring: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let c = touches.touches[rowId]?.celebrate {
                AnswerConfetti(accent: accent, onDone: { touches.clearBurst(rowId) })
                    .id(c)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let emoji = touches.touches[rowId]?.reaction {
                ReactionBadge(emoji: emoji, card: card, ring: ring)
                    .offset(x: -8, y: 14)
            }
        }
        .allowsHitTesting(false)
    }
}

/// "Edit" under a visitor row while it is the latest changeable answer.
@available(iOS 15.0, *)
struct ChangeAnswerSlot: View {
    let rowId: String
    var muted: Color = .secondary
    @ObservedObject private var touches = ConferBot.shared.touches

    var body: some View {
        if touches.changeRowId == rowId {
            ChangeAnswerLink(muted: muted) { ConferBot.shared.changeAnswer() }
        }
    }
}
