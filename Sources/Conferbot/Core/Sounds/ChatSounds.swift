//
//  ChatSounds.swift
//  Conferbot
//
//  The chat's sounds, wired (MessageSound.swift; RN useChatSounds.ts and
//  utils/chatSounds.ts; web ts/chat/messageSound.ts and index.ts
//  _playToggleSound): a message arriving, the chat opening and closing, the
//  visitor sending, under the owner's messageSound, soundPack and launcher
//  sound, and the visitor's Sound on / off kept on the device (UserDefaults,
//  the web's key "conferbot-sound-enabled").
//
//  Tones are rendered once per sound into a WAV in memory and played with
//  AVAudioPlayer; the launcher file with AVPlayer. The audio session is put
//  in the `.ambient` category (only while the app has not chosen one of its
//  own), so the silent switch mutes the chat and the app's other audio keeps
//  playing. No haptics.
//

import Foundation
import Combine
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
public final class ChatSounds: ObservableObject {

    /// The visitor's switch (on unless they turned it off).
    @Published public private(set) var soundOn: Bool

    private let defaults: UserDefaults
    private let gate = MessageSound.Gate()
    private var customizations: () -> [String: Any]?
    private var seen: Set<String> = []
    private var started = false
    /// Played instead of the speaker (tests).
    var player: ((MessageSound.Cue) -> Void)?
    var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }

    #if canImport(AVFoundation)
    private var wavs: [String: Data] = [:]
    private var playing: [AVAudioPlayer] = []
    private var filePlayer: AVPlayer?
    #endif

    init(defaults: UserDefaults = .standard, customizations: @escaping () -> [String: Any]?) {
        self.defaults = defaults
        self.customizations = customizations
        self.soundOn = MessageSound.soundEnabledFrom(defaults.string(forKey: MessageSound.soundEnabledKey))
    }

    /// The chat menu offers Sound on / off only when the bot has a sound.
    public var hasSounds: Bool { MessageSound.hasAnySound(customizations()) }

    /// Sound on / off, kept on the device.
    public func toggle() {
        soundOn.toggle()
        defaults.set(soundOn ? "true" : "false", forKey: MessageSound.soundEnabledKey)
    }

    /// Plays `event` when the visitor has sound on, the bot has a sound for
    /// it and its gap has passed. True when it played.
    @discardableResult
    public func play(_ event: MessageSound.Event) -> Bool {
        guard soundOn else { return false }
        let c = customizations()
        guard let cue = MessageSound.cueFor(c, event), gate.allow(c, event, now: now()) else { return false }
        if let player = player { player(cue) } else { output(cue) }
        return true
    }

    /// The conversation's rows changed: a message arrived (a bot step, a
    /// person's or the AI's message) plays the message sound. The first
    /// rows seen and a bulk restore play nothing.
    public func messagesChanged(_ rows: [any RecordItem], restoring: Bool = false) {
        let arrived = started && !restoring && MessageSound.messageArrived(seen, rows)
        seen = MessageSound.rowIds(rows)
        started = true
        if arrived { play(.message) }
    }

    /// The chat opened or closed (the launcher sound, or the pack's open / close).
    public func chatOpened(_ open: Bool) { play(open ? .open : .close) }

    /// The visitor sent from the composer (a pack's send sound).
    public func sent() { play(.send) }

    // MARK: - Output

    private func output(_ cue: MessageSound.Cue) {
        #if canImport(AVFoundation)
        Self.ambientSession()
        switch cue {
        case .tone(let key, let steps):
            let wav = wavs[key] ?? MessageSound.renderWav(steps)
            wavs[key] = wav
            guard let p = try? AVAudioPlayer(data: wav) else { return }
            playing.removeAll { !$0.isPlaying }
            playing.append(p)
            p.play()
        case .url(let raw):
            guard let url = URL(string: raw) else { return }
            let p = AVPlayer(url: url)
            filePlayer = p
            p.play()
        }
        #endif
    }

    #if canImport(AVFoundation)
    /// `.ambient`: the silent switch mutes it and other audio keeps playing.
    /// Left alone when the app chose its own category.
    private static func ambientSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        #endif
    }
    #endif
}
