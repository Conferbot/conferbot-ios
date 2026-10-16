//
//  ConferBotWidgetView.swift
//  Conferbot
//
//  Floating FAB widget overlay — matches web widget behavior exactly.
//

import SwiftUI
import Combine

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 27, 85, 243)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Widget Customizations (resolved from server)

struct WidgetCustomizations {
    enum FABPosition { case left, right }

    /// The launcher as the web draws it on a phone (Core/Customization/Launcher).
    var look: ResolvedLauncher
    var fabColor: Color
    var fabSize: CGFloat
    var fabWidth: CGFloat
    var position: FABPosition
    var offsetX: CGFloat
    var offsetBottom: CGFloat
    var tucked: CGFloat
    var iconName: String?
    var iconImageUrl: String?

    init(customizations: [String: Any]?, screenWidth: Double = 0) {
        let look = Launcher.resolve(customizations, screenWidth: screenWidth)
        self.look = look
        self.fabColor = Color(hex: look.solid)
        self.fabSize = CGFloat(look.size)
        self.fabWidth = CGFloat(look.width)
        self.position = look.position == "left" ? .left : .right
        self.offsetX = CGFloat(look.side)
        self.offsetBottom = CGFloat(look.bottom)
        self.tucked = CGFloat(look.tucked)
        self.iconName = look.iconId
        self.iconImageUrl = look.imageUrl
    }
}

// MARK: - SVG Icon Shape

/// All 15 web widget icons + default.
/// Drawn from the web widget's SVG paths (Utils/SVGPathParser.swift).
private struct BubbleIconView: View {
    let iconName: String?
    let color: Color
    let size: CGFloat

    private static let viewBoxes: [String: (CGFloat, CGFloat, CGFloat, CGFloat)] = [
        "WidgetBubbleIcon1": (0,0,30,30),
        "WidgetBubbleIcon2": (0,0,24,24),
        "WidgetBubbleIcon3": (0,1,15,15),
        "WidgetBubbleIcon4": (0,1,15,15),
        "WidgetBubbleIcon5": (0,0,24,24),
        "WidgetBubbleIcon6": (0,200,1900,1900),
        "WidgetBubbleIcon7": (0,0,512,512),
        "WidgetBubbleIcon8": (0,0,512,512),
        "WidgetBubbleIcon9": (0,0,512,512),
        "WidgetBubbleIcon10": (0,0,512,512),
        "WidgetBubbleIcon11": (0,0,512,512),
        "WidgetBubbleIcon12": (0,2,24,24),
        "WidgetBubbleIcon13": (0,2,24,24),
        "WidgetBubbleIcon14": (0,1,23,23),
        "WidgetBubbleIcon15": (0,2,24,24),
    ]

