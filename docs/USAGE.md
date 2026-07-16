# Conferbot iOS SDK - Usage Guide

A step-by-step walkthrough for integrating the Conferbot iOS SDK into a real app. This guide goes deeper than the README: it covers project setup, each integration pattern, user identity, theming, offline behavior, push notifications, the knowledge base, and a fully headless integration driven by the node flow engine.

All code in this guide compiles against SDK version 1.0.0.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install the SDK](#2-install-the-sdk)
3. [Initialize the SDK](#3-initialize-the-sdk)
4. [Identify Your User](#4-identify-your-user)
5. [Add the Floating Widget (FAB)](#5-add-the-floating-widget-fab)
6. [Present Chat Directly](#6-present-chat-directly)
7. [Theming](#7-theming)
8. [Sessions and Persistence](#8-sessions-and-persistence)
9. [Offline Behavior](#9-offline-behavior)
10. [Push Notifications](#10-push-notifications)
11. [Knowledge Base](#11-knowledge-base)
12. [Going Headless](#12-going-headless)
13. [Live Agent Handover](#13-live-agent-handover)
14. [Analytics and Goals](#14-analytics-and-goals)
15. [Self-Hosted / Custom Endpoints](#15-self-hosted--custom-endpoints)
16. [Troubleshooting Checklist](#16-troubleshooting-checklist)

---

## 1. Prerequisites

- Xcode 14.0 or later, Swift 5.7 - 5.9
- An app targeting iOS 14.0+ (the SwiftUI and UIKit components require iOS 14; the FAB's vector launcher icons use `Path(svgPath:)` on iOS 17+ and fall back to a system bubble icon on earlier versions)
- A Conferbot account with a **published** bot, or the public demo bot ID `691c970890527a0468f9b2c9` for a quick trial

Grab your credentials from [app.conferbot.com](https://app.conferbot.com):

- **Bot ID**: Bot Settings > General
- **API Key**: Workspace Settings > API Keys (starts with `conf_`)

## 2. Install the SDK

### Swift Package Manager

In Xcode: **File > Add Packages**, paste `https://github.com/conferbot/conferbot-ios`, and add the `Conferbot` library to your app target. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/conferbot/conferbot-ios", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "Conferbot", package: "conferbot-ios")
        ]
    )
]
```

### CocoaPods

```ruby
platform :ios, '14.0'
use_frameworks!

target 'MyApp' do
  pod 'Conferbot', '~> 1.0'
end
```

```bash
pod install
```

Both routes pull in `socket.io-client-swift` 16.x automatically.

## 3. Initialize the SDK

Everything hangs off the singleton `ConferBot.shared` (module `Conferbot`, class `ConferBot`). Call `initialize` once, as early as possible. It validates the key (must start with `conf_`), connects the Socket.IO client, requests your bot's dashboard customizations, and restores any still-valid persisted session.

### SwiftUI app

```swift
import SwiftUI
import Conferbot

@main
struct MyApp: App {
    init() {
        ConferBot.shared.initialize(
            apiKey: "conf_YOUR_API_KEY",
            botId: "YOUR_BOT_ID"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### UIKit app

```swift
import UIKit
import Conferbot

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ConferBot.shared.initialize(
            apiKey: "conf_YOUR_API_KEY",
            botId: "YOUR_BOT_ID"
        )
        return true
    }
}
```

### With configuration and customization

```swift
let config = ConferBotConfig(
    enableNotifications: true,   // default true
    enableOfflineMode: true      // default true - queue messages while offline
)

let customization = ConferBotCustomization(
    primaryColor: .systemIndigo,
    headerTitle: "Acme Support",
    showAvatar: true
)

ConferBot.shared.initialize(
    apiKey: "conf_YOUR_API_KEY",
    botId: "YOUR_BOT_ID",
    config: config,
    customization: customization
)
```

Note: `initialize` traps (fatalError) on an empty API key, an empty bot ID, or a key that does not start with `conf_`. Fail fast in development rather than silently shipping a broken integration.

## 4. Identify Your User

Call `identify(user:)` before starting a session so the conversation is attributed to a known user in your dashboard. Skip it and the SDK generates a persistent anonymous visitor ID instead (stored in `UserDefaults`, stable across launches).

```swift
import Conferbot

func onLogin(_ account: Account) {
    let user = ConferBotUser(
        id: account.id,                       // required
        name: account.displayName,            // optional
        email: account.email,                 // optional
        phone: account.phone,                 // optional
        metadata: [                            // optional, [String: AnyCodable]
            "plan": AnyCodable(account.plan),
            "orders": AnyCodable(account.orderCount)
        ]
    )
    ConferBot.shared.identify(user: user)
}
```

On logout, clear the persisted conversation so the next user does not see it:

```swift
ConferBot.shared.endSession(clearStorage: true)
ConferBot.shared.clearHistory()
```

## 5. Add the Floating Widget (FAB)

This is the closest match to the web widget experience: a floating bubble (bottom-right by default) that opens the chat in a sheet.

```swift
import SwiftUI
import Conferbot

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "house") }
            OrdersView().tabItem { Label("Orders", systemImage: "shippingbox") }
        }
        .conferBotWidget()
    }
}
```

What you get, with zero configuration:

- Bubble color, size, corner radius, position (left/right), and edge offsets from your dashboard's widget settings
- Your chosen launcher icon (all 15 web widget bubble icons are supported natively on iOS 17+; older iOS versions show a filled system chat bubble)
- The CTA tooltip (`chatIconCtaText`) appears 2 seconds after customizations load and dismisses on tap
- An unread badge on the bubble, cleared automatically when the chat opens
- Tap toggles between the bubble icon and a close (X) icon, like the web widget

The equivalent container form, if you prefer explicit composition over a modifier:

```swift
ConferBotWidgetOverlay {
    RootContent()
}
```

`ConferBotFABConfig` currently has no options (`ConferBotFABConfig()` only); FAB appearance is intentionally server-driven so it always matches your web widget. Change it from the dashboard, not from code.

There is no UIKit-native FAB. In a UIKit app, either host `ConferBotWidgetOverlay` in a `UIHostingController`, or add your own button that calls `ConferBot.shared.present(from: self)`.

## 6. Present Chat Directly

### UIKit modal

```swift
import Conferbot

class SupportViewController: UIViewController {
    @objc func contactSupportTapped() {
        ConferBot.shared.present(from: self) // full-screen, wrapped in a UINavigationController
    }
}
```

### SwiftUI sheet or navigation

```swift
struct SupportSection: View {
    @State private var showChat = false

    var body: some View {
        Section {
            Button("Chat with us") { showChat = true }
        }
        .sheet(isPresented: $showChat) {
            ChatView()
        }
    }
}
```

`ChatView` calls `startSession()` itself on first appearance, shows the message list, input bar, typing indicators, and (by default) a Help tab backed by your knowledge base. Disable the tab with:

```swift
ChatView(enableKnowledgeBase: false)
```

Prefer the KB in a sheet rather than a tab? Use `ChatViewWithKBSheet()`.

### Embedded inline

`ChatView` is an ordinary SwiftUI view; you can embed it in a split view, a tab, or any container:

```swift
NavigationView {
    ChatView()
        .navigationBarHidden(true)
}
```

## 7. Theming

Two layers style the experience. Understand which layer controls what:

### Server customizations (dashboard) - automatic

On every socket connect the SDK requests the bot configuration and publishes it as `ConferBot.shared.serverCustomizations` (`[String: Any]?`). Applied automatically:

| Dashboard setting | Where it applies |
|-------------------|------------------|
| `widgetIconBgColor` / `headerBgColor` | FAB bubble color (icon color first, header color as fallback, default `#1b55f3`) |
| `widgetSize`, `widgetBorderRadius` | FAB size and shape |
| `widgetPosition`, `widgetOffsetLeft/Right/Bottom` | FAB placement |
| `widgetIconSVG`, `widgetIconType`, `widgetIconImage` | FAB launcher icon |
| `chatIconCtaText` | CTA tooltip next to the FAB |
| `hideBrand` | Hides "Powered by Conferbot" (server value wins over the local flag) |
| `botName` / `logoText` | Bot name available to flow nodes |
| Flow content and node data | Everything the bot says and asks |

### Local customization (`ConferBotCustomization`) - the chat surface

```swift
let customization = ConferBotCustomization(
    primaryColor: UIColor.systemIndigo,   // send button and accents
    fontFamily: "SFProText-Regular",
    bubbleCornerRadius: 16,               // default 16 when nil
    headerTitle: "Acme Support",          // default "Support Chat"
    showAvatar: true,                     // default true
    avatarURL: URL(string: "https://example.com/bot.png"),
    botBubbleColor: UIColor.systemGray6,
    userBubbleColor: UIColor.systemIndigo,
    hideBrand: false
)
```

Pass it in `initialize(...)`. You can also swap it at runtime, since `ConferBot.shared.customization` is a public mutable property.

### Precedence, exactly as implemented

- **FAB**: server-only. No local overrides exist.
- **hideBrand**: `serverCustomizations["hideBrand"]` first, then `customization.hideBrand`, then `false`.
- **Header title, avatar, bubble colors, corner radius, primary color**: local `ConferBotCustomization` only. The iOS chat surface does not currently remap dashboard theme colors onto message bubbles, so if you want the in-chat colors to match your web widget, mirror them in `ConferBotCustomization`.
- **Dark mode**: automatic. The built-in UI uses dynamic system colors, so it follows the device appearance.

## 8. Sessions and Persistence

Sessions persist automatically: the session record, messages, flow answers, user metadata, and transcript are saved after every meaningful interaction and restored on the next `initialize` while unexpired.

```swift
// Expiry window (extends on activity)
ConferBot.shared.configureSessionStorage(expiryMinutes: 24 * 60)

// Inspect
ConferBot.shared.hasValidStoredSession()   // Bool
ConferBot.shared.getSessionExpiry()        // Date?
ConferBot.shared.hasRestoredSession        // @Published Bool

// Start / reuse
try await ConferBot.shared.startSession()               // reuses a restored session if present
try await ConferBot.shared.startSession(forceNew: true) // always creates a fresh conversation

// End
ConferBot.shared.endSession()                    // ends and clears storage (default)
ConferBot.shared.endSession(clearStorage: false) // ends but keeps the stored transcript
ConferBot.shared.clearStoredSession()            // wipe storage without ending
```

`startSession` throws `ConferBotError.notInitialized` if you call it before `initialize`. Other error cases you may encounter from the API layer: `.invalidResponse`, `.httpError(Int)`, `.apiError(String)`, `.noData`, `.socketNotConnected`.

## 9. Offline Behavior

With `enableOfflineMode: true` (the default):

- `sendMessage` appends the message to the local list immediately, then either sends it over the socket or, if offline, queues it.
- When connectivity or the socket returns, the queue flushes automatically and the chat room is rejoined (Socket.IO drops room membership on disconnect; the SDK handles the rejoin).

Surface the state to your users:

```swift
struct ConnectionBanner: View {
    @ObservedObject var bot = ConferBot.shared

    var body: some View {
        if !bot.isOnline {
            Text(bot.queuedMessageCount > 0
                 ? "Offline - \(bot.queuedMessageCount) message(s) queued"
                 : "Offline")
                .font(.caption)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.2))
        }
    }
}
```

Manual controls when you need them:

```swift
ConferBot.shared.queuedMessages        // [QueuedMessage]
ConferBot.shared.flushMessageQueue()
ConferBot.shared.retryFailedMessages()
ConferBot.shared.clearMessageQueue()
```

Delegate equivalents: `didChangeNetworkStatus(isOnline:)` and `didUpdateQueuedMessageCount(count:)`.

## 10. Push Notifications

1. Request notification permission and register with APNs as usual.
2. Forward the hex token to the SDK:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    ConferBot.shared.registerPushToken(token)
}
```

Registration is sent to the server against the current chat session. If no session exists yet, the token is only held in memory - call `registerPushToken` again once a session has started to guarantee it reaches the server.

3. Route incoming notifications. The SDK only claims payloads carrying `type: "conferbot_message"`; for those it increments the unread count (reflected on the FAB badge and via `didUpdateUnreadCount`) and returns `true`:

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    completionHandler(ConferBot.shared.handlePushNotification(userInfo) ? .newData : .noData)
}
```

## 11. Knowledge Base

Three ways to use it:

**Built into ChatView** - the Help tab is on by default (`ChatView(enableKnowledgeBase: true)`).

**Standalone view**:

```swift
.sheet(isPresented: $showHelp) {
    KnowledgeBaseView()
}
```

**Fully custom, via the async APIs**:

```swift
struct HelpCenterModel {
    func load() async throws {
        let categories = try await ConferBot.shared.fetchKnowledgeBaseCategories()
        let articles   = try await ConferBot.shared.fetchKnowledgeBaseArticles()
        _ = (categories, articles)
    }

    func search(_ text: String) async throws -> [KnowledgeBaseArticle] {
        try await ConferBot.shared.searchKnowledgeBaseArticles(query: text)
    }

    func open(_ id: String) async throws -> KnowledgeBaseArticle {
        let article = try await ConferBot.shared.getKnowledgeBaseArticle(id: id)
        ConferBot.shared.trackKnowledgeBaseArticleView(articleId: article.id)
        ConferBot.shared.startKnowledgeBaseArticleEngagement(articleId: article.id)
        return article
    }

    func closeArticle(scrolled: Double) {
        ConferBot.shared.updateKnowledgeBaseScrollDepth(scrolled) // 0.0 - 1.0
        ConferBot.shared.sendKnowledgeBaseEngagement()
    }

    func rate(_ id: String, helpful: Bool) {
        ConferBot.shared.rateKnowledgeBaseArticle(articleId: id, helpful: helpful) { success in
            print("rating sent: \(success)")
        }
    }
}
```

Related articles are computed locally from already-fetched data:

```swift
let related = ConferBot.shared.getRelatedKnowledgeBaseArticles(for: article, limit: 3)
```

Loading state is published as `isLoadingKnowledgeBase`, and fetched categories as `knowledgeBaseCategories`.

## 12. Going Headless

Skip the built-in UI entirely. Two complementary observation mechanisms:

- **Delegate** (`ConferBotDelegate`): imperative callbacks, good for UIKit.
- **Published properties** on `ConferBot.shared`: reactive, good for SwiftUI/Combine.

### The critical concept: flow nodes, not just text

If your bot is built with the flow builder (choices, forms, ratings...), bot turns arrive as **node UI states**, not plain messages. Your custom UI must render `currentUIState` (a `NodeUIState`) and reply through the typed `handle...` methods, which also append the user's answer as a message bubble, store it in the flow state, and advance the flow.

```swift
import Conferbot
import Combine

final class HeadlessChatModel: ObservableObject, ConferBotDelegate {
    @Published var messages: [any RecordItem] = []
    @Published var pendingNode: NodeUIState?

    private var cancellables = Set<AnyCancellable>()

    init() {
        ConferBot.shared.delegate = self

        // Mirror SDK state into this model
        ConferBot.shared.$messages
            .receive(on: DispatchQueue.main)
            .assign(to: &$messages)

        Task { try? await ConferBot.shared.startSession() }
    }

    // Free-text send (used when no interactive node is pending)
    func send(_ text: String) {
        Task { try? await ConferBot.shared.sendMessage(text) }
    }

    // Answer whatever node is currently displayed
    func answerText(_ text: String) {
        guard let nodeId = ConferBot.shared.getCurrentNodeId() else { return }
        ConferBot.shared.handleNodeInput(text, forNodeId: nodeId)
    }

    func pickChoice(_ optionId: String) {
        guard let nodeId = ConferBot.shared.getCurrentNodeId() else { return }
        ConferBot.shared.handleChoiceSelection(optionId: optionId, forNodeId: nodeId)
    }

    func rate(_ stars: Int) {
        guard let nodeId = ConferBot.shared.getCurrentNodeId() else { return }
        ConferBot.shared.handleRatingSelection(rating: stars, forNodeId: nodeId)
    }

    // MARK: ConferBotDelegate
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {}
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent) {}
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent) {}
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String) {}
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String) {}
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int) {}
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool) {}

    // Optional (has a default implementation) - the interactive node to render
    func conferBot(_ conferBot: ConferBot, didUpdateUIState state: NodeUIState?) {
        DispatchQueue.main.async { self.pendingNode = state }
    }
}
```

Other headless utilities:

```swift
ConferBot.shared.nodeRequiresInteraction("user-input")  // does this node type wait for input?
ConferBot.shared.resetFlow()                            // "restart conversation": new session, cleared state
ConferBot.shared.isFlowComplete                         // @Published; also didCompleteFlow(success:)
ConferBot.shared.nodeErrorMessage                       // @Published validation/flow error
ConferBot.shared.handleFileUpload(fileURL: url, forNodeId: nodeId)
ConferBot.shared.handleDateSelection(date: Date(), forNodeId: nodeId)
ConferBot.shared.handleMultipleChoiceSelection(optionIds: ["a", "b"], forNodeId: nodeId)
```

## 13. Live Agent Handover

Hand the conversation to a human agent:

```swift
ConferBot.shared.initiateHandover(message: "I need help with billing")
```

Then react to the lifecycle:

```swift
ConferBot.shared.isLiveChatMode   // @Published Bool
ConferBot.shared.currentAgent     // @Published Agent?
ConferBot.shared.isAgentTyping    // @Published Bool
```

Delegate callbacks: `agentDidJoin(agent:)` and `agentDidLeave(agent:)`. Agent messages arrive through the same `didReceiveMessage` / `messages` pipeline (HTML from the agent console is stripped to plain text). While in live chat, `sendTypingIndicator(isTyping:)` shows the visitor's typing state to the agent, and the indicator is cleared automatically when a message is sent. If no agents are online, the bot flow continues and the SDK handles the server's no-agents event internally.

## 14. Analytics and Goals

Analytics tracking starts automatically with each session (messages, node enters/exits, interactions, typing). Two explicit hooks:

```swift
// Conversion goals - also fires the didReachGoal delegate callback
ConferBot.shared.trackGoal(goalId: "checkout", goalName: "Checkout Complete", value: 199.0)

// Raw access to the analytics engine
let analytics = ConferBot.shared.analytics   // ChatAnalytics.shared
```

Need to talk to the server directly (integration nodes, custom events)?

```swift
ConferBot.shared.emitSocketEvent("my-custom-event", data: ["orderId": "A-1001"])
// chatSessionId is appended automatically
```

## 15. Self-Hosted / Custom Endpoints

Defaults point at production: API `https://wdt.conferbot.com/api/v1/mobile`, socket `https://wdt.conferbot.com`. Override before `initialize` (HTTPS is enforced with a precondition):

```swift
ConferBotEndpoints.configure(
    apiBaseURL: "https://embed.yourdomain.com/api/v1/mobile",
    socketURL: "https://embed.yourdomain.com"
)
// ConferBotEndpoints.resetToDefaults() to undo

ConferBotNetworkConfig.configure(
    apiTimeout: 30,
    socketTimeout: 20,
    reconnectionAttempts: 5,
    reconnectionDelay: 1.0,
    reconnectionDelayMax: 5.0
)
```

Capture SDK logs in your own pipeline:

```swift
ConferBotLogger.logHandler = { message, level in
    MyLogger.log("\(level.rawValue): \(message)")
}
```

## 16. Troubleshooting Checklist

Work through these in order when the bot does not appear or respond:

1. **Is the bot published?** Draft bots do not serve traffic. Publish from the dashboard.
2. **Is the botId correct?** Copy it from Bot Settings > General. A wrong ID connects but never receives flow data.
3. **Does the API key start with `conf_`?** `initialize` traps on malformed keys.
4. **Is `https://wdt.conferbot.com` reachable** from the device? Test in Safari on the same device; VPNs and corporate proxies sometimes block websockets.
5. **Rule out your setup with the demo bot**: bot ID `691c970890527a0468f9b2c9` works without an account. If the demo works and your bot does not, the problem is your bot's configuration or credentials, not the app.
6. **Watch connection state**: `ConferBot.shared.isConnected` and the `didChangeConnectionStatus` callback. Attach `ConferBotLogger.logHandler` for detailed logs.
7. **Session started?** Custom UIs must call `startSession()`; the built-in `ChatView` does it automatically.
8. **Socket.IO build issues?** `rm -rf ~/Library/Developer/Xcode/DerivedData`, and for CocoaPods `pod deintegrate && pod install`.

Screenshots of the expected result:

<p align="center">
  <img src="screenshots/chat-widget.png" width="260" alt="Chat Widget" />
  <img src="screenshots/choice-node.png" width="260" alt="Choice Node" />
  <img src="screenshots/themed-chat.png" width="260" alt="Themed Chat" />
</p>

---

Questions? Open an issue at [conferbot/conferbot-ios](https://github.com/conferbot/conferbot-ios/issues) or email support@conferbot.com.
