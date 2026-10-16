//
//  MessageSoundTests.swift
//  Conferbot
//
//  The chat's sounds (RN __tests__/core/messageSound.test.ts; web
//  ts/chat/messageSound.ts, index.ts _playToggleSound), and ChatSounds: the
//  visitor's switch, the gaps and what counts as a message arriving.
//

import XCTest
@testable import Conferbot

final class MessageSoundTests: XCTestCase {

    typealias S = MessageSound

    func testTheWebsThreeMessageSoundsOffByDefault() {
        XCTAssertEqual(S.soundRecipe("off"), [])
        XCTAssertEqual(S.soundRecipe(nil), [])
        XCTAssertEqual(S.soundRecipe("ding"), [])
        XCTAssertEqual(S.soundRecipe("pop"), [S.ToneStep(at: 0, from: 520, to: 880, dur: 0.09, type: .sine, gain: 0.18)])
        XCTAssertEqual(S.soundRecipe("chime").map { $0.from }, [880, 1318.5])
        XCTAssertEqual(S.soundRecipe("bubble").map { [$0.from, $0.to] }, [[380, 760], [520, 1040]])
        XCTAssertEqual(S.normalizeMessageSound("chime"), "chime")
        XCTAssertEqual(S.normalizeMessageSound("loud"), "off")
    }

    func testFivePacksWithAllFourMomentsQuietAndShort() {
        XCTAssertEqual(S.soundPacks, ["off", "soft", "playful", "retro", "bubbly", "premium"])
        XCTAssertEqual(S.normalizeSoundPack("nope"), "off")
        for pack in S.soundPacks where pack != "off" {
            for ev in S.Event.allCases {
                let steps = S.packRecipe(pack, ev)
                XCTAssertFalse(steps.isEmpty, "\(pack).\(ev)")
                steps.forEach { XCTAssertLessThanOrEqual($0.gain, 0.2) }
                XCTAssertLessThan(S.toneLength(steps), 0.5)
            }
        }
        XCTAssertEqual(S.packRecipe("retro", .send), [S.ToneStep(at: 0, from: 660, to: 660, dur: 0.04, type: .square, gain: 0.04)])
        XCTAssertEqual(S.packRecipe("playful", .open).map { $0.at }, [0, 0.065, 0.13])
        XCTAssertEqual(S.packRecipe("off", .open), [])
    }

    func testPlaysTheLauncherFileForOpenAndCloseUnlessAPackPlaysThem() {
        let c: [String: Any] = ["enableWidgetToggleSound": true, "checkedSoundTab": "choose", "widgetToggleSound": "https://cdn.conferbot.com/sounds/sound-1.mp3"]
        func with(_ extra: [String: Any]) -> [String: Any] { c.merging(extra) { $1 } }
        XCTAssertEqual(S.toggleSoundUrl(c), "https://cdn.conferbot.com/sounds/sound-1.mp3")
        var noTab = c
        noTab["checkedSoundTab"] = nil
        XCTAssertEqual(S.toggleSoundUrl(noTab), "https://cdn.conferbot.com/sounds/sound-1.mp3")
        XCTAssertEqual(S.toggleSoundUrl(with(["checkedSoundTab": "upload", "customWidgetSoundUrl": "https://x.test/a.wav"])), "https://x.test/a.wav")
        XCTAssertEqual(S.toggleSoundUrl(with(["enableWidgetToggleSound": false])), "")
        XCTAssertEqual(S.toggleSoundUrl(with(["soundPack": "soft"])), "")
        XCTAssertEqual(S.toggleSoundUrl(with(["widgetToggleSound": "javascript:alert(1)"])), "")
        XCTAssertEqual(S.cueFor(c, .open), .url("https://cdn.conferbot.com/sounds/sound-1.mp3"))
        XCTAssertEqual(S.cueFor(c, .close), .url("https://cdn.conferbot.com/sounds/sound-1.mp3"))
        XCTAssertNil(S.cueFor(c, .send))
        XCTAssertNil(S.cueFor(c, .message))
    }

