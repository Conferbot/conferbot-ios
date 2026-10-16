//
//  LiveChatExtras.swift
//  Conferbot
//
//  Live chat beyond the messages, as the web widget has it: the visitor's
//  place in the queue, what happens when nobody can join (an email for the
//  reply, leave a message), read receipts both ways, a conversation locked or
//  its composer turned off by the agent, an agent's dropped connection, an
//  agent asking for a file, the AI's follow-up email card, the post-chat
//  rating, "Email me this chat" and a blocked visitor's closed chat. Owned
//  by ConferBot (`conferBot.liveChat`); the shapes are in LiveChat.swift,
//  LiveEvents.swift and EmailTranscript.swift.
//

import Foundation
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif

public final class LiveChatExtras: ObservableObject {

    @Published public private(set) var queue: QueueStatus?
    @Published public private(set) var handoverWaiting: HandoverWaiting?
    @Published public private(set) var noAgentsAvailable = false
    @Published public private(set) var lockedBy: String?
    @Published public private(set) var visitorInputEnabled = true
    @Published public private(set) var agentConnectionLost: String?
    @Published public private(set) var fileRequestedBy: String?
    @Published public private(set) var receiptMarks = ReceiptMarks()
    @Published public private(set) var leadCardOpen = false
    @Published public private(set) var csatConfig: CsatConfig?
    @Published public private(set) var csatOpen = false
    // What the visitor already sent from a card (kept here, not in the card,
    // so a re-render does not bring the form back).
    @Published public private(set) var leftMessageTo: String?
    @Published public private(set) var leadEmail: String?
    @Published public private(set) var csatSent = false
    /// The workspace blocked this visitor: the closed line (LiveEvents), else nil (#40).
    @Published public private(set) var blocked: String?
    /// "Email me this chat": the card is up, and where it went once sent (#39).
    @Published public private(set) var emailTranscriptOpen = false
    @Published public private(set) var emailTranscriptSentTo: String?
    /// The server's transcript email (APIClient.sendTranscriptEmail); ConferBot sets it.
    var postTranscriptEmail: ((_ chatSessionId: String, _ email: String) async -> TranscriptEmailResult)?

    private let socket: () -> SocketClient?
    private let sessionId: () -> String?
    private let chatState: () -> ChatState
    private let addMessage: (any RecordItem) -> Void
    private let sendRecord: () -> Void

    private var queueTimer: Timer?
    private var waitTimer: Timer?
    private var reportedDelivered = ""
    private var reportedSeen = ""

    init(socket: @escaping () -> SocketClient?,
         sessionId: @escaping () -> String?,
         chatState: @escaping () -> ChatState,
         addMessage: @escaping (any RecordItem) -> Void,
         sendRecord: @escaping () -> Void) {
        self.socket = socket
        self.sessionId = sessionId
        self.chatState = chatState
        self.addMessage = addMessage
        self.sendRecord = sendRecord
    }

