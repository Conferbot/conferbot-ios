//
//  FlowContext.swift
//  Conferbot
//
//  What a step handler may use besides the chat state: the bot's server
//  endpoints, the socket, timers, the flow's edges (as the React Native
//  SDK's src/core/flow/context.ts). The engine passes one with every node
//  it hands a handler, under the node's "ctx" key; a handler called on its
//  own gets a stand-alone default (ctxOf).
//
//  The clock, the transport and the socket are protocols so a test can
//  drive the real engine on a virtual clock with scripted server replies.
//

import Foundation

// MARK: - Clock

/// A timer from the flow clock; cancel() stops it.
public protocol FlowTimer: AnyObject {
    func cancel()
}

/// Time for the flow: now, waiting, and setTimeout / setInterval.
public protocol FlowClock: AnyObject {
    func now() -> Date
    /// Resolves after `ms` (at once for 0, on the next turn).
    @MainActor func sleep(ms: Double) async
    /// Runs `fn` after `ms`, again every `ms` when `repeats`.
    @MainActor func schedule(ms: Double, repeats: Bool, _ fn: @escaping @MainActor () -> Void) -> FlowTimer
}

/// The device's clock.
public final class SystemFlowClock: FlowClock {
    public init() {}

    public func now() -> Date { Date() }

    @MainActor public func sleep(ms: Double) async {
        if ms <= 0 {
            await Task.yield()
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
    }

    private final class Timer: FlowTimer {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    @MainActor public func schedule(ms: Double, repeats: Bool, _ fn: @escaping @MainActor () -> Void) -> FlowTimer {
        let timer = Timer()
        let wait = UInt64(max(0, ms) * 1_000_000)
        timer.task = Task { @MainActor in
            repeat {
                try? await Task.sleep(nanoseconds: max(wait, repeats ? 1_000_000 : 0))
                if Task.isCancelled { return }
                fn()
            } while repeats && !Task.isCancelled
        }
        return timer
    }
}

// MARK: - Transport

/// The bot server's HTTP: one request, the status and body, nil when the
/// server could not be reached.
public protocol FlowTransport: AnyObject {
    @MainActor func send(_ request: URLRequest) async -> (status: Int, body: Data?)?
}

public final class URLSessionFlowTransport: FlowTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    @MainActor public func send(_ request: URLRequest) async -> (status: Int, body: Data?)? {
        await withCheckedContinuation { c in
            session.dataTask(with: request) { data, response, error in
                if error != nil { return c.resume(returning: nil) }
                c.resume(returning: ((response as? HTTPURLResponse)?.statusCode ?? 0, data))
            }.resume()
        }
    }
}

// MARK: - Socket

/// The socket as the flow uses it.
public protocol FlowSocket: AnyObject {
    var isConnected: Bool { get }
    /// A socket event to the server.
    func emit(_ event: String, _ payload: [String: Any])
    /// Listen to a server event; returns the unsubscribe.
    func on(_ event: String, _ listener: @escaping ([String: Any]) -> Void) -> () -> Void
    /// The conversation's record (response-record).
    func sendResponseRecord(_ data: [String: Any])
}

/// Listeners by event, with their own unsubscribe (the app's socket has one
/// handler per event; this fans it out to the flow's steps).
public final class FlowEventHub {
    private var listeners: [String: [(UUID, ([String: Any]) -> Void)]] = [:]
    private let lock = NSLock()

    public init() {}

    public func on(_ event: String, _ listener: @escaping ([String: Any]) -> Void) -> () -> Void {
        let id = UUID()
        lock.lock()
        listeners[event, default: []].append((id, listener))
        lock.unlock()
        return { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.listeners[event]?.removeAll { $0.0 == id }
            self.lock.unlock()
        }
    }

    public func fire(_ event: String, _ payload: [String: Any]) {
        lock.lock()
        let list = listeners[event] ?? []
        lock.unlock()
        list.forEach { $0.1(payload) }
    }
}

// MARK: - Context

public struct FlowApiReply {
    public let ok: Bool
    public let status: Int
    public let body: Any?
    /// "network" when the server could not be reached, "timeout" when it took too long.
    public let error: String?
}

/// A file for the bot's media endpoint.
public struct FlowUploadFile {
    public var url: URL?
    public var name: String
    public var type: String
    public var size: Double
    /// Raw content for a generated file (a typed signature).
    public var data: Data?

    public init(url: URL? = nil, name: String, type: String, size: Double = 0, data: Data? = nil) {
        self.url = url
        self.name = name
        self.type = type
        self.size = size
        self.data = data
    }

    /// A file from an answer: {name, size, type, uri | url}.
    init(_ dict: [String: Any]) {
        let uri = JS.text(dict["uri"]).isEmpty ? JS.text(dict["url"]) : JS.text(dict["uri"])
        self.init(url: URL(string: uri), name: JS.text(dict["name"]), type: JS.text(dict["type"]), size: JS.toNumber(dict["size"]))
    }
}

/// The page a chat runs on, when the host app has one (hidden-fields).
public struct FlowPage {
    public var url: String?
    public var referrer: String?