    // Only filled-path icons stored (stroke icons fall back to default on <iOS17)
    private static let svgPaths: [String: [String]] = [
        "WidgetBubbleIcon1": [
            "M16 19a6.99 6.99 0 0 1-5.833-3.129l1.666-1.107a5 5 0 0 0 8.334 0l1.666 1.107A6.99 6.99 0 0 1 16 19m4-11a2 2 0 1 0 2 2a1.98 1.98 0 0 0-2-2m-8 0a2 2 0 1 0 2 2a1.98 1.98 0 0 0-2-2",
            "M17.736 30L16 29l4-7h6a1.997 1.997 0 0 0 2-2V6a1.997 1.997 0 0 0-2-2H6a1.997 1.997 0 0 0-2 2v14a1.997 1.997 0 0 0 2 2h9v2H6a4 4 0 0 1-4-4V6a3.999 3.999 0 0 1 4-4h20a3.999 3.999 0 0 1 4 4v14a4 4 0 0 1-4 4h-4.835Z",
        ],
        "WidgetBubbleIcon2": [
            "M11.999 0c-2.25 0-4.5.06-6.6.21a5.57 5.57 0 0 0-5.19 5.1c-.24 3.21-.27 6.39-.06 9.6a5.644 5.644 0 0 0 5.7 5.19h3.15v-3.9h-3.15c-.93.03-1.74-.63-1.83-1.56c-.18-3-.15-6 .06-9c.06-.84.72-1.47 1.56-1.53c2.04-.15 4.2-.21 6.36-.21s4.32.09 6.36.18c.81.06 1.5.69 1.56 1.53c.24 3 .24 6 .06 9c-.12.93-.9 1.62-1.83 1.59h-3.15l-6 3.9V24l6-3.9h3.15c2.97.03 5.46-2.25 5.7-5.19c.21-3.18.18-6.39-.03-9.57a5.57 5.57 0 0 0-5.19-5.1c-2.13-.18-4.38-.24-6.63-.24m-5.04 8.76c-.36 0-.66.3-.66.66v2.34c0 .33.18.63.48.78c1.62.78 3.42 1.2 5.22 1.26c1.8-.06 3.6-.48 5.22-1.26c.3-.15.48-.45.48-.78V9.42c0-.09-.03-.15-.09-.21a.648.648 0 0 0-.87-.36c-1.5.66-3.12 1.02-4.77 1.05c-1.65-.03-3.27-.42-4.77-1.08a.566.566 0 0 0-.24-.06",
        ],
        "WidgetBubbleIcon3": [
            "M7.5 5a1.5 1.5 0 1 0 0 3a1.5 1.5 0 0 0 0-3",
            "M9 2H8V0H7v2H6a6 6 0 0 0 0 12h3c.13 0 .26-.004.389-.013l3.99.998a.5.5 0 0 0 .606-.606l-.577-2.309A6 6 0 0 0 9 2M5 6.5a2.5 2.5 0 1 1 5 0a2.5 2.5 0 0 1-5 0M7.5 12a4.483 4.483 0 0 1-2.813-.987l.626-.78c.599.48 1.359.767 2.187.767c.828 0 1.588-.287 2.187-.767l.626.78A4.483 4.483 0 0 1 7.5 12",
        ],
        "WidgetBubbleIcon4": [
            "M9 2.5V2zm-3 0V3zm6.856 9.422l-.35-.356l-.205.2l.07.277zM13.5 14.5l-.121.485a.5.5 0 0 0 .606-.606zm-4-1l-.354-.354l-.624.625l.857.214zm.025-.025l.353.354a.5.5 0 0 0-.4-.852zM.5 8H0zM7 0v2.5h1V0zm2 2H6v1h3zm6 6a6 6 0 0 0-6-6v1a5 5 0 0 1 5 5zm-1.794 4.279A5.983 5.983 0 0 0 15 7.999h-1a4.983 4.983 0 0 1-1.495 3.567zm.78 2.1L13.34 11.8l-.97.242l.644 2.578zm-4.607-.394l4 1l.242-.97l-4-1zm-.208-.863l-.025.024l.708.707l.024-.024zM9 14c.193 0 .384-.01.572-.027l-.094-.996A5.058 5.058 0 0 1 9 13zm-3 0h3v-1H6zM0 8a6 6 0 0 0 6 6v-1a5 5 0 0 1-5-5zm6-6a6 6 0 0 0-6 6h1a5 5 0 0 1 5-5zm1.5 6A1.5 1.5 0 0 1 6 6.5H5A2.5 2.5 0 0 0 7.5 9zM9 6.5A1.5 1.5 0 0 1 7.5 8v1A2.5 2.5 0 0 0 10 6.5zM7.5 5A1.5 1.5 0 0 1 9 6.5h1A2.5 2.5 0 0 0 7.5 4zm0-1A2.5 2.5 0 0 0 5 6.5h1A1.5 1.5 0 0 1 7.5 5zm0 8c1.064 0 2.042-.37 2.813-.987l-.626-.78c-.6.48-1.359.767-2.187.767zm-2.813-.987c.77.617 1.75.987 2.813.987v-1a3.483 3.483 0 0 1-2.187-.767z",
        ],
        "WidgetBubbleIcon6": [
            "M768 1024H640V896h128zm512 0h-128V896h128zm512-128v256h-128v320q0 40-15 75t-41 61t-61 41t-75 15h-264l-440 376v-376H448q-40 0-75-15t-61-41t-41-61t-15-75v-320H128V896h128V704q0-40 15-75t41-61t61-41t75-15h448V303q-29-17-46-47t-18-64q0-27 10-50t27-40t41-28t50-10q27 0 50 10t40 27t28 41t10 50q0 34-17 64t-47 47v209h448q40 0 75 15t61 41t41 61t15 75v192zm-256-192q0-26-19-45t-45-19H448q-26 0-45 19t-19 45v768q0 26 19 45t45 19h448v226l264-226h312q26 0 45-19t19-45zm-851 462q55 55 126 84t149 30q78 0 149-29t126-85l90 91q-73 73-167 112t-198 39q-103 0-197-39t-168-112z",
        ],
        "WidgetBubbleIcon5": [
            "M18 4a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-5l-5 3v-3H6a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3zM9.5 9h.01m4.99 0h.01",
            "M9.5 13a3.5 3.5 0 0 0 5 0",
        ],
        "WidgetBubbleIcon7": [
            "M408 64H104a56.16 56.16 0 0 0-56 56v192a56.16 56.16 0 0 0 56 56h40v80l93.72-78.14a8 8 0 0 1 5.13-1.86H408a56.16 56.16 0 0 0 56-56V120a56.16 56.16 0 0 0-56-56Z",
        ],
        "WidgetBubbleIcon8": [
            "M456 48H56a24 24 0 0 0-24 24v288a24 24 0 0 0 24 24h72v80l117.74-80H456a24 24 0 0 0 24-24V72a24 24 0 0 0-24-24M160 248a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32",
        ],
        "WidgetBubbleIcon9": [
            "M408 64H104a56.16 56.16 0 0 0-56 56v192a56.16 56.16 0 0 0 56 56h40v80l93.72-78.14a8 8 0 0 1 5.13-1.86H408a56.16 56.16 0 0 0 56-56V120a56.16 56.16 0 0 0-56-56Z",
        ],
        "WidgetBubbleIcon10": [
            "M408 48H104a72.08 72.08 0 0 0-72 72v192a72.08 72.08 0 0 0 72 72h24v64a16 16 0 0 0 26.25 12.29L245.74 384H408a72.08 72.08 0 0 0 72-72V120a72.08 72.08 0 0 0-72-72M160 248a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32",
        ],
        "WidgetBubbleIcon11": [
            "M144 464a16 16 0 0 1-16-16v-64h-24a72.08 72.08 0 0 1-72-72V120a72.08 72.08 0 0 1 72-72h304a72.08 72.08 0 0 1 72 72v192a72.08 72.08 0 0 1-72 72H245.74l-91.49 76.29A16.05 16.05 0 0 1 144 464",
        ],
        "WidgetBubbleIcon13": [
            "M12 8V4H8",
            "M2 14h2m16 0h2m-7-1v2m-6-2v2",
        ],
        "WidgetBubbleIcon14": [
            "M8.125 13a2 2 0 1 0 0-4a2 2 0 0 0 0 4m0-1.5a.5.5 0 1 0 0-1a.5.5 0 0 0 0 1m10-.5a2 2 0 1 1-4 0a2 2 0 0 1 4 0m-1.5 0a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0",
            "M2.749 14.666A6 6 0 0 0 8.125 18h8c2.44 0 4.54-1.456 5.478-3.547A2.997 2.997 0 0 0 22.875 12c0-1.013-.503-1.91-1.272-2.452A6.001 6.001 0 0 0 16.125 6h-8A6 6 0 0 0 2.75 9.334a3 3 0 0 0 0 5.332M8.125 8h8c1.384 0 2.603.702 3.322 1.77c.276.69.428 1.442.428 2.23s-.152 1.54-.428 2.23A3.996 3.996 0 0 1 16.125 16h-8a4 4 0 0 1 0-8",
        ],
        "WidgetBubbleIcon12": [
            "M21.928 11.607c-.202-.488-.635-.605-.928-.633V8c0-1.103-.897-2-2-2h-6V4.61c.305-.274.5-.668.5-1.11a1.5 1.5 0 0 0-3 0c0 .442.195.836.5 1.11V6H5c-1.103 0-2 .897-2 2v2.997l-.082.006A1 1 0 0 0 1.99 12v2a1 1 0 0 0 1 1H3v5c0 1.103.897 2 2 2h14c1.103 0 2-.897 2-2v-5a1 1 0 0 0 1-1v-1.938a1.006 1.006 0 0 0-.072-.455M5 20V8h14l.001 3.996L19 12v2l.001.005l.001 5.995z",
        ],
        "WidgetBubbleIcon15": [
            "M21 10.975V8a2 2 0 0 0-2-2h-6V4.688c.305-.274.5-.668.5-1.11a1.5 1.5 0 0 0-3 0c0 .442.195.836.5 1.11V6H5a2 2 0 0 0-2 2v2.998l-.072.005A.999.999 0 0 0 2 12v2a1 1 0 0 0 1 1v5a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5a1 1 0 0 0 1-1v-1.938a1.004 1.004 0 0 0-.072-.455c-.202-.488-.635-.605-.928-.632M7 12c0-1.104.672-2 1.5-2s1.5.896 1.5 2s-.672 2-1.5 2S7 13.104 7 12m8.998 6c-1.001-.003-7.997 0-7.998 0v-2s7.001-.002 8.002 0zm-.498-4c-.828 0-1.5-.896-1.5-2s.672-2 1.5-2s1.5.896 1.5 2s-.672 2-1.5 2",
        ],
    ]