    private func main(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func own(_ data: [String: Any]?) -> Bool {
        let id = data?["chatSessionId"] as? String ?? ""
        guard let mine = sessionId(), !id.isEmpty else { return true }
        return id == mine
    }

    /// fetched-chatbot-data: the bot's post-chat rating settings.
    func setChatbotData(_ chatbotData: [String: Any]) {
        let config = LiveChat.csatConfig(chatbotData["csatConfig"] as? [String: Any])
        main { self.csatConfig = config }
    }

    func setupListeners() {
        guard let s = socket() else { return }
        func on(_ event: String, _ fn: @escaping ([String: Any]?) -> Void) {
            s.on(event) { data, _ in fn(data.first as? [String: Any]) }
        }
        on("queue-status") { d in
            guard self.own(d) else { return }
            let q = LiveChat.queueStatus(d)
            self.main { self.queue = q }
        }
        on("handover-waiting") { d in
            guard self.own(d) else { return }
            let w = LiveChat.handoverWaiting(d)
            self.main {
                self.queue = nil
                self.handoverWaiting = w
            }
        }
        on("no-agents-available") { _ in
            self.main {
                self.queue = nil
                self.stopQueuePoll()
                self.noAgentsAvailable = true
            }
        }
        on("agent-accepted") { d in
            // A person (or the AI taking it back) answered: the wait is over.
            let details = d?["agentDetails"] as? [String: Any]
            let person = details != nil && (details?["isAIAgent"] as? Bool) != true
            self.main {
                self.queue = nil
                self.stopQueuePoll()
                self.noAgentsAvailable = false
                if person { self.handoverWaiting = nil }
            }
        }
        on("conversation-locked") { d in
            guard self.own(d) else { return }
            let who = (d?["lockedByName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "the team"
            self.main { self.lockedBy = who }
        }
        on("conversation-unlocked") { d in
            guard self.own(d) else { return }
            self.main { self.lockedBy = nil }
        }
        on("visitor-input-toggled") { d in
            guard self.own(d) else { return }
            let enabled = (d?["isInputEnabled"] as? Bool) != false
            self.main { self.visitorInputEnabled = enabled }
        }
        on("agent-connection-lost") { d in
            guard self.own(d) else { return }
            let who = (d?["agentName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "The agent"
            self.main { self.agentConnectionLost = who }
        }
        on("agent-connection-restored") { d in
            guard self.own(d) else { return }
            self.main { self.agentConnectionLost = nil }
        }
        on("file-upload-requested") { d in
            guard self.own(d) else { return }
            let who = (d?["agentName"] as? String)?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "The team"
            self.chatState().pushServerEntry([
                "id": "file-request-\(Int(Date().timeIntervalSince1970 * 1000))",
                "shape": "agent-file-request",
                "type": "agent-file-request",
                "agentName": who,
            ])
            self.main { self.fileRequestedBy = who }
        }
        on("agent-read-status") { d in
            guard self.own(d) else { return }
            let marks = LiveChat.receiptMarks(d)
            self.main { self.receiptMarks = marks }
        }
        on("agent-message") { d in
            // Buying intent and no email yet: the one-field follow-up card.
            let ai = ((d?["agentDetails"] as? [String: Any])?["isAIAgent"] as? Bool) == true
            if ai && (d?["leadCard"] as? Bool) == true { self.main { self.leadCardOpen = true } }
        }
    }

    /// chat-ended, once per end (ConferBot drops the same end again, #40):
    /// the queue and the agent's asks go, the post-chat rating shows.
    func chatEnded() {
        main {
            self.queue = nil
            self.stopQueuePoll()
            self.lockedBy = nil
            self.fileRequestedBy = nil
            self.csatOpen = true
        }
    }

    /// Blocked by the workspace, mid-chat or at the handshake (web
    /// _applyVisitorBlock): the chat closes with a neutral line, whatever was
    /// waiting goes, and nothing more is taken (#40).
    func block(_ text: String) {
        stopQueuePoll()
        stopWaitTimer()
        main {
            self.blocked = text
            self.queue = nil
            self.handoverWaiting = nil
            self.noAgentsAvailable = false
            self.leadCardOpen = false
            self.fileRequestedBy = nil
            self.csatOpen = false
            self.emailTranscriptOpen = false
        }
    }

    /// "Email me this chat" from the chat menu: the card, once at a time (web mountEmailTranscript).
    public func openEmailTranscript() {
        main {
            guard self.blocked == nil else { return }
            self.emailTranscriptSentTo = nil
            self.emailTranscriptOpen = true
        }
    }

    public func closeEmailTranscript() {
        main { self.emailTranscriptOpen = false }
    }

    /// Send the transcript to this address. Sent: the address is kept as the
    /// visitor's (user metadata, the email answer) and the record goes, as
    /// the web's rememberEmail does. `done` gets the result on the main thread.
    public func emailTranscript(_ email: String, done: @escaping (TranscriptEmailResult) -> Void = { _ in }) {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailTranscript.isEmail(address) else {
            return main { done(TranscriptEmailResult(ok: false, message: EmailTranscript.Copy.checkEmail)) }
        }
        guard let id = sessionId(), let post = postTranscriptEmail else {
            return main { done(TranscriptEmailResult(ok: false)) }
        }
        Task {
            let r = await post(id, address)
            if r.ok {
                self.chatState().updateMetadata(key: "email", value: address)
                self.chatState().setAnswer(nodeId: "email-transcript", value: address)
                self.sendRecord()
            }
            self.main {
                if r.ok {
                    self.emailTranscriptSentTo = address
                    self.emailTranscriptOpen = false
                }
                done(r)
            }
        }
    }

    /// Where the visitor stands: asked every 20s while a handover waits for a person.
    public func startQueuePoll() {
        main {
            guard self.queueTimer == nil else { return }
            self.askQueue()
            self.queueTimer = Timer.scheduledTimer(withTimeInterval: LiveChat.queuePollSeconds, repeats: true) { [weak self] _ in
                self?.askQueue()
            }
        }
    }

    public func stopQueuePoll() {
        main {
            self.queueTimer?.invalidate()
            self.queueTimer = nil
        }
    }

    /// The handover step's max wait: once it passes with nobody joined, the
    /// server is asked to decide (handover-timeout) and answers with
    /// no-agents-available. Once per wait.
    public func startWaitTimer(nodeData: [String: Any]?, workspaceId: String?) {
        main {
            guard self.waitTimer == nil else { return }
            self.waitTimer = Timer.scheduledTimer(withTimeInterval: LiveChat.waitSeconds(nodeData?["maxWaitTime"]), repeats: false) { [weak self] _ in
                guard let self, let id = self.sessionId() else { return }
                self.socket()?.emit(event: "handover-timeout", data: LiveChat.handoverTimeoutPayload(chatSessionId: id, nodeData: nodeData, workspaceId: workspaceId))
            }
        }
    }

    public func stopWaitTimer() {
        main {
            self.waitTimer?.invalidate()
            self.waitTimer = nil
        }
    }

    private func askQueue() {
        guard let id = sessionId() else { return }
        socket()?.emitWithAck(event: "queue-status", data: ["chatSessionId": id], timeout: 10) { res in
            if let q = LiveChat.queueStatus(res as? [String: Any]) { self.main { self.queue = q } }
        }
    }

    /// The visitor's receipts for the agent's newest message: delivered when
    /// it arrives, seen while the chat is on screen.
    public func reportReceipts(chatVisible: Bool) {
        let latest = LiveChat.latestAgentMessageId(Self.entries(chatState().getServerRecord()))
        guard !latest.isEmpty, let id = sessionId(), let s = socket() else { return }
        if reportedDelivered != latest {
            reportedDelivered = latest
            s.emit(event: "visitor-read-receipt", data: ["chatSessionId": id, "messageId": latest, "state": "delivered"])
        }
        if chatVisible && reportedSeen != latest {
            reportedSeen = latest
            s.emit(event: "visitor-read-receipt", data: ["chatSessionId": id, "messageId": latest, "state": "seen"])
        }
    }

    private static func entryId(_ prefix: String) -> String {
        "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))-\(String(UInt32.random(in: 0...UInt32.max), radix: 36))"
    }

    /// "Leave a message" when nobody is available: by email. [done] gets ok on the main thread.
    public func leaveMessage(email: String, message: String, done: @escaping (Bool) -> Void) {
        guard let s = socket(), let id = sessionId() else { return main { done(false) } }
        let entryId = Self.entryId("leave-message")
        let visitorId = chatState().visitorId ?? id
        s.emitWithAck(event: "leave-message", data: ["chatSessionId": id, "email": email, "message": message, "entryId": entryId, "visitorId": visitorId], timeout: 15) { res in
            let ok = ((res as? [String: Any])?["ok"] as? Bool) == true
            if ok {
                self.chatState().pushServerEntry([
                    "id": entryId, "_id": entryId, "shape": "user-message", "type": "user-message",
                    "via": "email", "text": message, "data": ["leftMessage": true, "email": email],
                ])
            }
            self.main {
                if ok {
                    self.addMessage(UserMessageRecord(id: entryId, time: Date(), text: message))
                    self.leftMessageTo = email
                    self.noAgentsAvailable = false
                }
                done(ok)
            }
        }
    }

    /// The email the team replies to when nobody could join (handover-waiting).
    public func shareEmailForReply(_ email: String, done: @escaping (Bool) -> Void) {
        guard let s = socket(), let id = sessionId() else { return main { done(false) } }
        let entryId = Self.entryId("handover-email")
        let visitorId = chatState().visitorId ?? id
        s.emitWithAck(event: "handover-email", data: ["chatSessionId": id, "email": email, "entryId": entryId, "visitorId": visitorId], timeout: 15) { res in
            let ok = ((res as? [String: Any])?["ok"] as? Bool) == true
            if ok {
                self.chatState().pushServerEntry([
                    "id": entryId, "_id": entryId, "shape": "user-message", "type": "user-message",
                    "via": "email", "text": email, "data": ["handoverEmail": true, "email": email],
                ])
            }
            self.main {
                if ok {
                    self.handoverWaiting?.askEmail = false
                    self.handoverWaiting?.email = email
                }
                done(ok)
            }
        }
    }

    /// The AI's follow-up card: the email kept as the visitor's, the record sent.
    public func captureLeadEmail(_ email: String) {
        chatState().updateMetadata(key: "email", value: email)
        chatState().setAnswer(nodeId: "lead-card", value: email)
        sendRecord()
        main {
            self.leadEmail = email
            self.leadCardOpen = false
        }
    }

    /// The post-chat rating (value: Int, or Bool for thumbs).
    public func submitRating(_ value: Any, feedback: String?) {
        guard let config = csatConfig, let id = sessionId() else { return }
        socket()?.emit(event: "submit-chat-rating", data: LiveChat.ratingPayload(chatSessionId: id, type: config.ratingType, value: value, feedback: feedback))
        main { self.csatSent = true }
    }

    public func dismissCsat() {
        main { self.csatOpen = false }
    }

    /// The visitor's file in a live chat, uploaded already: recorded as the web widget does.
    public func sendLiveFile(url: String, fileName: String?, mimeType: String?) {
        let id = Self.entryId("user-file")
        chatState().pushServerEntry(["id": id, "_id": id, "shape": "user-live-message-file", "type": "user-live-message-file", "url": url])
        sendRecord()
        main {
            self.addMessage(UserLiveMessageFileRecord(id: id, time: Date(), url: url, fileName: fileName, mimeType: mimeType))
            self.fileRequestedBy = nil
        }
    }

    func reset() {
        stopWaitTimer()
        stopQueuePoll()
        main {
            self.queue = nil
            self.handoverWaiting = nil
            self.noAgentsAvailable = false
            self.lockedBy = nil
            self.visitorInputEnabled = true
            self.agentConnectionLost = nil
            self.fileRequestedBy = nil
            self.receiptMarks = ReceiptMarks()
            self.leadCardOpen = false
            self.csatOpen = false
            self.leftMessageTo = nil
            self.leadEmail = nil
            self.csatSent = false
            self.blocked = nil
            self.emailTranscriptOpen = false
            self.emailTranscriptSentTo = nil
        }
        reportedDelivered = ""
        reportedSeen = ""
    }

    /// The conversation as the receipt logic sees it: the server record,
    /// where a visitor's live message has its own shape and the same id as
    /// its bubble.
    public static func entries(_ serverRecord: [[String: Any]]) -> [LiveEntry] {
        serverRecord.map { e in
            LiveEntry(id: (e["id"] as? String) ?? (e["_id"] as? String) ?? "",
                      kind: (e["shape"] as? String) ?? (e["type"] as? String) ?? "")
        }
    }

    /// The "Sent / Delivered / Seen" line, while a person is on the other end.
    public func visitorReceipt(personHere: Bool) -> VisitorReceipt? {
        guard personHere else { return nil }
        return LiveChat.visitorReceipt(Self.entries(chatState().getServerRecord()), marks: receiptMarks)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
