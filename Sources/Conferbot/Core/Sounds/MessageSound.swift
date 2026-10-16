//
//  MessageSound.swift
//  Conferbot
//
//  The chat's sounds, as the web widget plays them. Ported from the React
//  Native SDK (src/core/messageSound.ts), itself from conferbot-widget
//  src/ts/chat/messageSound.ts (soundRecipe, packRecipe, playMessageFor,
//  playPackSound, MIN_GAP_MS, PACK_GAP_MS), the launcher sound in
//  src/index.ts (_playToggleSound and the soundUrl it picks) and
//  src/ts/layout/ownerLayout.ts (normalizeMessageSound).
//
//    messageSound    "off" (default) | "pop" | "chime" | "bubble": a message
//                    arrived (the bot's step drawn, an agent's message)
//    soundPack       "off" (default) | "soft" | "playful" | "retro" |
//                    "bubbly" | "premium": open, message, send and close as
//                    a set; a pack replaces the single message sound and the
//                    launcher sound, so nothing doubles up
//    launcher sound  enableWidgetToggleSound with checkedSoundTab "choose"
//                    (widgetToggleSound) or "upload" (customWidgetSoundUrl):
//                    an audio file played when the chat opens or closes
//
//  The visitor's "Sound off" in the chat menu silences all of them (kept on
//  the device under the web's key "conferbot-sound-enabled").
//
//  The web synthesises each tone with Web Audio (an oscillator per step, its
//  frequency and gain on exponential ramps), so there are no files. An app
//  has no Web Audio: `renderWav` computes the same steps into a small 16-bit
//  mono WAV (about 20 KB for the longest sound) that AVAudioPlayer loads
//  from memory. Pure: no audio, storage or clock of its own (ChatSounds.swift
//  plays them).
//

import Foundation

public enum MessageSound {

    public enum Wave: String { case sine, triangle, square }

    /// The moments a sound plays for.
    public enum Event: String, CaseIterable { case open, message, send, close }

    public static let messageSounds = ["off", "pop", "chime", "bubble"]
    public static let soundPacks = ["off", "soft", "playful", "retro", "bubbly", "premium"]

    /// The visitor's switch, under the web's own key.
    public static let soundEnabledKey = "conferbot-sound-enabled"

    /// One oscillator: when it starts, its glide, length, wave and peak gain.
    public struct ToneStep: Equatable {
        /// Start, seconds after the sound begins.
        public let at: Double
        /// Frequency at the start and end of the step (Hz).
        public let from: Double
        public let to: Double
        /// Length of the step (seconds).
        public let dur: Double
        public let type: Wave
        /// Peak gain, 0-1.
        public let gain: Double

        public init(at: Double, from: Double, to: Double, dur: Double, type: Wave, gain: Double) {
            self.at = at; self.from = from; self.to = to; self.dur = dur; self.type = type; self.gain = gain
        }
    }

    public static func normalizeMessageSound(_ v: Any?) -> String {
        guard let s = v as? String, messageSounds.contains(s) else { return "off" }
        return s
    }

    public static func normalizeSoundPack(_ v: Any?) -> String {
        guard let s = v as? String, soundPacks.contains(s) else { return "off" }
        return s
    }

    /// True when a pack (not "off") is chosen.
    public static func soundPackOn(_ c: [String: Any]?) -> Bool { normalizeSoundPack(c?["soundPack"]) != "off" }

    /// The notes of each message sound.
    public static func soundRecipe(_ kind: Any?) -> [ToneStep] {
        switch normalizeMessageSound(kind) {
        case "pop":
            return [ToneStep(at: 0, from: 520, to: 880, dur: 0.09, type: .sine, gain: 0.18)]
        case "chime":
            return [
                ToneStep(at: 0, from: 880, to: 880, dur: 0.18, type: .triangle, gain: 0.12),
                ToneStep(at: 0.09, from: 1318.5, to: 1318.5, dur: 0.22, type: .triangle, gain: 0.1),
            ]
        case "bubble":
            return [
                ToneStep(at: 0, from: 380, to: 760, dur: 0.07, type: .sine, gain: 0.16),
                ToneStep(at: 0.08, from: 520, to: 1040, dur: 0.07, type: .sine, gain: 0.12),
            ]
        default:
            return []
        }
    }

