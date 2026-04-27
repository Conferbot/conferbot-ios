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

    var fabColor: Color
    var fabSize: CGFloat
    var fabBorderRadius: CGFloat
    var position: FABPosition
    var offsetX: CGFloat
    var offsetBottom: CGFloat
    var iconName: String?
    var iconType: String?
    var iconImageUrl: String?
    var ctaText: String?
    var ctaBorderRadius: CGFloat

    init(customizations: [String: Any]?) {
        let c = customizations ?? [:]

        func hexColor(_ key: String) -> Color? {
            guard let hex = c[key] as? String, !hex.isEmpty else { return nil }
            return Color(hex: hex)
        }

        self.fabColor = hexColor("widgetIconBgColor")
            ?? hexColor("headerBgColor")
            ?? Color(hex: "#1b55f3")

        let rawSize = (c["widgetSize"] as? NSNumber)?.doubleValue ?? 50.0
        self.fabSize = CGFloat(rawSize)

        if let br = (c["widgetBorderRadius"] as? NSNumber)?.doubleValue {
            self.fabBorderRadius = CGFloat(br)
        } else {
            self.fabBorderRadius = self.fabSize / 2
        }

        let pos = c["widgetPosition"] as? String
        self.position = pos == "left" ? .left : .right

        let offsetR = (c["widgetOffsetRight"] as? NSNumber)?.doubleValue ?? 10.0
        let offsetL = (c["widgetOffsetLeft"] as? NSNumber)?.doubleValue ?? 10.0
        self.offsetX = CGFloat(self.position == .left ? offsetL : offsetR)
        self.offsetBottom = CGFloat((c["widgetOffsetBottom"] as? NSNumber)?.doubleValue ?? 10.0)

        self.iconName = c["widgetIconSVG"] as? String
        self.iconType = c["widgetIconType"] as? String
        self.iconImageUrl = c["widgetIconImage"] as? String
        self.ctaText = c["chatIconCtaText"] as? String

        let ctaBr = CGFloat((c["widgetBorderRadius"] as? NSNumber)?.doubleValue ?? 50.0)
        self.ctaBorderRadius = min(ctaBr, 20)
    }
}

// MARK: - SVG Icon Shape

/// All 15 web widget icons + default.
/// Uses Path(svgPath:) on iOS 17+, fallback rounded-rect on older.
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
        "WidgetBubbleIcon8": [
            "M456 48H56a24 24 0 0 0-24 24v288a24 24 0 0 0 24 24h72v80l117.74-80H456a24 24 0 0 0 24-24V72a24 24 0 0 0-24-24M160 248a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32",
        ],
        "WidgetBubbleIcon10": [
            "M408 48H104a72.08 72.08 0 0 0-72 72v192a72.08 72.08 0 0 0 72 72h24v64a16 16 0 0 0 26.25 12.29L245.74 384H408a72.08 72.08 0 0 0 72-72V120a72.08 72.08 0 0 0-72-72M160 248a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32m96 0a32 32 0 1 1 32-32a32 32 0 0 1-32 32",
        ],
        "WidgetBubbleIcon11": [
            "M144 464a16 16 0 0 1-16-16v-64h-24a72.08 72.08 0 0 1-72-72V120a72.08 72.08 0 0 1 72-72h304a72.08 72.08 0 0 1 72 72v192a72.08 72.08 0 0 1-72 72H245.74l-91.49 76.29A16.05 16.05 0 0 1 144 464",
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
                var p = Path(svgPath: svgStr)
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

@available(iOS 14.0, *)
private struct ConferBotFABButton: View {
    let customizations: WidgetCustomizations
    let isOpen: Bool
    let unreadCount: Int
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        let iconSize = customizations.fabSize * 0.6

        ZStack {
            RoundedRectangle(cornerRadius: customizations.fabBorderRadius)
                .fill(customizations.fabColor)
                .frame(width: customizations.fabSize, height: customizations.fabSize)
                .shadow(
                    color: Color(.sRGB, red: 50/255, green: 50/255, blue: 93/255, opacity: 0.25),
                    radius: 27, x: 0, y: 13
                )

            if isOpen {
                CloseIconShape()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: iconSize, height: iconSize)
            } else {
                BubbleIconView(
                    iconName: customizations.iconName,
                    color: .white,
                    size: iconSize
                )
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
                .frame(width: customizations.fabSize, height: customizations.fabSize)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - CTA Tooltip

@available(iOS 14.0, *)
private struct ConferBotCTATooltip: View {
    let text: String
    let backgroundColor: Color
    let borderRadius: CGFloat
    let isVisible: Bool
    let onDismiss: () -> Void

    var body: some View {
        if !text.isEmpty {
            Button(action: onDismiss) {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(backgroundColor)
                    .cornerRadius(borderRadius)
            }
            .frame(maxWidth: 212, alignment: .leading)
            .shadow(
                color: Color(.sRGB, red: 50/255, green: 50/255, blue: 93/255, opacity: 0.25),
                radius: 27, x: 0, y: 13
            )
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        }
    }
}

// MARK: - Public Config

public struct ConferBotFABConfig {
    public init() {}
}

// MARK: - Main Overlay

@available(iOS 14.0, *)
public struct ConferBotWidgetOverlay<Content: View>: View {
    @ObservedObject private var bot = ConferBot.shared
    @State private var isChatOpen = false
    @State private var showCta = false

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
        WidgetCustomizations(customizations: bot.serverCustomizations)
    }

    public var body: some View {
        let c = customizations
        let ctaEdge = c.offsetX + c.fabSize + 10

        ZStack {
            content

            // CTA Tooltip
            if let ctaText = c.ctaText, !ctaText.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        if c.position == .right { Spacer() }
                        ConferBotCTATooltip(
                            text: ctaText,
                            backgroundColor: c.fabColor,
                            borderRadius: c.ctaBorderRadius,
                            isVisible: showCta && !isChatOpen,
                            onDismiss: { showCta = false }
                        )
                        if c.position == .left { Spacer() }
                    }
                    .padding(c.position == .right ? .trailing : .leading, ctaEdge)
                    .padding(.bottom, c.offsetBottom)
                }
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
                        onTap: {
                            if isChatOpen {
                                isChatOpen = false
                            } else {
                                isChatOpen = true
                                showCta = false
                                bot.resetUnreadCount()
                            }
                        }
                    )
                    if c.position == .left { Spacer() }
                }
                .padding(c.position == .right ? .trailing : .leading, c.offsetX)
                .padding(.bottom, c.offsetBottom)
            }
        }
        .sheet(isPresented: $isChatOpen) {
            ChatView()
        }
        .onReceive(bot.$serverCustomizations) { customs in
            guard let customs = customs,
                  let ctaText = customs["chatIconCtaText"] as? String,
                  !ctaText.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !isChatOpen { showCta = true }
            }
        }
    }
}

// MARK: - View Modifier

@available(iOS 14.0, *)
extension View {
    /// Overlay a floating Conferbot FAB widget on top of this view.
    public func conferBotWidget(config: ConferBotFABConfig = ConferBotFABConfig()) -> some View {
        ConferBotWidgetOverlay(config: config) { self }
    }
}
