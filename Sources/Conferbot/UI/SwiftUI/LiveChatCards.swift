//
//  LiveChatCards.swift
//  Conferbot
//
//  The small cards and lines of a live chat, as on the web widget: the
//  owner's quick actions and "Talk to a person" above the composer, the AI's
//  follow-up email card, the queue position, the "nobody could join" email
//  ask, leave a message, a locked conversation, an agent's dropped
//  connection, an agent asking for a file, the post-chat rating, "Email me
//  this chat" and the closed chat (blocked, or ended with a new chat). State
//  is on ConferBot.liveChat (Core/LiveChat).
//

import SwiftUI

@available(iOS 15.0, *)
private struct LiveCard<Content: View>: View {
    var indent: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(UIColor.separator), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.leading, indent ? 40 : 0)
    }
}

@available(iOS 15.0, *)
private struct CardTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary) }
}

@available(iOS 15.0, *)
private struct CardSub: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13)).foregroundColor(.secondary) }
}

@available(iOS 15.0, *)
private struct PrimaryButton: View {
    let label: String
    var accent: Color
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 64)
            .background(enabled ? accent : accent.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled || busy)
    }
}

/// An email field (and an optional message) with one button. [onSubmit] reports ok.
@available(iOS 15.0, *)
private struct EmailForm: View {
    let button: String
    var messagePlaceholder: String? = nil
    var accent: Color
    let onSubmit: (_ email: String, _ message: String, _ done: @escaping (Bool) -> Void) -> Void

    @State private var email = ""
    @State private var message = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let placeholder = messagePlaceholder {
                TextField(placeholder, text: $message)
                    .padding(10)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(Color(UIColor.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 0.5))
            }
            HStack(spacing: 8) {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(10)
                    .background(Color(UIColor.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 0.5))
                PrimaryButton(label: button, accent: accent, busy: busy) {
                    if !LiveChat.isEmail(email) {
                        error = I18n.t("sdk.form.invalidEmail")
                    } else if messagePlaceholder != nil && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        error = I18n.t("leave.writeMessage")
                    } else {
                        error = nil
                        busy = true
                        onSubmit(email.trimmingCharacters(in: .whitespacesAndNewlines), message.trimmingCharacters(in: .whitespacesAndNewlines)) { ok in
                            busy = false
                            if !ok { error = I18n.t("sdk.form.notThrough") }
                        }
                    }
                }
            }
            if let error = error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .padding(.top, 6)
    }
}

/// The owner's quick actions (and "Talk to a person") above the composer,
/// as on the web (quickActions.ts): from the first AI answer on. "Talk to a
/// person" only on an AI agent bot, and only while no handover is under way
/// and nobody is here (HandoverState.talkToPersonAllowed); it goes on tap and
/// never comes back on the strip, and the owner's links stay.
@available(iOS 15.0, *)
public struct QuickActionsStrip: View {
    @ObservedObject var conferBot: ConferBot
    var accent: Color
    @Environment(\.openURL) private var openURL
    /// Retired once tapped, or once a handover took it off: an AI reply
    /// arriving mid-handover cannot bring it back.
    @State private var humanRetired = false

    public init(conferBot: ConferBot = .shared, accent: Color) {
        self.conferBot = conferBot
        self.accent = accent
    }

    /// Nobody is coming or here, on a bot whose owner offers a person.
    private var offerHuman: Bool {
        let personHere = conferBot.currentAgent.map { !$0.id.hasPrefix("ai-agent-") } ?? false
        return conferBot.agentBot != nil
            && (conferBot.serverCustomizations?["chatTalkToHuman"] as? Bool) == true
            && HandoverState.talkToPersonAllowed(conferBot.chatState.getServerRecord())
            && !personHere
    }

