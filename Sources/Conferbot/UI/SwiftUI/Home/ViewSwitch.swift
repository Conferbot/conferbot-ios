//
//  ViewSwitch.swift
//  Conferbot
//
//  The open chat's views - home, conversation, help centre - and how the
//  new one comes in: ViewTransition.motion from the owner's viewTransition /
//  viewTransitionDirection (web ts/layout/viewTransition.ts; the React
//  Native SDK's components/Home/ViewSwitch.tsx). Only the new view moves,
//  once per switch; Reduce Motion is a 200ms fade. Then it stays still.
//

import SwiftUI

@available(iOS 15.0, *)
struct ViewSwitch<Content: View>: View {
    /// The view on screen.
    let view: HomeView
    /// customizations.viewTransition and viewTransitionDirection.
    let kind: Any?
    let sweep: Any?
    @ViewBuilder let content: (HomeView) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: HomeView?
    @State private var motion: ViewTransition.Motion = .none
    /// 0 where the new view starts, 1 in place.
    @State private var progress: CGFloat = 1

    var body: some View {
        let current = shown ?? view
        GeometryReader { g in
            content(current)
                .frame(width: g.size.width, height: g.size.height)
                .modifier(Moving(motion: motion, progress: progress, size: g.size))
                .id(current)
        }
        .clipped()
        .onChange(of: view) { next in
            let from = shown ?? next
            guard from != next else { return }
            let m = ViewTransition.motion(kind, sweep, from: from.rawValue, to: next.rawValue, reduced: reduceMotion)
            motion = m
            shown = next
            guard let animation = Self.animation(m) else { return progress = 1 }
            progress = 0
            // The start is drawn first, then it moves into place.
            DispatchQueue.main.async { withAnimation(animation) { progress = 1 } }
        }
        .onAppear { if shown == nil { shown = view } }
    }

    static func animation(_ m: ViewTransition.Motion) -> Animation? {
        func curve(_ p: [Double], _ ms: Double) -> Animation { .timingCurve(p[0], p[1], p[2], p[3], duration: ms / 1000) }
        switch m {
        case .none: return nil
        case .reduced(let d): return .linear(duration: d / 1000)
        case .fade(let d, let delay, _): return curve(ViewTransition.ease, d).delay(delay / 1000)
        case .slide(let d, _, _): return curve(ViewTransition.easeInOut, d)
        }
    }
}

/// Where the new view is at `progress` (0 its start, 1 in place).
@available(iOS 15.0, *)
private struct Moving: ViewModifier {
    let motion: ViewTransition.Motion
    let progress: CGFloat
    let size: CGSize

    func body(content: Content) -> some View {
        var opacity = 1.0, scale: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0
        switch motion {
        case .none:
            break
        case .reduced:
            opacity = Double(progress)
        case .fade(_, _, let from):
            opacity = Double(progress)
            scale = CGFloat(from) + (1 - CGFloat(from)) * progress
        case .slide(_, let x, let y):
            dx = CGFloat(x) * size.width * (1 - progress)
            dy = CGFloat(y) * size.height * (1 - progress)
        }
        return content.opacity(opacity).scaleEffect(scale).offset(x: dx, y: dy)
    }
}