    private func key(_ cue: S.Cue?) -> String? {
        if case .tone(let k, _)? = cue { return k }
        return nil
    }

    func testPicksThePackOverTheSingleMessageSound() {
        XCTAssertEqual(key(S.cueFor(["messageSound": "pop"], .message)), "message.pop")
        XCTAssertEqual(key(S.cueFor(["messageSound": "pop", "soundPack": "retro"], .message)), "retro.message")
        XCTAssertEqual(key(S.cueFor(["soundPack": "retro"], .send)), "retro.send")
        XCTAssertNil(S.cueFor([:], .message))
        XCTAssertFalse(S.hasAnySound([:]))
        XCTAssertTrue(S.hasAnySound(["messageSound": "chime"]))
        XCTAssertTrue(S.hasAnySound(["soundPack": "soft"]))
    }

    func testKeepsTheWebsGaps() {
        let gate = S.Gate()
        let c: [String: Any] = ["messageSound": "pop"]
        XCTAssertTrue(gate.allow(c, .message, now: 1000))
        XCTAssertFalse(gate.allow(c, .message, now: 1000 + S.minGapMs - 1))
        XCTAssertTrue(gate.allow(c, .message, now: 1000 + S.minGapMs))
        // The launcher file plays on every toggle.
        XCTAssertTrue(gate.allow(c, .open, now: 1000))
        XCTAssertTrue(gate.allow(c, .open, now: 1001))
        let p: [String: Any] = ["soundPack": "soft"]
        let g2 = S.Gate()
        XCTAssertTrue(g2.allow(p, .send, now: 0))
        XCTAssertFalse(g2.allow(p, .send, now: S.packGapMs[.send]! - 1))
        XCTAssertTrue(g2.allow(p, .open, now: 10))
        XCTAssertTrue(g2.allow(p, .send, now: S.packGapMs[.send]!))
    }

    func testReadsTheVisitorsSwitchOnlyFalseIsOff() {
        XCTAssertFalse(S.soundEnabledFrom("false"))
        XCTAssertTrue(S.soundEnabledFrom("true"))
        XCTAssertTrue(S.soundEnabledFrom(nil))
    }

