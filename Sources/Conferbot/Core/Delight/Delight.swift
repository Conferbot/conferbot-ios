//
//  Delight.swift
//  Conferbot
//
//  The conversation's small human touches, as the web widget judges them.
//  Ported from the React Native SDK (src/core/delight.ts), itself from
//  conferbot-widget src/ts/chat/delight/rules.ts (which answers can be
//  changed and when going back is safe, the bot's tapback, the moments that
//  earn a celebration, the gentle nudge), delight/index.ts (the timings, the
//  owner's on/off settings), delight/stallNudge.ts (when the nudge shows),
//  delight/celebrate.ts (the confetti's fan) and ratingFx.ts (the rating's
//  sparks).
//
//  Restraint is the point: a reaction on every answer, or confetti for an
//  email address, would feel like a toy. These fire on the moments a person
//  would react to, and each can be switched off by the owner:
//  customizations.botReactions, celebrations, stallNudges, allowChangeAnswer
//  (all on unless false). Motion is skipped with Reduce Motion. No haptics.
//  Pure.
//

import Foundation

public enum Delight {

    // MARK: - The owner's switches

    public enum Touch: String { case botReactions, celebrations, stallNudges, allowChangeAnswer }

    /// On unless the owner set it to false (web delight/index.ts `on`).
    public static func touchOn(_ c: [String: Any]?, _ key: Touch) -> Bool {
        (c?[key.rawValue] as? Bool) != false
    }

    /// The reaction and the burst wait this long after the answer (web REACT_AFTER_MS).
    public static let reactAfterMs: Double = 550
    /// "Edit" shows once the bot has been quiet this long (web QUIET_BEFORE_CHANGE_MS).
    public static let quietBeforeChangeMs: Double = 900
    /// Only the recent past can be changed (web keeps 30 question points).
    public static let maxQuestionPoints = 30

    // MARK: - Changing an answer

    /// Questions whose answer can be taken back and given again.
    public static let changeableTypes: Set<String> = [
        // v2 questions
        "ask-name-node", "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node",
        "ask-location-node", "ask-custom-question-node",
        // choices
        "n-choices-node", "n-select-option-node", "n-check-options-node", "yes-or-no-choice-node", "image-choice-node",
        "rating-choice-node", "opinion-scale-choice-node", "dynamic-choices-node",
        // rich inputs with no side effect
        "slider-node", "datetime-node", "ranking-node", "matrix-node", "address-node",
        // classic
        "two-choices-node", "three-choices-node", "select-option-node", "user-rating-node", "user-range-node", "user-input-node",
    ]

    /// Steps that show something but act on the world (a booking made, a code
    /// sent, a payment, a file uploaded, a signature given, an AI call): once
    /// one has run, going back would not undo it, so the answer before it stays.
    static let actsOnTheWorld: Set<String> = [
        "calendar-node", "payment-node", "otp-node", "ask-file-node", "signature-node", "ai-extract-node",
        "ai-route-node", "kb-answer-node", "quiz-node", "consent-node", "ask-multiple-questions-node",
    ]

    /// The web's display steps (nodeTypeCategories.ts DISPLAY_NODE_TYPES).
    static let displayTypes: Set<String> = [
        "two-choices-node", "three-choices-node", "select-option-node", "user-rating-node", "quiz-node", "user-input-node",
        "user-range-node", "message-node", "image-node", "video-node", "audio-node", "file-node", "ask-name-node",
        "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node", "ask-file-node", "ask-location-node",
        "ask-custom-question-node", "ask-multiple-questions-node", "calendar-node", "n-select-option-node",
        "n-check-options-node", "n-choices-node", "image-choice-node", "carousel-node", "rating-choice-node",
        "yes-or-no-choice-node", "opinion-scale-choice-node", "user-redirect-node", "html-node", "navigate-node",
        "dynamic-choices-node", "consent-node", "product-card-node", "slider-node", "datetime-node", "ranking-node",
        "otp-node", "address-node", "matrix-node", "ai-extract-node", "ai-route-node", "kb-answer-node", "signature-node",
        "payment-node",
    ]