    public init(url: String? = nil, referrer: String? = nil) {
        self.url = url
        self.referrer = referrer
    }
}

/// What a step handler may use: the bot API, the socket, timers, this step's edges.
@MainActor
public final class FlowContext {
    public let botId: String
    public let sessionId: String
    /// How this step was reached: "start", "edge:<h>", "port:<h>" or "jump".
    public let via: String
    /// The step's place in the conversation (0 = the welcome).
    public let stepIndex: Int
    public let customizations: [String: Any]
    /// The visitor's IANA time zone.
    public let visitorTimeZone: String
    public let page: FlowPage?

    let apiFn: (String, [String: Any], Double?) async -> FlowApiReply
    let uploadFn: (FlowUploadFile) async -> (ok: Bool, url: String?)
    let sendFn: (URLRequest) async -> (status: Int, body: Data?)?
    let emitFn: (String, [String: Any]) -> Bool
    let onFn: (String, @escaping ([String: Any]) -> Void) -> () -> Void
    let typingFn: (Double) async -> Void
    let clock: FlowClock
    let edgesFn: () -> [[String: Any]]
    let edgesOfFn: (String) -> [[String: Any]]
    let randomFn: () -> Double
    let respondFn: (Any) -> Void
    let shownFn: () -> Void
    let isStaleFn: () -> Bool
    let nodeFn: (String) -> [String: Any]?

    init(botId: String, sessionId: String, via: String, stepIndex: Int, customizations: [String: Any], visitorTimeZone: String, page: FlowPage?,
         api: @escaping (String, [String: Any], Double?) async -> FlowApiReply,
         upload: @escaping (FlowUploadFile) async -> (ok: Bool, url: String?),
         send: @escaping (URLRequest) async -> (status: Int, body: Data?)?,
         emit: @escaping (String, [String: Any]) -> Bool,
         on: @escaping (String, @escaping ([String: Any]) -> Void) -> () -> Void,
         typing: @escaping (Double) async -> Void,
         clock: FlowClock,
         edges: @escaping () -> [[String: Any]],
         edgesOf: @escaping (String) -> [[String: Any]],
         random: @escaping () -> Double,
         respond: @escaping (Any) -> Void,
         shown: @escaping () -> Void,
         isStale: @escaping () -> Bool,
         node: @escaping (String) -> [String: Any]?) {
        self.botId = botId
        self.sessionId = sessionId
        self.via = via
        self.stepIndex = stepIndex
        self.customizations = customizations
        self.visitorTimeZone = visitorTimeZone
        self.page = page
        apiFn = api
        uploadFn = upload
        sendFn = send
        emitFn = emit
        onFn = on
        typingFn = typing
        self.clock = clock
        edgesFn = edges
        edgesOfFn = edgesOf
        randomFn = random
        respondFn = respond
        shownFn = shown
        isStaleFn = isStale
        nodeFn = node
    }

    /// POST JSON to {api}/api/v1/bot/:botId/<path>. Never throws.
    public func api(_ path: String, _ body: [String: Any], timeoutMs: Double? = nil) async -> FlowApiReply { await apiFn(path, body, timeoutMs) }
    /// Upload a file to {api}/api/v1/bot/:botId/media; ok with the file's url.
    public func upload(_ file: FlowUploadFile) async -> (ok: Bool, url: String?) { await uploadFn(file) }
    /// Any other HTTP request (a webhook step's call); nil when it could not be sent.
    public func send(_ request: URLRequest) async -> (status: Int, body: Data?)? { await sendFn(request) }
    /// A socket event to the server; false when there is no socket.
    @discardableResult public func emit(_ event: String, _ payload: [String: Any]) -> Bool { emitFn(event, payload) }
    /// Listen to a socket event; returns the unsubscribe.
    public func on(_ event: String, _ listener: @escaping ([String: Any]) -> Void) -> () -> Void { onFn(event, listener) }
    /// Typing dots for `ms`, then resolves.
    public func typing(_ ms: Double) async { await typingFn(ms) }
    public func delay(_ ms: Double) async { await clock.sleep(ms: ms) }
    /// setTimeout / setInterval on the flow's clock.
    @discardableResult public func schedule(_ ms: Double, repeats: Bool = false, _ fn: @escaping @MainActor () -> Void) -> FlowTimer {
        clock.schedule(ms: ms, repeats: repeats, fn)
    }
    public func now() -> Date { clock.now() }
    /// The edges that leave this step, in flow order.
    public func edges() -> [[String: Any]] { edgesFn() }
    /// The edges that leave another step, in flow order.
    public func edgesOf(_ nodeId: String) -> [[String: Any]] { edgesOfFn(nodeId) }
    /// Whether an edge leaves this step by exactly this handle.
    public func wired(_ handle: String) -> Bool { edgesFn().contains { ($0["sourceHandle"] as? String) == handle } }
    public func random() -> Double { randomFn() }
    /// Give the waiting step an answer from outside (a socket event).
    public func respond(_ response: Any) { respondFn(response) }
    /// The step's content is on screen now (for a step that speaks before it returns).
    public func shown() { shownFn() }
    /// True once the flow has moved past this step.
    public func isStale() -> Bool { isStaleFn() }
    /// A node of the flow by id.
    public func node(_ id: String) -> [String: Any]? { nodeFn(id) }