    private static func note(_ at: Double, _ from: Double, _ dur: Double, _ type: Wave, _ gain: Double, _ to: Double? = nil) -> ToneStep {
        ToneStep(at: at, from: from, to: to ?? from, dur: dur, type: type, gain: gain)
    }

    private static func run(_ freqs: [Double], _ step: Double, _ dur: Double, _ type: Wave, _ gain: Double) -> [ToneStep] {
        freqs.enumerated().map { note(Double($0.offset) * step, $0.element, dur, type, gain) }
    }

    // C5 E5 G5 C6, and the rest of the notes the packs use.
    private static let C5 = 523.25, E5 = 659.25, G5 = 783.99, C6 = 1046.5, E6 = 1318.5, G6 = 1568.0, B5 = 987.77, A4 = 440.0, E4 = 329.63

    private static let packs: [String: [Event: [ToneStep]]] = [
        // Soft: low, rounded sines - barely there.
        "soft": [
            .open: [note(0, A4, 0.16, .sine, 0.07, E5), note(0.08, E5, 0.16, .sine, 0.05)],
            .message: [note(0, E5, 0.16, .sine, 0.08), note(0.07, A4 * 2, 0.2, .sine, 0.05)],
            .send: [note(0, C5, 0.08, .sine, 0.05, G5)],
            .close: [note(0, E5, 0.16, .sine, 0.06, A4)],
        ],
        // Playful: a bright arpeggio and a boing.
        "playful": [
            .open: run([C5, E5, G5], 0.065, 0.09, .triangle, 0.1),
            .message: [note(0, 300, 0.14, .sine, 0.14, 900), note(0.13, 900, 0.06, .sine, 0.06)],
            .send: [note(0, 600, 0.06, .sine, 0.12, 1050)],
            .close: run([G5, E5, C5], 0.06, 0.08, .triangle, 0.08),
        ],
        // Retro: square-wave chiptune - a power-up and a coin.
        "retro": [
            .open: run([E4, A4, E5, A4 * 2], 0.045, 0.05, .square, 0.045),
            .message: [note(0, B5, 0.07, .square, 0.05), note(0.07, E6, 0.16, .square, 0.045)],
            .send: [note(0, 660, 0.04, .square, 0.04)],
            .close: run([A4 * 2, E5, A4], 0.05, 0.05, .square, 0.04),
        ],
        // Bubbly: rising bubbles.
        "bubbly": [
            .open: [note(0, 400, 0.06, .sine, 0.13, 800), note(0.07, 500, 0.06, .sine, 0.11, 1000), note(0.14, 650, 0.07, .sine, 0.09, 1300)],
            .message: [note(0, 380, 0.07, .sine, 0.16, 760), note(0.08, 520, 0.07, .sine, 0.12, 1040)],
            .send: [note(0, 700, 0.05, .sine, 0.1, 1400)],
            .close: [note(0, 800, 0.09, .sine, 0.1, 400)],
        ],
        // Premium: a soft bell - a fundamental and its octave, long and low.
        "premium": [
            .open: [note(0, C5, 0.42, .sine, 0.07), note(0, C6, 0.34, .sine, 0.03), note(0.1, G5, 0.36, .sine, 0.04)],
            .message: [note(0, C6, 0.32, .triangle, 0.07), note(0.09, G6, 0.28, .sine, 0.035)],
            .send: [note(0, A4 * 2, 0.1, .sine, 0.045)],
            .close: [note(0, G5, 0.26, .sine, 0.05, C5)],
        ],
    ]

    /// The notes of `pack` for `event`.
    public static func packRecipe(_ pack: Any?, _ event: Event) -> [ToneStep] {
        let p = normalizeSoundPack(pack)
        return p == "off" ? [] : packs[p]?[event] ?? []
    }