    /// The web's logic steps (LOGIC_NODE_TYPES).
    static let logicTypes: Set<String> = [
        "condition-node", "boolean-logic-node", "random-flow-node", "math-operation-node", "variable-node", "jump-to-node",
        "business-hours-node",
    ]

    /// A step after the answer that going back can safely undo.
    public static func isSafeToUndo(_ type: String) -> Bool {
        (displayTypes.contains(type) && !actsOnTheWorld.contains(type)) || logicTypes.contains(type) || type == "delay-node"
    }

    /// Can the visitor change their answer to `questionType`, given the step
    /// types that have run since it was asked (the question itself excluded)?
    /// A person in the conversation since then counts as "agent" (not safe).
    public static func canChangeAnswer(_ questionType: String, _ typesSince: [String]) -> Bool {
        changeableTypes.contains(questionType) && typesSince.allSatisfy(isSafeToUndo)
    }

    /// Steps that wait for the visitor's answer: the ones a question point is
    /// kept for (what an answer belongs to, and what to go back to).
    public static func waitsForAnswer(_ questionType: String) -> Bool {
        changeableTypes.contains(questionType) || actsOnTheWorld.contains(questionType)
    }

    /// Whether "Edit" shows under the visitor's latest answer: the owner
    /// allows it, nothing locks the conversation (a person in it, or over),
    /// the bot is not mid-reply, the answer is the visitor's latest bubble,
    /// and nothing irreversible ran since (web delight/index.ts refreshChange).
    public static func showChangeFor(customizations: [String: Any]?, locked: Bool, botBusy: Bool, isLatestAnswer: Bool,
                                     questionType: String, typesSince: [String]) -> Bool {
        touchOn(customizations, .allowChangeAnswer) && !locked && !botBusy && isLatestAnswer
            && canChangeAnswer(questionType, typesSince)
    }

    // MARK: - Reading an answer