    /// A context for a handler called outside the engine: no server, no socket, the device's clock.
    static func standalone(_ state: ChatState) -> FlowContext {
        let clock = SystemFlowClock()
        return FlowContext(
            botId: state.botId, sessionId: state.sessionId, via: "edge", stepIndex: 0, customizations: [:],
            visitorTimeZone: TimeZone.current.identifier, page: nil,
            api: { _, _, _ in FlowApiReply(ok: false, status: 0, body: nil, error: "network") },
            upload: { _ in (false, nil) },
            send: { _ in nil },
            emit: { _, _ in false },
            on: { _, _ in {} },
            // No chat on screen to show typing dots in: no beat to wait for.
            typing: { _ in },
            clock: clock,
            edges: { [] }, edgesOf: { _ in [] },
            random: { Double.random(in: 0..<1) },
            respond: { _ in }, shown: {}, isStale: { false }, node: { _ in nil }
        )
    }
}

/// The context the engine gave the handler, or a stand-alone default.
@MainActor
func ctxOf(_ node: [String: Any], _ state: ChatState) -> FlowContext {
    (node["ctx"] as? FlowContext) ?? FlowContext.standalone(state)
}

// MARK: - The bot API over a transport

enum BotApi {

    /// POST JSON to {origin}/api/v1/bot/:botId/<path>, with an optional client timeout.
    @MainActor
    static func post(transport: FlowTransport, clock: FlowClock, origin: String, botId: String, path: String, body: [String: Any], timeoutMs: Double?) async -> FlowApiReply {
        let botPath = botId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? botId
        guard let url = URL(string: "\(origin)/api/v1/bot/\(botPath)/\(path)") else {
            return FlowApiReply(ok: false, status: 0, body: nil, error: "network")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: JS.plain(body) ?? [:])
        let call: @MainActor () async -> FlowApiReply = {
            guard let reply = await transport.send(request) else { return FlowApiReply(ok: false, status: 0, body: nil, error: "network") }
            let json = reply.body.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
            return FlowApiReply(ok: reply.status >= 200 && reply.status < 300, status: reply.status, body: json, error: nil)
        }
        guard let timeout = timeoutMs else { return await call() }
        return await race(clock: clock, ms: timeout, timedOut: FlowApiReply(ok: false, status: 0, body: nil, error: "timeout"), call)
    }

    /// Upload a file to the bot's media endpoint (multipart "file").
    @MainActor
    static func upload(transport: FlowTransport, origin: String, botId: String, sessionId: String, visitorId: String, file: FlowUploadFile) async -> (ok: Bool, url: String?) {
        let q = "chatSessionId=\(FlowText.encodeURIComponent(sessionId))&visitorId=\(FlowText.encodeURIComponent(visitorId))"
        let botPath = botId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? botId
        guard let url = URL(string: "\(origin)/api/v1/bot/\(botPath)/media?\(q)") else { return (false, nil) }
        let boundary = "conferbot-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let content = file.data ?? file.url.flatMap { $0.isFileURL ? try? Data(contentsOf: $0) : nil } ?? Data()
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(file.name)\"\r\nContent-Type: \(file.type.isEmpty ? "application/octet-stream" : file.type)\r\n\r\n".data(using: .utf8)!)
        body.append(content)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        guard let reply = await transport.send(request) else { return (false, nil) }
        let json = reply.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        // Only a 2xx answer that carries the file's URL is an upload (web nodeLogic.uploadSucceeded)
        if reply.status >= 200, reply.status < 300, let u = json?["url"] as? String, !u.trimmed.isEmpty { return (true, u) }
        return (false, nil)
    }

    /// The first of `work` and a timeout on the flow clock (the timer is cleared either way).
    @MainActor
    static func race<T>(clock: FlowClock, ms: Double, timedOut: T, _ work: @escaping @MainActor () async -> T) async -> T {
        let once = FlowOnce<T>()
        let timer = clock.schedule(ms: ms, repeats: false) { once.resume(timedOut) }
        Task { @MainActor in once.resume(await work()) }
        let value = await once.value()
        timer.cancel()
        return value
    }
}

/// A value that arrives once, from whichever callback is first; later ones are dropped.
public final class FlowOnce<T> {
    private let lock = NSLock()
    private var result: T?
    private var continuation: CheckedContinuation<T, Never>?
    private var done = false

    public init() {}

    public func resume(_ value: T) {
        lock.lock()
        guard !done else { return lock.unlock() }
        done = true
        if let c = continuation {
            continuation = nil
            lock.unlock()
            c.resume(returning: value)
        } else {
            result = value
            lock.unlock()
        }
    }

    public func value() async -> T {
        await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            lock.lock()
            if let r = result {
                result = nil
                lock.unlock()
                c.resume(returning: r)
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }
}
