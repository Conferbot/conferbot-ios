//
//  LauncherIcons.swift
//  Conferbot
//
//  The web widget's launcher icons as flat draw operations on a 24x24 grid
//  (generated from conferbot-widget src/svg/launcher): a path, its 2x3
//  transform, fill and stroke ("ink" = the launcher's icon colour, "bg" =
//  the launcher's own colour, or a hex; or a gradient), opacity, clip and
//  the motion part it belongs to. Pure data; the launcher view draws it.
//

import Foundation

public struct IconPaint: Codable, Equatable {
    public var c: String?
    public var g: Int?
    public var a: Double
}

public struct IconStop: Codable, Equatable {
    public var o: Double
    public var c: String
    public var a: Double
}

public struct IconGradient: Codable, Equatable {
    public var t: String
    public var x1: Double?, y1: Double?, x2: Double?, y2: Double?
    public var cx: Double?, cy: Double?, r: Double?
    public var stops: [IconStop]
}

public struct IconOp: Codable, Equatable {
    public var d: String
    public var m: [Double]?
    public var fill: IconPaint?
    public var stroke: IconPaint?
    public var sw: Double?
    public var cap: String?
    public var join: String?
    public var op: Double?
    public var rule: String?
    public var strokeFirst: Bool?
    public var clip: String?
    public var part: [String]?
}

public struct LauncherIcon: Codable, Equatable {
    public var id: String
    public var anim: String
    public var grads: [IconGradient]
    public var ops: [IconOp]
}

public enum LauncherIcons {
    /// The icon a bot without one (or with an unknown id) draws, as on the web.
    public static let defaultIcon = "WidgetBubbleIcon40"

    public static let all: [LauncherIcon] = {
        (try? JSONDecoder().decode([LauncherIcon].self, from: Data(LauncherIconsData.json.utf8))) ?? []
    }()

    private static let byIdMap: [String: LauncherIcon] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func byId(_ id: String?) -> LauncherIcon? {
        (id.flatMap { byIdMap[$0] }) ?? byIdMap[defaultIcon]
    }
}