    /// At most one message sound this often (ms).
    public static let minGapMs: Double = 800
    /// A pack's own moments can follow each other quickly (open, then the greeting arriving); each has its own gap.
    public static let packGapMs: [Event: Double] = [.open: 400, .message: 800, .send: 250, .close: 400]

    /// The launcher sound's file, or "" (none, or a pack plays open and close instead).
    public static func toggleSoundUrl(_ c: [String: Any]?) -> String {
        guard let c = c, JS.truthy(c["enableWidgetToggleSound"]), !soundPackOn(c) else { return "" }
        let tab = (c["checkedSoundTab"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "choose"
        let raw = tab == "choose" ? c["widgetToggleSound"] : tab == "upload" ? c["customWidgetSoundUrl"] : nil
        guard let url = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil else { return "" }
        return url
    }

    /// Whether the bot has any sound at all (the chat menu offers Sound on / off only then).
    public static func hasAnySound(_ c: [String: Any]?) -> Bool {
        soundPackOn(c) || normalizeMessageSound(c?["messageSound"]) != "off" || !toggleSoundUrl(c).isEmpty
    }

    /// The visitor's stored switch: only "false" turns sounds off (nothing stored reads as on).
    public static func soundEnabledFrom(_ stored: String?) -> Bool { stored != "false" }

    /// What to play for a moment: a tone (its cache key and notes) or a file.
    public enum Cue: Equatable {
        case tone(key: String, steps: [ToneStep])
        case url(String)
    }

    /// The cue for `event` under the owner's settings: the pack's sound when
    /// a pack is on; else the message sound for "message" and the launcher
    /// file for "open" / "close"; "send" has a sound only in a pack.
    public static func cueFor(_ c: [String: Any]?, _ event: Event) -> Cue? {
        if soundPackOn(c) {
            let pack = normalizeSoundPack(c?["soundPack"])
            let steps = packRecipe(pack, event)
            return steps.isEmpty ? nil : .tone(key: "\(pack).\(event.rawValue)", steps: steps)
        }
        switch event {
        case .message:
            let kind = normalizeMessageSound(c?["messageSound"])
            let steps = soundRecipe(kind)
            return steps.isEmpty ? nil : .tone(key: "message.\(kind)", steps: steps)
        case .open, .close:
            let url = toggleSoundUrl(c)
            return url.isEmpty ? nil : .url(url)
        case .send:
            return nil
        }
    }

    /// The gaps between sounds, per moment: a message sound at most every
    /// minGapMs (a pack's message too), each pack moment its own gap. The
    /// launcher file has no gap (the web plays it on every toggle).
    public final class Gate {
        private var last: [Event: Double] = [:]
        public init() {}

        /// True (and noted) when `event` may play at `now` (ms).
        public func allow(_ c: [String: Any]?, _ event: Event, now: Double) -> Bool {
            let pack = soundPackOn(c)
            if !pack && event != .message { return true }
            let gap = pack ? (packGapMs[event] ?? 0) : minGapMs
            if let l = last[event], now - l < gap { return false }
            last[event] = now
            return true
        }
    }

    // MARK: - The tone as a WAV file

    /// Web Audio starts the notes this long after the call (t0 = currentTime + 0.01).
    static let leadS = 0.01
    /// The gain's attack (exponentialRampToValueAtTime(gain, t + 0.012)).
    static let attackS = 0.012
    /// Each oscillator stops this long after its note (osc.stop(t + dur + 0.02)).
    static let tailS = 0.02
    static let floorGain = 0.0001

    static func wave(_ type: Wave, _ phase: Double) -> Double {
        let p = phase - phase.rounded(.down) // 0..1 of a cycle
        switch type {
        case .square: return p < 0.5 ? 1 : -1
        case .triangle: return p < 0.25 ? 4 * p : p < 0.75 ? 2 - 4 * p : 4 * p - 4
        case .sine: return sin(2 * Double.pi * p)
        }
    }

    /// A value on an exponential ramp from a to b, at fraction f (Web Audio's exponentialRampToValueAtTime).
    static func expRamp(_ a: Double, _ b: Double, _ f: Double) -> Double { a * pow(b / a, max(0, min(1, f))) }

    /// The gain of a step `t` seconds into it: 0.0001, up to `gain` in 12 ms, down to 0.0001 at `dur`.
    public static func stepGain(_ s: ToneStep, _ t: Double) -> Double {
        if t < 0 || t > s.dur + tailS { return 0 }
        if t <= attackS { return expRamp(floorGain, s.gain, t / attackS) }
        if t <= s.dur { return expRamp(s.gain, floorGain, (t - attackS) / max(1e-6, s.dur - attackS)) }
        return floorGain
    }

    /// The step's frequency `t` seconds into it: an exponential glide from `from` to `to` over `dur`.
    public static func stepFrequency(_ s: ToneStep, _ t: Double) -> Double { expRamp(s.from, s.to, t / s.dur) }

    /// Seconds the sound lasts, its lead-in and tails included.
    public static func toneLength(_ steps: [ToneStep]) -> Double {
        guard let end = steps.map({ $0.at + $0.dur + tailS }).max() else { return 0 }
        return leadS + end
    }

    /// The steps as samples in [-1, 1].
    public static func renderSamples(_ steps: [ToneStep], sampleRate: Int = 22050) -> [Float] {
        let rate = Double(sampleRate)
        let n = Int((toneLength(steps) * rate).rounded(.up))
        var out = [Double](repeating: 0, count: n)
        for s in steps {
            let start = Int(((leadS + s.at) * rate).rounded())
            let len = Int(((s.dur + tailS) * rate).rounded(.up))
            var phase = 0.0
            var i = 0
            while i < len && start + i < n {
                let t = Double(i) / rate
                out[start + i] += wave(s.type, phase) * stepGain(s, t)
                phase += stepFrequency(s, min(t, s.dur)) / rate
                i += 1
            }
        }
        return out.map { Float(max(-1, min(1, $0))) }
    }

    /// The steps as a 16-bit mono PCM WAV file.
    public static func renderWav(_ steps: [ToneStep], sampleRate: Int = 22050) -> Data {
        let samples = renderSamples(steps, sampleRate: sampleRate)
        let dataLen = samples.count * 2
        var d = Data(capacity: 44 + dataLen)
        func str(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + dataLen)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1) // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)) // byte rate
        u16(2); u16(16) // block align, bits per sample
        str("data"); u32(UInt32(dataLen))
        for s in samples {
            let v = Int16(max(-32768, min(32767, (Double(s) * 32767).rounded())))
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }

    // MARK: - Which new conversation rows are a message arriving

    /// A row that is a message arriving: a bot step's bubble (the web plays as
    /// each step is drawn) or a person's / the AI agent's message. Not the
    /// visitor's own, not join / leave lines, not the frozen copy of choice
    /// buttons.
    public static func isArrivingMessage(_ item: any RecordItem) -> Bool {
        switch item.type {
        case .botMessage:
            return (item as? BotMessageRecord)?.nodeData?["choices"] == nil
        case .agentMessage, .agentMessageRich, .agentMessageFile, .agentMessageAudio:
            return true
        default:
            return false
        }
    }

    /// More new rows than this at once is a conversation put on screen whole (restored, the server's history), not news.
    public static let bulkRows = 3

    /// Whether the rows added since `prevIds` include an arriving message (and are not a bulk restore).
    public static func messageArrived(_ prevIds: Set<String>, _ next: [any RecordItem]) -> Bool {
        let added = next.filter { !prevIds.contains($0.id) }
        return !added.isEmpty && added.count <= bulkRows && added.contains(where: isArrivingMessage)
    }

    /// The ids of a conversation's rows, for the next messageArrived.
    public static func rowIds(_ rows: [any RecordItem]) -> Set<String> { Set(rows.map { $0.id }) }
}