    /// A rating or scale answer as a share of the best (0 to 1), from the
    /// reply text: "★★★★ Good" (stars out of 5), "8/10", "7 / 10". nil when the
    /// text is not a score. This SDK's star answers are "⭐⭐⭐⭐": counted the same.
    public static func scoreShare(_ text: String) -> Double? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = s.range(of: #"^(\d+(?:\.\d+)?)\s*/\s*(\d+)\b"#, options: .regularExpression) {
            let parts = s[m].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let v = Double(parts[0]), let max = Double(parts[1]) {
                return max > 0 ? Swift.max(0, Swift.min(1, v / max)) : nil
            }
        }
        let stars = s.unicodeScalars.filter { $0 == "\u{2605}" || $0 == "\u{2B50}" }.count
        if stars > 0 { return min(1, Double(stars) / 5) }
        return nil
    }

    static let scoreTypes: Set<String> = ["rating-choice-node", "opinion-scale-choice-node", "user-rating-node"]

    /// The answer's text as the web would read it for a score: a rating of n
    /// out of `max` stars as "n/max", a scale value as "v/to" (its top).
    public static func scoreText(_ questionType: String, _ value: Double, _ max: Double) -> String {
        guard scoreTypes.contains(questionType), value.isFinite, max > 0 else { return "" }
        return "\(fmt(value))/\(fmt(max))"
    }

    private static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    // MARK: - The bot's reaction

    /// The tapback the bot puts on the visitor's answer, or nil for none.
    /// Names get a wave, scores a heart or a thumbs up (a low score gets a
    /// quiet "thank you for telling us", never a cheer), a booking a party.
    /// Everything else goes unremarked - a reaction on every answer is noise.
    public static func reactionFor(_ questionType: String, _ answerText: String) -> String? {
        if questionType == "ask-name-node" { return "👋" }
        if questionType == "calendar-node" || questionType == "payment-node" { return "🎉" }
        if scoreTypes.contains(questionType) {
            guard let s = scoreShare(answerText) else { return nil }
            if s >= 0.8 { return "❤️" }
            if s >= 0.55 { return "👍" }
            return "🙏"
        }
        return nil
    }

    static let reactionLabels: [String: String] = [
        "👋": "reaction.waved",
        "🎉": "reaction.celebrated",
        "❤️": "reaction.loved",
        "👍": "reaction.liked",
        "🙏": "reaction.thanked",
    ]

    /// What VoiceOver says for the badge (web reactions.ts LABELS).
    public static func reactionLabel(_ emoji: String) -> String { I18n.t(reactionLabels[emoji] ?? "reaction.reacted") }

    // MARK: - Celebrations

    /// The moments that earn a burst: a booking made, a payment through, a top score.
    public static func celebrates(_ questionType: String, _ answerText: String) -> Bool {
        if questionType == "calendar-node" || questionType == "payment-node" { return true }
        if scoreTypes.contains(questionType) {
            // The rating card already sparks on a pick; a perfect score adds the burst.
            guard let s = scoreShare(answerText) else { return false }
            return s >= 0.999 && questionType != "rating-choice-node"
        }
        return false
    }

    /// What an answer gets, a beat after it lands: a tapback and / or a burst (web delight/index.ts onAnswer).
    public static func touchesFor(_ c: [String: Any]?, _ questionType: String, _ answerText: String,
                                  reducedMotion: Bool) -> (reaction: String?, celebrate: Bool) {
        (touchOn(c, .botReactions) ? reactionFor(questionType, answerText) : nil,
         !reducedMotion && touchOn(c, .celebrations) && celebrates(questionType, answerText))
    }

    /// Pieces in a burst (web celebrate.ts PIECES).
    public static let confettiPieceCount = 28
    /// The burst is gone after this (web: the pieces removed at 1600 ms).
    public static let confettiMs: Double = 1600

    public struct ConfettiPiece: Equatable {
        /// Where the piece flies to from the answer, pt.
        public let dx: Double
        public let dy: Double
        /// How far it then falls, pt.
        public let fall: Double
        /// Its spin, degrees.
        public let rot: Double
        /// Its start delay, ms.
        public let delay: Double
        /// Which of the 4 colours (the bot's own).
        public let tone: Int
        public let round: Bool
    }

    /// The burst's pieces: a fan that opens up and towards the bot's side,
    /// -160 to -20 degrees with a little jitter, 56-116 pt out, then a 26-56
    /// pt fall (web celebrate.ts). `random` is the system's unless a test gives one.
    public static func confettiPieces(_ random: () -> Double = { Double.random(in: 0..<1) }) -> [ConfettiPiece] {
        (0..<confettiPieceCount).map { i in
            let angle = (-160 + 140 * Double(i) / Double(confettiPieceCount - 1) + (random() * 14 - 7)) * (Double.pi / 180)
            let reach = 56 + random() * 60
            return ConfettiPiece(
                dx: jsRound(cos(angle) * reach),
                dy: jsRound(sin(angle) * reach),
                fall: jsRound(26 + random() * 30),
                rot: jsRound(random() * 540 - 270),
                delay: jsRound(random() * 90),
                tone: i % 4,
                round: i % 3 == 0
            )
        }
    }

    /// Math.round: halves go up.
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    /// The rating's sparks on a pick: 8, or 12 for the top score, evenly round from 20 degrees (web ratingFx.ts burst).
    public static func ratingSparks(top: Bool) -> [Double] {
        let count = top ? 12 : 8
        return (0..<count).map { 360 / Double(count) * Double($0) + 20 }
    }
    /// The sparks are gone after this (web: removed at 1000 ms).
    public static let ratingSparksMs: Double = 1000

    // MARK: - A gentle nudge when a question waits

    /// How long a question waits, with the chat open and nobody busy, before the nudge.
    public static let stallAfterMs: Double = 40_000
    /// Recent activity (typing, a touch, a scroll) in the chat postpones it this long.
    public static let stallQuietMs: Double = 15_000

    static let typed: Set<String> = [
        "ask-name-node", "ask-email-node", "ask-phone-number-node", "ask-number-node", "ask-url-node",
        "ask-location-node", "ask-custom-question-node", "user-input-node", "user-range-node",
    ]

    /// What the nudge says: picking or typing, never pushy.
    public static func stallHintFor(_ questionType: String) -> String {
        typed.contains(questionType) ? I18n.t("nudge.stallType") : I18n.t("nudge.stallPick")
    }

    /// Whether a question shows a nudge at all (not for steps that already wait on their own).
    public static func nudgesWhileWaiting(_ questionType: String) -> Bool {
        changeableTypes.contains(questionType) || questionType == "calendar-node" || questionType == "consent-node"
    }

    /// The nudge's timing (web delight/stallNudge.ts): stallAfterMs after the
    /// question, unless the visitor was busy in the last stallQuietMs, the chat
    /// is not on screen, or something is typed; then it checks again every
    /// stallQuietMs. Once per question. The timers are injected (ms).
    public final class StallWatch {
        public typealias SetTimer = (_ ms: Double, _ fn: @escaping () -> Void) -> AnyObject
        public typealias ClearTimer = (AnyObject) -> Void

        private let isVisible: () -> Bool
        private let composerValue: () -> String
        private let show: (String) -> Void
        private let hide: () -> Void
        private let now: () -> Double
        private let setTimer: SetTimer
        private let clearTimer: ClearTimer
        private var timer: AnyObject?
        private var armedType = ""
        private var armed = false
        private var shown = false
        private var lastActivity: Double

        public init(isVisible: @escaping () -> Bool, composerValue: @escaping () -> String,
                    show: @escaping (String) -> Void, hide: @escaping () -> Void,
                    now: @escaping () -> Double, setTimer: @escaping SetTimer, clearTimer: @escaping ClearTimer) {
            self.isVisible = isVisible
            self.composerValue = composerValue
            self.show = show
            self.hide = hide
            self.now = now
            self.setTimer = setTimer
            self.clearTimer = clearTimer
            self.lastActivity = now()
        }

        private func clear() {
            if let t = timer { clearTimer(t) }
            timer = nil
        }

        private func check() {
            timer = nil
            if shown || !armed { return }
            let busy = now() - lastActivity < Delight.stallQuietMs
            if busy || !isVisible() || !composerValue().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                timer = setTimer(Delight.stallQuietMs) { [weak self] in self?.check() }
                return
            }
            shown = true
            show(Delight.stallHintFor(armedType))
        }

        /// Start (or restart) the wait for the question now on screen.
        public func arm(_ questionType: String) {
            armedType = questionType
            armed = true
            if shown { return }
            clear()
            timer = setTimer(Delight.stallAfterMs) { [weak self] in self?.check() }
        }

        /// They answered, or the question went away: the nudge goes.
        public func disarm() {
            clear()
            let was = shown
            armed = false
            shown = false
            if was { hide() }
        }

        /// The visitor touched, scrolled or typed in the chat.
        public func touch() { lastActivity = now() }
    }

    // MARK: - Where "Edit" cuts the conversation

    /// The question's own rows just above the answer (its bubble, its frozen
    /// choices), else the answer itself: the index the conversation is cut at.
    public static func cutIndex(_ rowNodeIds: [String?], answerIndex: Int, nodeId: String) -> Int {
        var cut = answerIndex
        var i = answerIndex - 1
        while i >= 0, rowNodeIds[i] == nodeId {
            cut = i
            i -= 1
        }
        return cut
    }
}
