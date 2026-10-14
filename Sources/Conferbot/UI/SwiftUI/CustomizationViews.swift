//
//  CustomizationViews.swift
//  Conferbot
//
//  Drawing the bot's settings (Core/Customization) the way the web widget
//  does: bubble corners per side, avatar shapes, and readable ink.
//

import SwiftUI

/// A rectangle with its own radius per corner (the web's 18/18/18/6 bubbles), iOS 13+.
struct BubbleShape: Shape {
    var corners: BubbleCorners

    func path(in rect: CGRect) -> Path {
        let maxR = min(rect.width, rect.height) / 2
        let tl = min(CGFloat(corners.topLeft), maxR), tr = min(CGFloat(corners.topRight), maxR)
        let br = min(CGFloat(corners.bottomRight), maxR), bl = min(CGFloat(corners.bottomLeft), maxR)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

extension ConferBot {
    /// True once the bot's own settings arrived (the screens keep the host app's look until then).
    var hasServerLook: Bool { serverCustomizations != nil }
}

extension Color {
    /// Black or white, whichever reads on the hex colour.
    static func ink(onHex hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        guard h.count == 6 else { return .white }
        let r = Double(v >> 16) / 255, g = Double(v >> 8 & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? .black : .white
    }
}