    public var body: some View {
        let aiAnswered = conferBot.messages.contains { ($0 as? AgentMessageRecord)?.agentDetails.isAIAgent == true }
        let actions = AgentBotParser.quickActions(conferBot.serverCustomizations)
        let human = offerHuman && !humanRetired
        Group {
            if aiAnswered && (!actions.isEmpty || human) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(actions, id: \.url) { a in
                            pill("\(a.label) \u{2197}") {
                                conferBot.trackGoal(goalId: "quick-action:\(a.label)", goalName: AgentBotParser.conversionEvent(label: a.label, url: a.url))
                                if let url = URL(string: a.url) { openURL(url) }
                            }
                        }
                        if human {
                            pill(I18n.t("chat.talkToPerson")) {
                                humanRetired = true
                                Task { try? await conferBot.sendMessage(LiveChat.talkToPersonAsk) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
        // A handover under way (or a person here) after the first answer
        // takes it off for good.
        .onChange(of: aiAnswered && !offerHuman) { off in
            if off { humanRetired = true }
        }
    }

    private func pill(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(accent)
                .clipShape(Capsule())
        }
    }
}

/// The handover step while it waits for a person: where they stand, about
/// how long, and Cancel to leave the queue.
@available(iOS 15.0, *)
public struct HandoverWaitCard: View {
    @ObservedObject var live: LiveChatExtras
    let message: String?
    var accent: Color
    /// Leave the queue (ConferBot.leaveQueue); no Cancel without it.
    var onCancel: (() -> Void)? = nil

    public var body: some View {
        LiveCard(indent: false) {
            HStack(spacing: 12) {
                ProgressView().tint(accent)
                VStack(alignment: .leading, spacing: 2) {
                    CardTitle(text: LiveChat.queueLine(live.queue))
                    // The estimate, else the usual wait, else a calm promise (web queueCard.ts).
                    let lines = LiveChat.waitCardLines(live.queue, typical: ReplyTime.typicalWait(
                        ConferBot.shared.serverCustomizations?["replyTime"] as? [String: Any], queueTypical: live.queue?.typical))
                    CardSub(text: lines.estimate)
                    if !lines.typical.isEmpty { CardSub(text: lines.typical) }
                }
                if let onCancel = onCancel {
                    Spacer(minLength: 8)
                    Button(I18n.t("common.cancel"), action: onCancel)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .accessibilityHint(I18n.t("sdk.queue.leaveHint"))
                }
            }
            if let message = message, !message.isEmpty {
                Text(message).font(.system(size: 13)).foregroundColor(.secondary).padding(.top, 6)
            }
        }
    }
}

/// The cards below the messages, in the web widget's order.
@available(iOS 15.0, *)
public struct LiveChatFooterCards: View {
    @ObservedObject var conferBot: ConferBot
    @ObservedObject var live: LiveChatExtras
    var accent: Color
    var onUpload: (() -> Void)?

    public init(conferBot: ConferBot = .shared, accent: Color, onUpload: (() -> Void)?) {
        self.conferBot = conferBot
        self.live = conferBot.liveChat
        self.accent = accent
        self.onUpload = onUpload
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let waiting = live.handoverWaiting {
                LiveCard {
                    Text(LiveChat.handoverWaitingLine(waiting)).font(.system(size: 14))
                    if waiting.email == nil && waiting.askEmail {
                        EmailForm(button: I18n.t("common.send"), accent: accent) { email, _, done in
                            live.shareEmailForReply(email, done: done)
                        }
                    }
                }
            }
            if (live.noAgentsAvailable || live.leftMessageTo != nil) && (conferBot.serverCustomizations?["chatLeaveMessage"] as? Bool) != false {
                LiveCard {
                    if let sentTo = live.leftMessageTo {
                        CardTitle(text: I18n.t("leave.sent", ["email": sentTo]))
                        CardSub(text: I18n.t("leave.sentSub"))
                    } else {
                        CardTitle(text: I18n.t("leave.title"))
                        CardSub(text: I18n.t("leave.sub"))
                        EmailForm(button: I18n.t("common.send"), messagePlaceholder: I18n.t("leave.messagePlaceholder"), accent: accent) { email, message, done in
                            live.leaveMessage(email: email, message: message) { ok in
                                done(ok)
                                if ok { conferBot.continueAfterLeaveMessage() }
                            }
                        }
                        Button(I18n.t("common.notNow")) { conferBot.continueAfterLeaveMessage() }
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            if let who = live.fileRequestedBy {
                LiveCard {
                    Text(I18n.t("file.requested", ["name": who])).font(.system(size: 14))
                    if let onUpload = onUpload {
                        PrimaryButton(label: I18n.t("sdk.file.choose"), accent: accent, action: onUpload).padding(.top, 6)
                    }
                }
            }
            if live.leadCardOpen || live.leadEmail != nil {
                LiveCard {
                    if let email = live.leadEmail {
                        Text(I18n.t("lead.done", ["email": email])).font(.system(size: 14))
                    } else {
                        CardTitle(text: I18n.t("lead.title"))
                        CardSub(text: I18n.t("lead.sub"))
                        EmailForm(button: I18n.t("common.send"), accent: accent) { email, _, done in
                            live.captureLeadEmail(email)
                            done(true)
                        }
                    }
                }
            }
            if let config = live.csatConfig, live.csatOpen {
                CsatCard(live: live, config: config, accent: accent)
            }
            if live.emailTranscriptOpen || live.emailTranscriptSentTo != nil {
                EmailTranscriptCard(live: live, known: knownEmail, accent: accent)
            }
            if let closed = conferBot.closedState {
                ClosedChatCard(closed: closed, accent: accent) { conferBot.startNewChat() }
            }
        }
    }

    /// The visitor's email when they gave one (user metadata, an email answer).
    private var knownEmail: String {
        let state = conferBot.chatState
        if let e = state.userMetadata["email"] as? String, EmailTranscript.isEmail(e) { return e }
        return state.userEmail.flatMap { EmailTranscript.isEmail($0) ? $0 : nil } ?? ""
    }
}

/// "Email me this chat" (web emailTranscript.ts, #39): one card, the
/// visitor's email filled in when known; Send, Cancel; the server's reason
/// when it did not go; "Sent! Check your inbox at ..." once it did.
@available(iOS 15.0, *)
private struct EmailTranscriptCard: View {
    @ObservedObject var live: LiveChatExtras
    var accent: Color
    @State private var email: String
    @State private var busy = false
    @State private var error: String?

    init(live: LiveChatExtras, known: String, accent: Color) {
        self.live = live
        self.accent = accent
        _email = State(initialValue: known)
    }

    var body: some View {
        LiveCard {
            if let sentTo = live.emailTranscriptSentTo {
                CardTitle(text: EmailTranscript.Copy.sent(sentTo))
            } else {
                CardTitle(text: EmailTranscript.Copy.title)
                CardSub(text: EmailTranscript.Copy.sub)
                HStack(spacing: 8) {
                    TextField(EmailTranscript.Copy.placeholder, text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityLabel(EmailTranscript.Copy.label)
                        .submitLabel(.send)
                        .onSubmit(submit)
                        .onChange(of: email) { _ in error = nil }
                        .padding(10)
                        .background(Color(UIColor.systemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 0.5))
                    PrimaryButton(label: busy ? EmailTranscript.Copy.sending : EmailTranscript.Copy.send, accent: accent, busy: busy, action: submit)
                }
                .padding(.top, 6)
                if let error = error {
                    Text(error).font(.caption).foregroundColor(.red).accessibilityAddTraits(.isStaticText)
                }
                Button(EmailTranscript.Copy.cancel) { live.closeEmailTranscript() }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func submit() {
        guard !busy else { return }
        guard EmailTranscript.isEmail(email) else { return error = EmailTranscript.Copy.checkEmail }
        error = nil
        busy = true
        live.emailTranscript(email) { r in
            busy = false
            if !r.ok { error = EmailTranscript.errorText(r) }
        }
    }
}

/// The closed chat (LiveEvents.closedState, #40): a blocked visitor's
/// neutral line, or, under an ended chat's own line, "Start a new chat".
@available(iOS 15.0, *)
private struct ClosedChatCard: View {
    let closed: LiveEvents.ClosedState
    var accent: Color
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // An ended chat's "Chat has ended" line is in the messages already.
            if closed.kind == .blocked {
                LiveSystemLine(closed.text)
            }
            if closed.newChat {
                PrimaryButton(label: LiveEvents.newChatText, accent: accent, action: onNewChat)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// The post-chat rating, from the bot's csatConfig.
@available(iOS 15.0, *)
private struct CsatCard: View {
    @ObservedObject var live: LiveChatExtras
    let config: CsatConfig
    var accent: Color

    @State private var stars = 0
    @State private var choice: Int?
    @State private var thumbs: Bool?
    @State private var feedback = ""

    private static let faces = ["\u{1F61E}", "\u{1F615}", "\u{1F610}", "\u{1F642}", "\u{1F604}"]

    private var picked: Any? {
        switch config.ratingType {
        case "thumbs": return thumbs
        case "stars": return stars > 0 ? stars : nil
        default: return choice
        }
    }

    var body: some View {
        LiveCard {
            if live.csatSent {
                CardTitle(text: config.thankYouText)
            } else {
                CardTitle(text: config.titleText)
                CardSub(text: config.subtitleText)
                options.padding(.top, 8)
                if picked != nil && config.showFeedbackInput {
                    TextField(config.feedbackPlaceholder, text: $feedback)
                        .padding(10)
                        .background(Color(UIColor.systemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator), lineWidth: 0.5))
                        .padding(.top, 8)
                }
                HStack(spacing: 8) {
                    PrimaryButton(label: I18n.t("common.send"), accent: accent, enabled: picked != nil) {
                        if let value = picked { live.submitRating(value, feedback: feedback) }
                    }
                    Button(I18n.t("common.notNow")) { live.dismissCsat() }
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch config.ratingType {
        case "thumbs":
            HStack(spacing: 8) {
                choicePill(I18n.t("sdk.csat.yes"), chosen: thumbs == true) { thumbs = true }
                choicePill(I18n.t("sdk.csat.no"), chosen: thumbs == false) { thumbs = false }
            }
        case "nps":
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0...10, id: \.self) { n in choicePill("\(n)", chosen: choice == n) { choice = n } }
                }
            }
        case "emoji":
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in choicePill(Self.faces[n - 1], chosen: choice == n) { choice = n } }
            }
        default:
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Button { stars = n } label: {
                        Image(systemName: n <= stars ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundColor(n <= stars ? Color(red: 0.96, green: 0.65, blue: 0.14) : Color(UIColor.separator))
                    }
                    .accessibilityLabel(I18n.t("rating.outOf", ["n": n, "max": 5]))
                }
            }
        }
    }

    private func choicePill(_ label: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(chosen ? .white : .primary)
                .frame(minWidth: 36)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(chosen ? accent : Color.clear)
                .overlay(Capsule().stroke(chosen ? accent : Color(UIColor.separator), lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

/// A centred system line (locked, connection dropped).
@available(iOS 15.0, *)
public struct LiveSystemLine: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

/// Everything live chat in one strip, for the UIKit chat (ChatViewController)
/// to host above its composer: the handover wait card, "Sent / Seen", the
/// cards, locked / connection lines and the owner's quick actions.
@available(iOS 15.0, *)
public struct LiveChatStrip: View {
    @ObservedObject private var conferBot = ConferBot.shared
    @ObservedObject private var live = ConferBot.shared.liveChat
    var onUpload: (() -> Void)?

    public init(onUpload: (() -> Void)?) {
        self.onUpload = onUpload
    }

    private var accent: Color {
        conferBot.customization?.primaryColor.map { Color($0) } ?? .blue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .humanHandover(let message) = conferBot.currentUIState {
                HandoverWaitCard(live: live, message: message, accent: accent, onCancel: { conferBot.leaveQueue() })
            }
            if let receipt = live.visitorReceipt(personHere: conferBot.currentAgent.map { !$0.id.hasPrefix("ai-agent-") } ?? false) {
                Text(LiveChat.receiptLabel(receipt.state))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            LiveChatFooterCards(accent: accent, onUpload: onUpload)
            if live.lockedBy != nil {
                LiveSystemLine(ChatText.locked)
            }
            if let lost = live.agentConnectionLost {
                LiveSystemLine(ChatText.connectionLost(lost))
            }
            QuickActionsStrip(accent: accent)
        }
        .padding(.horizontal, 12)
    }
}