    private static let defaultPath = "M21.5 18C21.5 18 20.5 18.5 20.5 20.1453V21.2858V22.5287V23.3572C20.5 24.131 20.0184 24.1046 19.3517 23.7118L18.75 23.3572L13.5 20C12.8174 19.6587 12.6007 19.5504 12.3729 19.516C12.267 19.5 12.1587 19.5 12 19.5H7.5C2.5 19.5 0 17.5 0 12.5V7.5C0 2.5 2.5 0 7.5 0H16.5C21.5 0 24 2.5 24 7.5V12.5C24 17.5 21.5 18 21.5 18Z"
    private static let defaultVB: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, -1, 24, 25)

    var body: some View {
        if #available(iOS 17.0, *) {
            svgIconView
        } else {
            // Fallback: simple filled chat bubble
            fallbackBubble
        }
    }

    @available(iOS 17.0, *)
    private var svgIconView: some View {
        let name = iconName
        let vb = name.flatMap { Self.viewBoxes[$0] } ?? Self.defaultVB
        let pathStrings = name.flatMap { Self.svgPaths[$0] } ?? [Self.defaultPath]
        let (vbMinX, vbMinY, vbW, vbH) = vb
        let scale = min(size / vbW, size / vbH)
        let scaledW = vbW * scale, scaledH = vbH * scale
        let tx = (size - scaledW) / 2 - vbMinX * scale
        let ty = (size - scaledH) / 2 - vbMinY * scale

        return Canvas { context, canvasSize in
            for svgStr in pathStrings {
                var p = Path.fromSVG(svgStr)
                let transform = CGAffineTransform(translationX: tx, y: ty)
                    .scaledBy(x: scale, y: scale)
                p = p.applying(transform)
                context.fill(p, with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackBubble: some View {
        // Simple rounded chat bubble for iOS < 17
        Image(systemName: "bubble.left.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Close Icon

private struct CloseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pad = rect.width * 0.24
        p.move(to: CGPoint(x: rect.minX + pad, y: rect.minY + pad))
        p.addLine(to: CGPoint(x: rect.maxX - pad, y: rect.maxY - pad))
        p.move(to: CGPoint(x: rect.maxX - pad, y: rect.minY + pad))
        p.addLine(to: CGPoint(x: rect.minX + pad, y: rect.maxY - pad))
        return p
    }
}

// MARK: - FAB Button

@available(iOS 15.0, *)
private struct ConferBotFABButton: View {
    let customizations: WidgetCustomizations
    let isOpen: Bool
    let unreadCount: Int
    /// The entrance, attention loop and idle call (LauncherFxModel); `fxLive` while one of them moves the button.
    @ObservedObject var fx: LauncherFxModel
    let attentionOn: Bool
    let fxLive: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    // Motion (Core/Customization/LauncherMotion): the moment playing, the ripple, idle moments played.
    @State private var moment: (state: String, start: Date)?
    @State private var ripple: (start: Date, delay: Double, iterations: Int)?
    @State private var played = 0
    @State private var idleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The owner's mascot on a soft light button (launcherStyle.ts "mascot"), unless an image was uploaded.
    private var mascotStyle: Bool { customizations.look.style == "mascot" && customizations.iconImageUrl == nil }

    /// Nothing moves for an image, avatar or mascot launcher (the mascot has its own moods), or when the phone asks for reduced motion.
    private var still: Bool {
        reduceMotion || customizations.iconImageUrl != nil || customizations.look.style == "avatar" || mascotStyle || !ConferBot.shared.hasServerLook
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: moment == nil && ripple == nil && !fxLive)) { timeline in
            content(now: timeline.date)
        }
        .onAppear {
            guard !still else { return }
            // The ripple after the launcher settles (whatever the motion mode), then idle moments.
            ripple = (Date(), LauncherMotion.rippleDelay, LauncherMotion.rippleIter)
            scheduleIdle()
        }
        .onDisappear { idleTask?.cancel() }
        .onChange(of: unreadCount) { [old = unreadCount] new in
            // A message while the chat is closed: the icon reacts and the ripple plays once more.
            guard new > old, !isOpen, !still else { return }
            if customizations.look.animation != "off" { moment = ("msg", Date()) }
            ripple = (Date(), 0, 1)
        }
        .onChange(of: isOpen) { open in
            if open {
                LauncherFxSession.openedAt = Date().timeIntervalSince1970 * 1000
                moment = nil
                ripple = nil
                idleTask?.cancel()
            }
        }
        // The attention loop pauses while an idle or message moment plays.
        .onChange(of: moment != nil) { fx.inMoment = $0 }
    }

    /// Idle moments: the first ~2s in, then the plan's pace, never after the chat was opened.
    private func scheduleIdle() {
        idleTask?.cancel()
        let mode = customizations.look.animation
        idleTask = Task { @MainActor in
            while let wait = LauncherMotion.nextIdleDelay(mode, played: played) {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
                if Task.isCancelled || isOpen { return }
                if LauncherFxSession.openedRecently(Date().timeIntervalSince1970 * 1000) { return }
                played += 1
                // A launcher attention is moving the button: this moment holds off (it still counts).
                if !fx.attention.onLauncher { moment = ("idle", Date()) }
            }
        }
    }

    private func frameAt(_ now: Date) -> [OpFrame?]? {
        guard let m = moment, !isOpen else { return nil }
        let ms = now.timeIntervalSince(m.start) * 1000
        if ms >= LauncherMotion.momentMs {
            DispatchQueue.main.async { if moment?.start == m.start { moment = nil } }
            return nil
        }
        guard let icon = LauncherIcons.byId(customizations.iconName) else { return nil }
        return LauncherMotion.iconFrame(icon, state: m.state, t: ms / 1000)
    }

    private func ringsAt(_ now: Date) -> [MotionRing?] {
        guard let r = ripple, !isOpen else { return [nil, nil] }
        let t = now.timeIntervalSince(r.start)
        // A launcher attention loop takes the place of the three ripples after load.
        if (r.iterations > 1 && fx.attention.onLauncher) || t > r.delay + LauncherMotion.rippleGap + LauncherMotion.rippleDur * Double(r.iterations) {
            DispatchQueue.main.async { if ripple?.start == r.start { ripple = nil } }
            return [nil, nil]
        }
        return [LauncherMotion.rippleRing(t, ring: 0, iterations: r.iterations, delay: r.delay),
                LauncherMotion.rippleRing(t, ring: 1, iterations: r.iterations, delay: r.delay)]
    }

    /// The shine's gloss sweeping across the button (the button clips it).
    @ViewBuilder
    private func gloss(_ shape: BubbleShape) -> some View {
        if attentionOn, fx.attention.has("shine"), let v = fx.attention.part("shine", fx.attention.elapsed) {
            Canvas { ctx, size in LauncherFxDraw.gloss(ctx, size.width, size.height, v) }
                .clipShape(shape)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let look = customizations.look
        let frame = still ? nil : frameAt(now)
        let rings = still ? [nil, nil] : ringsAt(now)
        let iconSize = CGFloat(look.glyph)
        let size = customizations.fabSize
        let shape = BubbleShape(corners: look.corners)
        let ink = Color(hex: look.ink)
        let showLabel = look.style == "label" && customizations.iconImageUrl == nil
        let avatar = look.style == "avatar" && customizations.iconImageUrl == nil ? look.avatar : nil

        ZStack {
            // The pulse's two rings in the launcher's colour, under the button.
            if attentionOn && fx.attention.has("ring") {
                ForEach(["ring", "ring2"], id: \.self) { part in
                    let v = fx.attention.part(part, fx.attention.elapsed)
                    shape.stroke(customizations.fabColor, lineWidth: 2.5)
                        .frame(width: customizations.fabWidth, height: size)
                        .scaleEffect(x: v?.sx ?? 1, y: v?.sy ?? 1)
                        .opacity(min(1, max(0, v?.o ?? 0)))
                        .allowsHitTesting(false)
                }
            }
            // The ripple: rings of the launcher's colour growing out from behind it.
            ForEach(0..<2, id: \.self) { k in
                if let ring = rings[k] {
                    shape.fill(customizations.fabColor)
                        .frame(width: customizations.fabWidth, height: size)
                        .scaleEffect(ring.scale)
                        .opacity(ring.opacity)
                        .allowsHitTesting(false)
                }
            }
            // The label pill draws its own background round the text.
            if !showLabel {
            Group {
                if let g = look.gradient {
                    // Left to right, as the web's linear-gradient(to right).
                    shape.fill(LinearGradient(colors: g.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing))
                } else {
                    shape.fill(customizations.fabColor)
                }
            }
            .frame(width: customizations.fabWidth, height: size)
            // A soft glow in the header colour (0 0 4px), as the web draws it.
            .shadow(color: Color(hex: look.glow).opacity(0.9), radius: 4, x: 0, y: 0)
            // The mascot's soft light button while closed; open, the brand colour with its cross.
            if mascotStyle && !isOpen {
                Canvas { ctx, sz in FxSvg.draw(ctx, mascotButtonXml(look.mascot.light), sz.width, sz.height) }
                    .frame(width: customizations.fabWidth, height: size)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            gloss(shape)
                .frame(width: customizations.fabWidth, height: size)
            }

            if isOpen {
                CloseIconShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.6, height: size * 0.6)
            } else if let url = customizations.iconImageUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(Circle())
            } else if mascotStyle {
                // Its bust over the rim, blinking; a reply landing makes it hop and smile.
                LauncherMascotView(mascot: look.mascot, width: customizations.fabWidth, height: size, unread: unreadCount, chatOpen: isOpen)
            } else if let url = avatar.flatMap(URL.init(string:)) {
                // The photo fills the button inside a thin ring of its colour, with an online dot.
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.white }
                    .frame(width: customizations.fabWidth - 6, height: size - 6)
                    .clipShape(BubbleShape(corners: look.corners))
                let dot = max(10, size * 0.24)
                Circle()
                    .fill(Color(hex: "#22c55e"))
                    .frame(width: dot, height: dot)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: size / 2 - dot / 2 - (size >= 56 ? 2 : 1), y: size / 2 - dot / 2 - (size >= 56 ? 2 : 1))
            } else if showLabel {
                HStack(spacing: size * 0.16) {
                    LauncherIconView(iconId: customizations.iconName, ink: ink, bg: customizations.fabColor, size: size * 0.52, frame: frame)
                    Text(look.label)
                        .font(.system(size: max(13, min(16, (size * 0.3).rounded())), weight: .semibold))
                        .foregroundColor(ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, (size - size * 0.52) / 2)
                .frame(minWidth: size, minHeight: size)
                .background(
                    Group {
                        if let g = look.gradient {
                            shape.fill(LinearGradient(colors: g.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing))
                        } else {
                            shape.fill(customizations.fabColor)
                        }
                    }
                )
                .overlay(gloss(shape))
            } else {
                // The web's launcher icons (Core/Customization/LauncherIcons).
                LauncherIconView(iconId: customizations.iconName, ink: ink, bg: customizations.fabColor, size: iconSize, frame: frame)
            }

            // Unread badge
            if unreadCount > 0 && !isOpen {
                VStack {
                    HStack {
                        Spacer()
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .frame(width: customizations.fabWidth, height: size)
            }
        }
        .modifier(LauncherFxMotion(fx: fx, attentionOn: attentionOn, isOpen: isOpen, glow: look.solid))
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // "Open chat" / "Close chat" (web launcher aria-label), the unread count read with it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? ChatText.closeLauncher : ChatText.openLauncher)
        .accessibilityValue(unreadCount > 0 && !isOpen ? "\(unreadCount)" : "")
        .accessibilityAddTraits(.isButton)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// The launcher moved by its effects, innermost first: a knock / tap jolts
/// it, the attention loop moves it (and the orbit's spark runs round it),
/// the ufo's beam draws it top to bottom, and the entrance holds it hidden
/// until its reveal, then plays its arrival.
@available(iOS 15.0, *)
private struct LauncherFxMotion: ViewModifier {
    @ObservedObject var fx: LauncherFxModel
    let attentionOn: Bool
    let isOpen: Bool
    let glow: String

    func body(content: Content) -> some View {
        let perf = isOpen ? nil : fx.idle.perf
        let jolt = (perf?.launcher.isEmpty == false) ? Keyframes.evaluate(perf!.launcher, fx.idle.elapsed) : FxValues.rest()
        let move = attentionOn && fx.attention.onLauncher ? fx.attention.part("self", fx.attention.elapsed) : nil
        let orbit = attentionOn && fx.attention.has("orbit") ? fx.attention.part("orbit", fx.attention.elapsed) : nil
        let look = fx.entrance.lookAt(fx.entrance.elapsed) ?? EntranceLook()
        content
            .scaleEffect(x: jolt.sx, y: jolt.sy)
            .offset(x: jolt.tx, y: jolt.ty)
            .overlay(GeometryReader { g in
                if let v = orbit {
                    Canvas { ctx, _ in
                        var c = ctx
                        c.translateBy(x: 20, y: 20)
                        LauncherFxDraw.orbit(c, g.size.width, g.size.height, v, glow: glow)
                    }
                    .frame(width: g.size.width + 40, height: g.size.height + 40)
                    .offset(x: -20, y: -20)
                    .allowsHitTesting(false)
                }
            })
            .scaleEffect(x: move?.sx ?? 1, y: move?.sy ?? 1)
            .rotationEffect(.degrees(move?.r ?? 0))
            .offset(x: (move?.tx ?? 0) + (move?.txp ?? 0) / 100 * (fx.launcher?.width ?? 0), y: move?.ty ?? 0)
            // Everything above the line shows (the glow and rings reach past the button).
            .mask(alignment: .top) {
                Rectangle()
                    .frame(width: 2000, height: 1000 + (look.shown < 0.999 ? max(0, (fx.launcher?.height ?? 0) * look.shown) : 1000))
                    .offset(y: -1000)
            }
            .scaleEffect(x: look.sx, y: look.sy)
            .rotationEffect(.degrees(look.r))
            .offset(x: look.tx, y: look.ty)
            .opacity(min(1, max(0, look.o)))
    }
}

/// The greeting card kept on screen while it leaves (RN ConferBotWidget's
/// leavingCard): the card last shown, and why it went (its x: close; else
/// open). Read and updated while the launcher draws.
final class GreetingLeave {
    private var last: GreetingCardData?
    private var leaving: (card: GreetingCardData, reason: String)?
    /// The x was tapped: the card that goes next is closed, not opened.
    var closing = false

    /// The card to draw: the one shown, else the one leaving and why.
    func drawn(_ shown: GreetingCardData?) -> (card: GreetingCardData, leaving: String?)? {
        if let s = shown {
            last = s
            leaving = nil
            closing = false
            return (s, nil)
        }
        if let l = last {
            leaving = (l, closing ? "close" : "open")
            last = nil
            closing = false
        }
        return leaving.map { ($0.card, $0.reason) }
    }

    /// Its leaving moves are over.
    func gone() { leaving = nil }
}

/// Where the launcher sits on the screen (global pt), before its effects move it.
private struct LauncherRectKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// What the launcher's effects keep between frames: the three controllers
/// (Core/Customization/LauncherFxControllers), a version bumped when what to
/// draw changes, where the launcher sits, and the mascot's drawing.
@available(iOS 15.0, *)
final class LauncherFxModel: ObservableObject {
    let entrance = LauncherEntranceController()
    let attention = LauncherAttentionController()
    let idle = LauncherIdleCallController(store: DefaultsIdleCallRestStore())
    @Published private(set) var version = 0
    /// The launcher's box on the screen (global pt).
    @Published var launcher: CGRect?
    /// An idle or message moment is playing (the attention loop pauses for it).
    @Published var inMoment = false

    init() {
        let bump: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.version += 1 }
        }
        entrance.onChange = bump
        attention.onChange = bump
        idle.onChange = bump
    }

    deinit {
        entrance.dispose()
        attention.onChange = nil
        idle.dispose()
    }

    /// The owner's mascot drawn for this call (its look, the launcher's colour, the arm pose).
    func mascotFor(_ perf: LauncherIdleCall.Performance, look: MascotArt.Look, accent: String) -> MascotArt.Layers {
        MascotDraw.layers(accent, arm: perf.mascot.arm, look: look, bust: false)
    }
}

/// The effects drawn round the launcher, behind it or in front of it, over the whole screen; they reach past it.
@available(iOS 15.0, *)
private struct LauncherFxStage: View {
    @ObservedObject var fx: LauncherFxModel
    let front: Bool
    let attentionOn: Bool
    let perf: LauncherIdleCall.Performance?
    let mascot: MascotArt.Layers?
    /// The owner's mascot's character (its joints).
    var shape = "blob"
    let live: Bool

    var body: some View {
        let plan = fx.entrance.phase == "play" ? fx.entrance.plan : nil
        let shadow = !front && attentionOn && fx.attention.has("shadow")
        let drawsMascot = perf != nil && perf!.front == front && mascot != nil
        let drawsPlan = plan != nil && plan!.behind != front
        if fx.launcher != nil && (shadow || drawsMascot || drawsPlan) {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                TimelineView(.animation(paused: !live)) { _ in
                    Canvas { ctx, _ in
                        guard let r = fx.launcher else { return }
                        var c = ctx
                        c.translateBy(x: r.minX - origin.x, y: r.minY - origin.y)
                        if shadow, let v = fx.attention.part("shadow", fx.attention.elapsed) {
                            LauncherFxDraw.bounceShadow(c, r.width, r.height, v)
                        }
                        if drawsMascot { LauncherFxDraw.idleCall(c, perf!, mascot!, shape: shape, fx.idle.elapsed) }
                        if drawsPlan { LauncherFxDraw.entrance(c, plan!, fx.entrance.elapsed) }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

/// The idle call's speech bubble, kept on the screen, its tail on the mascot.
@available(iOS 15.0, *)
private struct IdleCallBubbleLayer: View {
    @ObservedObject var fx: LauncherFxModel
    let perf: LauncherIdleCall.Performance
    let line: String
    let onOpen: () -> Void
    @State private var size: CGSize = .zero

    private func now() -> FxValues { Keyframes.evaluate([perf.bubble], fx.idle.elapsed, base: ["o": 0]) }

    var body: some View {
        if let rect = fx.launcher {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let screenW = UIScreen.main.bounds.width
                let bw = size.width, bh = size.height
                let left = min(max(8, rect.minX + perf.sayX - bw / 2), max(8, screenW - bw - 8))
                let tail = min(max(14, perf.sayX - (left - rect.minX)), max(14, bw - 14))
                TimelineView(.animation(paused: fx.idle.perf == nil)) { _ in
                    let v = now()
                    IdleCallBubble(line: line, tail: tail) {
                        if now().o > 0.05 {
                            fx.idle.stop()
                            onOpen()
                        }
                    }
                    .background(GeometryReader { g in Color.clear.preference(key: BubbleSizeKey.self, value: g.size) })
                    .scaleEffect(x: v.sx, y: v.sy)
                    .offset(y: v.ty)
                    .opacity(size == .zero ? 0 : min(1, max(0, v.o)))
                    .offset(x: left - origin.x, y: rect.minY + perf.sayY - 10 - bh - origin.y)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
            .onPreferenceChange(BubbleSizeKey.self) { size = $0 }
        }
    }
}

private struct BubbleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Public Config

public struct ConferBotFABConfig {
    public init() {}
}

// MARK: - Main Overlay

@available(iOS 15.0, *)
public struct ConferBotWidgetOverlay<Content: View>: View {
    @ObservedObject private var bot = ConferBot.shared
    @State private var isChatOpen = false
    /// The owner's auto-open, waiting for its delay (AutoOpen).
    @State private var autoOpen: DispatchWorkItem?
    /// The greeting card by the closed launcher (GreetingCardView, Core/Customization/Greeting).
    @StateObject private var greeting = GreetingController()
    /// The entrance, attention loop and idle call (Core/Customization/LauncherFxControllers).
    @StateObject private var fx = LauncherFxModel()
    /// The greeting card stays drawn while it leaves (its collapse or fade, the figure's hand-off or bow).
    @State private var cardLeave = GreetingLeave()
    @State private var cardGone = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let content: Content
    private let config: ConferBotFABConfig

    public init(
        config: ConferBotFABConfig = ConferBotFABConfig(),
        @ViewBuilder content: () -> Content
    ) {
        self.config = config
        self.content = content()
    }

    private var customizations: WidgetCustomizations {
        WidgetCustomizations(customizations: bot.serverCustomizations, screenWidth: Double(UIScreen.main.bounds.width))
    }

    /// The chat's state handed to the effects (each call is cheap; the controllers only report a change).
    private func syncFx(_ c: WidgetCustomizations, hasLook: Bool, botId: String) {
        let look = c.look
        // Decided as the settings arrive, before the launcher is drawn with them (so it never flashes in first).
        if hasLook {
            fx.entrance.decide(look.entrance, botId: botId, reduced: reduceMotion, chatOpen: isChatOpen)
            fx.idle.start(look.idleCall, delay: look.idleCallDelay, botId: botId, reduced: reduceMotion)
        }
        let cardShown = greeting.card != nil && !isChatOpen
        let showLabel = look.style == "label" && c.iconImageUrl == nil
        if hasLook {
            fx.attention.update(mode: look.attention, enabled: true, reduced: reduceMotion, chatOpen: isChatOpen, cardShown: cardShown,
                                moment: fx.inMoment, entranceBusy: fx.entrance.busy, hasSize: fx.launcher != nil, wide: showLabel)
        }
        fx.idle.chatOpen = isChatOpen
        fx.idle.entranceBusy = fx.entrance.busy
        fx.idle.cardShown = cardShown
        fx.idle.width = fx.launcher.map { Double($0.width) }
        fx.idle.height = fx.launcher.map { Double($0.height) }
        fx.idle.position = c.position == .left ? "left" : "right"
        if let r = fx.launcher, hasLook {
            fx.entrance.laidOut {
                let screen = UIScreen.main.bounds.size
                return LauncherEntrance.stage(
                    width: r.width, height: r.height, position: c.position == .left ? "left" : "right",
                    screenWidth: screen.width, screenHeight: screen.height,
                    side: c.position == .left ? r.minX : screen.width - r.maxX,
                    bottom: screen.height - r.maxY, accent: look.solid)
            }
        }
    }

    public var body: some View {
        let c = customizations
        let hasLook = bot.serverCustomizations != nil
        let _ = fx.version
        let _ = syncFx(c, hasLook: hasLook, botId: bot.activeBotId ?? "default")
        // The greeting card: 12 above the launcher, its edge in line with it.
        let cardEdge = max(8, c.offsetX - c.tucked)
        let attentionOn = fx.attention.running && !isChatOpen
        let perf = isChatOpen ? nil : fx.idle.perf
        let mascot = perf.map { fx.mascotFor($0, look: c.look.mascot.look, accent: c.look.solid) }
        let fxLive = fx.entrance.active || attentionOn || perf != nil
        let _ = cardGone
        let drawn = cardLeave.drawn(isChatOpen ? nil : greeting.card)

        ZStack {
            content

            if let card = drawn?.card {
                VStack {
                    Spacer()
                    HStack {
                        if c.position == .right { Spacer() }
                        TimelineView(.animation(paused: !fxLive)) { _ in
                            // Hidden until the launcher lands, then fading up; the wave / float loop.
                            let l = fx.entrance.lookAt(fx.entrance.elapsed)
                            let selfMove = attentionOn && fx.attention.target == "greeting" ? fx.attention.part("self", fx.attention.elapsed) : nil
                            let hand = attentionOn && fx.attention.has("hand") && !card.text.contains(LauncherAttention.wavingHand)
                                ? fx.attention.part("hand", fx.attention.elapsed) : nil
                            GreetingCardView(
                                card: card,
                                alignLeft: c.position == .left,
                                onPress: { if greeting.card != nil { pressGreeting(card) } },
                                onClose: {
                                    cardLeave.closing = true
                                    greeting.dismiss()
                                    fx.idle.greetingClosed()
                                },
                                onStarter: { text in
                                    guard greeting.card != nil else { return }
                                    greeting.closeForNow()
                                    openChat()
                                    send(text)
                                },
                                leaving: drawn?.leaving,
                                launcher: fx.launcher?.size,
                                onGone: {
                                    cardLeave.gone()
                                    cardGone += 1
                                }
                            )
                            // The wave: a waving hand on the card's corner, unless its text has its own.
                            .overlay(alignment: .topLeading) {
                                if let h = hand {
                                    Text(LauncherAttention.wavingHand)
                                        .font(.system(size: 20))
                                        .frame(width: LauncherFxDraw.handW, height: LauncherFxDraw.handH)
                                        .rotationEffect(.degrees(h.r), anchor: UnitPoint(x: 0.7, y: 0.8))
                                        .offset(x: -9, y: -13)
                                        .allowsHitTesting(false)
                                }
                            }
                            .offset(x: selfMove?.tx ?? 0, y: (l?.greetingTy ?? 0) + (selfMove?.ty ?? 0))
                            .opacity(min(1, max(0, l?.greetingO ?? 1)))
                        }
                        if c.position == .left { Spacer() }
                    }
                    .padding(c.position == .right ? .trailing : .leading, cardEdge)
                    .padding(.bottom, c.offsetBottom + c.fabSize + 12)
                }
                // It leaves on its own moves (GreetingCardView `leaving`).
                .transition(.identity)
                .zIndex(1)
            }

            // Behind the launcher: the bounce's shadow, the idle call's mascot, the portal.
            if !isChatOpen {
                LauncherFxStage(fx: fx, front: false, attentionOn: attentionOn, perf: perf, mascot: mascot, shape: c.look.mascot.look.shape, live: fxLive)
                    .zIndex(2)
            }

            // FAB
            VStack {
                Spacer()
                HStack {
                    if c.position == .right { Spacer() }
                    ConferBotFABButton(
                        customizations: c,
                        isOpen: isChatOpen,
                        unreadCount: bot.unreadCount,
                        fx: fx,
                        attentionOn: attentionOn,
                        fxLive: fxLive,
                        onTap: {
                            if isChatOpen {
                                isChatOpen = false
                            } else {
                                openChat()
                            }
                        }
                    )
                    // Where the launcher sits, before the effects move it.
                    .background(GeometryReader { g in Color.clear.preference(key: LauncherRectKey.self, value: g.frame(in: .global)) })
                    if c.position == .left { Spacer() }
                }
                .padding(c.position == .right ? .trailing : .leading, c.offsetX)
                .padding(.bottom, c.offsetBottom)
                // Peek: the tab is tucked part-way off screen.
                .offset(x: c.position == .right ? c.tucked : -c.tucked)
            }
            .zIndex(3)

            // In front of the launcher: a knock / tap mascot and the other entrances.
            if !isChatOpen {
                LauncherFxStage(fx: fx, front: true, attentionOn: attentionOn, perf: perf, mascot: mascot, shape: c.look.mascot.look.shape, live: fxLive)
                    .zIndex(4)
            }

            // The idle call's speech bubble (none while the greeting is up).
            if let p = perf, p.talks {
                IdleCallBubbleLayer(fx: fx, perf: p, line: c.look.idleCallText, onOpen: openChat)
                    .zIndex(5)
            }
        }
        .onPreferenceChange(LauncherRectKey.self) { r in
            guard let r = r else { return }
            if let old = fx.launcher, abs(old.minX - r.minX) <= 0.5, abs(old.minY - r.minY) <= 0.5,
               abs(old.width - r.width) <= 0.5, abs(old.height - r.height) <= 0.5 { return }
            fx.launcher = r
        }
        .sheet(isPresented: $isChatOpen) {
            ChatView()
        }
        .onReceive(bot.$serverCustomizations) { customs in
            greeting.update(customizations: customs, chatOpen: isChatOpen, botId: bot.activeBotId, agentBot: bot.agentBot)
            planAutoOpen(customs)
        }
        .onReceive(bot.$agentBot) { agent in
            greeting.update(customizations: bot.serverCustomizations, chatOpen: isChatOpen, botId: bot.activeBotId, agentBot: agent)
        }
        // A tapped Conferbot notification (handlePushNotification): the chat opens on it.
        .onReceive(bot.$pushToOpen) { p in
            guard p != nil else { return }
            bot.pushOpened()
            openChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in fx.idle.appActive = true }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in fx.idle.appActive = false }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in fx.idle.keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in fx.idle.keyboard = false }
        .onChange(of: isChatOpen) { open in
            // A close (of any open) blocks auto-open for 2 minutes.
            if !open { AutoOpen.Memory.noteClosed(bot.activeBotId ?? "bot") }
            // Opening the chat: chatted, and the card rests as if closed.
            if open {
                greeting.chatOpened()
                // By any route: the entrance ends at once, and no call comes for a few days.
                LauncherFxSession.openedAt = Date().timeIntervalSince1970 * 1000
                fx.entrance.chatOpened()
                fx.idle.chatOpened()
                fx.idle.stop()
            }
            greeting.update(customizations: bot.serverCustomizations, chatOpen: open, botId: bot.activeBotId, agentBot: bot.agentBot)
        }
    }

    /// The owner's auto-open (botAutoOpen, botAutoOpenDelay seconds): first
    /// visit only, once per launch of the app, not within 2 minutes of a close.
    private func planAutoOpen(_ customs: [String: Any]?) {
        let key = bot.activeBotId ?? "bot"
        // A conversation they already have is theirs to reopen (web: !chatStarted).
        let started = bot.hasValidStoredSession() || !bot.messages.isEmpty
        guard let delay = AutoOpen.plan(customs, chatStarted: started, isOpen: isChatOpen,
                                        alreadyAutoOpened: AutoOpen.Memory.autoOpened(key),
                                        closedAt: AutoOpen.Memory.closedAt(key)) else {
            autoOpen?.cancel()
            autoOpen = nil
            return
        }
        // Already waiting (the settings were only repainted): the delay runs on.
        if let pending = autoOpen, !pending.isCancelled { return }
        let item = DispatchWorkItem {
            AutoOpen.Memory.noteAutoOpened(key)
            autoOpen = nil
            if !isChatOpen { openChat() }
        }
        autoOpen = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000, execute: item)
    }

    private func openChat() {
        guard !isChatOpen else { return }
        isChatOpen = true
        bot.resetUnreadCount()
    }

    /// The visitor's words, once the chat has opened. With the owner's home
    /// screen they go past it to the conversation, asked there.
    private func send(_ text: String) {
        if bot.home.isOn { return bot.home.showChat(text) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Task { try? await bot.sendMessage(text) }
        }
    }

    /// A tap on the card: open the chat (and send its words), or follow its link.
    private func pressGreeting(_ card: GreetingCardData) {
        greeting.closeForNow()
        if card.click == "link", let url = URL(string: card.linkUrl), !card.linkUrl.isEmpty {
            UIApplication.shared.open(url)
            return
        }
        openChat()
        if card.click == "send" { send(card.text) }
    }
}

// MARK: - View Modifier

@available(iOS 15.0, *)
extension View {
    /// Overlay a floating Conferbot FAB widget on top of this view.
    public func conferBotWidget(config: ConferBotFABConfig = ConferBotFABConfig()) -> some View {
        ConferBotWidgetOverlay(config: config) { self }
    }
}

// MARK: - SVG path

extension Path {
    /// A path from an SVG "d" attribute.
    static func fromSVG(_ d: String) -> Path {
        var path = Path()
        for segment in SVGPathParser.parse(d) {
            switch segment {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .cubic(let c1, let c2, let end): path.addCurve(to: end, control1: c1, control2: c2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