    func testRendersAToneAsWebAudioDoes() {
        let pop = S.soundRecipe("pop")[0]
        XCTAssertEqual(S.stepFrequency(pop, 0), 520, accuracy: 1e-6)
        XCTAssertEqual(S.stepFrequency(pop, pop.dur), 880, accuracy: 1e-6)
        XCTAssertEqual(S.stepFrequency(pop, pop.dur / 2), (520.0 * 880).squareRoot(), accuracy: 1e-6)
        XCTAssertEqual(S.stepGain(pop, 0), 0.0001, accuracy: 1e-7)
        XCTAssertEqual(S.stepGain(pop, 0.012), 0.18, accuracy: 1e-6)
        XCTAssertEqual(S.stepGain(pop, pop.dur), 0.0001, accuracy: 1e-7)
        XCTAssertEqual(S.stepGain(pop, pop.dur + 0.05), 0)
        let samples = S.renderSamples(S.soundRecipe("pop"), sampleRate: 8000)
        XCTAssertEqual(samples.count, Int((S.toneLength(S.soundRecipe("pop")) * 8000).rounded(.up)))
        let peak = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.1)
        XCTAssertLessThanOrEqual(Double(peak), 0.18 + 1e-6)
    }

    func testWritesAValid16BitMonoWavAbout20KB() {
        let wav = S.renderWav(S.packRecipe("premium", .open))
        func text(_ o: Int, _ n: Int) -> String { String(bytes: wav[o..<o + n], encoding: .ascii) ?? "" }
        func u16(_ o: Int) -> Int { Int(wav[o]) | Int(wav[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        XCTAssertEqual(text(0, 4), "RIFF")
        XCTAssertEqual(text(8, 4), "WAVE")
        XCTAssertEqual(u16(22), 1)
        XCTAssertEqual(u32(24), 22050)
        XCTAssertEqual(u16(34), 16)
        XCTAssertEqual(u32(40), wav.count - 44)
        XCTAssertLessThan(wav.count, 25_000)
        #if canImport(AVFoundation)
        // A player takes it from memory.
        XCTAssertNotNil(try? AVAudioPlayerShim.make(wav))
        #endif
    }

    func testHearsAMessageArrivingNotTheVisitorsOwnNorARestoredConversation() {
        let bot = BotMessageRecord(id: "a", time: Date(), text: "Hi")
        let frozen = BotMessageRecord(id: "f", time: Date(), nodeData: ["choices": AnyCodable(["A", "B"])])
        XCTAssertTrue(S.isArrivingMessage(bot))
        XCTAssertFalse(S.isArrivingMessage(frozen))
        XCTAssertTrue(S.isArrivingMessage(AgentMessageRecord(id: "g", time: Date(), text: "Hello", agentDetails: AgentDetails(id: "x", name: "Ana", email: "a@b.co"))))
        XCTAssertFalse(S.isArrivingMessage(UserMessageRecord(id: "u", time: Date(), text: "me")))
        let before: [any RecordItem] = [bot]
        XCTAssertTrue(S.messageArrived(S.rowIds(before), before + [BotMessageRecord(id: "b", time: Date(), text: "Next")]))
        XCTAssertFalse(S.messageArrived(S.rowIds(before), before + [UserMessageRecord(id: "u", time: Date(), text: "me")]))
        let restored: [any RecordItem] = (0...S.bulkRows).map { BotMessageRecord(id: "r\($0)", time: Date(), text: "x") }
        XCTAssertFalse(S.messageArrived([], restored))
        XCTAssertTrue(S.messageArrived([], [BotMessageRecord(id: "w", time: Date(), text: "Hi")]))
    }

    // MARK: - ChatSounds

    @MainActor
    func testChatSoundsTheSwitchKeptOnTheDeviceTheFirstRowsSilentAndAMessagePlays() {
        let defaults = UserDefaults(suiteName: "cb-sound-tests")!
        defaults.removePersistentDomain(forName: "cb-sound-tests")
        var c: [String: Any] = ["messageSound": "pop"]
        let sounds = ChatSounds(defaults: defaults, customizations: { c })
        var played: [String] = []
        sounds.player = { cue in
            if case .tone(let k, _) = cue { played.append(k) } else if case .url(let u) = cue { played.append(u) }
        }
        var now = 0.0
        sounds.now = { now }
        XCTAssertTrue(sounds.soundOn)
        XCTAssertTrue(sounds.hasSounds)
        // What was on screen first (a restored chat) plays nothing.
        sounds.messagesChanged([BotMessageRecord(id: "a", time: Date(), text: "Hi")])
        XCTAssertEqual(played, [])
        sounds.messagesChanged([BotMessageRecord(id: "a", time: Date(), text: "Hi"), BotMessageRecord(id: "b", time: Date(), text: "More")])
        XCTAssertEqual(played, ["message.pop"])
        // Sound off: kept under the web's key, nothing plays.
        sounds.toggle()
        XCTAssertEqual(defaults.string(forKey: S.soundEnabledKey), "false")
        now = 5000
        XCTAssertFalse(sounds.play(.message))
        XCTAssertFalse(ChatSounds(defaults: defaults, customizations: { c }).soundOn)
        sounds.toggle()
        // A pack's send and open; no send sound without one.
        XCTAssertFalse(sounds.play(.send))
        c = ["soundPack": "retro"]
        XCTAssertTrue(sounds.play(.send))
        sounds.chatOpened(true)
        XCTAssertEqual(played, ["message.pop", "retro.send", "retro.open"])
        defaults.removePersistentDomain(forName: "cb-sound-tests")
    }
}

#if canImport(AVFoundation)
import AVFoundation
enum AVAudioPlayerShim {
    static func make(_ data: Data) throws -> AVAudioPlayer { try AVAudioPlayer(data: data) }
}
#endif
