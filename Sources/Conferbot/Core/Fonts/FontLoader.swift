//
//  FontLoader.swift
//  Conferbot
//
//  The chat's font, loaded (OwnerFont.swift; RN utils/fontLoader.ts and
//  hooks/useChatFont.ts). The owner's font, else the theme's, is fetched
//  from Google Fonts at run time: the css2 stylesheet (TrueType faces, as
//  Google sends to a client that is not a browser), then each upright face,
//  registered for this process with CTFontManagerRegisterGraphicsFont and
//  drawn by its PostScript name. The files are kept in Caches
//  (conferbot-fonts/<family>/<weight>.ttf), so a later launch registers them
//  without the network. On any failure the chat keeps the system font; a
//  failed family is tried again on the next update.
//
//  `ConferBot.shared.chatFont` holds it; the views ask `faceName(_:weight:)`
//  (ChatFontViews.swift turns it into a SwiftUI Font).
//

import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreText)
import CoreText
import CoreGraphics
#endif

@MainActor
public final class ChatFontLoader: ObservableObject {

    public enum Role { case body, display }

    /// The fonts picked for the owner's setting and the theme.
    @Published public private(set) var fonts = OwnerFont.ChatFonts(body: nil, display: nil)
    /// Loaded faces per family: weight -> PostScript name.
    @Published public private(set) var faces: [String: [Int: String]] = [:]

    private var loading: Set<String> = []
    var session: URLSession = .shared
    var cacheDir: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("conferbot-fonts", isDirectory: true)

    public init() {}

    /// The owner's font and the theme's changed (the bot's settings arrived, a theme switch).
    public func update(ownerFont: Any?, themeFont: String?, themeFontRole: String?) {
        let next = OwnerFont.chatFontsFor(ownerFont, themeFont: themeFont, themeFontRole: themeFontRole)
        if next != fonts { fonts = next }
        for pick in [next.body, next.display].compactMap({ $0 }) where pick.google != nil {
            load(pick)
        }
    }

    /// The face to draw `role` text of `weight` with: a loaded web face's
    /// PostScript name (the nearest weight), a system font's family, or nil
    /// (the system font).
    public func faceName(_ role: Role, weight: Int = 400) -> String? {
        guard let pick = role == .body ? fonts.body : fonts.display else { return nil }
        guard pick.google != nil else { return pick.family }
        let loaded = faces[pick.family] ?? [:]
        return OwnerFont.nearestWeight(Array(loaded.keys), weight).flatMap { loaded[$0] }
    }

    /// Whether any chat font applies (a quick check for the views).
    public var isSet: Bool { faceName(.body) != nil || faceName(.display) != nil }

    // MARK: - Loading

    private func load(_ pick: OwnerFont.FontPick) {
        let family = pick.family
        guard let query = pick.google, faces[family] == nil, !loading.contains(family) else { return }
        loading.insert(family)
        Task { @MainActor in
            let loaded = await self.fetchAndRegister(family: family, query: query)
            self.loading.remove(family)
            if !loaded.isEmpty { self.faces[family] = loaded }
        }
    }

    private func familyDir(_ family: String) -> URL? {
        let safe = family.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        return cacheDir?.appendingPathComponent(safe, isDirectory: true)
    }

    private func fetchAndRegister(family: String, query: String) async -> [Int: String] {
        // Kept from an earlier launch: no network.
        var out: [Int: String] = [:]
        if let dir = familyDir(family),
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "ttf" {
                if let weight = Int(file.deletingPathExtension().lastPathComponent),
                   let data = try? Data(contentsOf: file), let name = Self.register(data) {
                    out[weight] = name
                }
            }
            if !out.isEmpty { return out }
        }
        guard let cssURL = URL(string: OwnerFont.googleFontUrl(query)),
              let (cssData, response) = await fetch(cssURL),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
              let css = String(data: cssData, encoding: .utf8) else { return [:] }
        let upright = OwnerFont.parseFontFaces(css).filter { $0.style == "normal" }
        for face in upright where out[face.weight] == nil {
            guard let url = URL(string: face.url), let (data, _) = await fetch(url),
                  let name = Self.register(data) else { continue }
            out[face.weight] = name
            if let dir = familyDir(family) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: dir.appendingPathComponent("\(face.weight).ttf"))
            }
        }
        return out
    }

    /// One GET (dataTask: the package supports iOS 13).
    private func fetch(_ url: URL) async -> (Data, URLResponse)? {
        let session = self.session
        return await withCheckedContinuation { cont in
            session.dataTask(with: url) { data, response, error in
                if let data = data, let response = response, error == nil { cont.resume(returning: (data, response)) } else { cont.resume(returning: nil) }
            }.resume()
        }
    }

    /// Registers a TrueType / OpenType file for this process; its PostScript
    /// name, or nil when it is not a font. One already registered (the app
    /// bundles it, or a second load) counts as registered.
    nonisolated static func register(_ data: Data) -> String? {
        #if canImport(CoreText)
        guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return nil }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error) {
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
            // Already registered, or a font of that name is there (the
            // phone's own, the app's): drawn by the same name all the same.
            guard code == CTFontManagerError.alreadyRegistered.rawValue || code == CTFontManagerError.duplicatedName.rawValue else { return nil }
        }
        return name
        #else
        return nil
        #endif
    }
}
