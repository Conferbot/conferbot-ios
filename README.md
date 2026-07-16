# Conferbot iOS SDK

Native iOS SDK for embedding Conferbot AI-powered chatbots into your iOS applications.

[![Platform](https://img.shields.io/badge/Platform-iOS-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.7+-F05138.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-14.0+-000000.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

<p align="center">
  <img src="docs/screenshots/chat-swiftui.png" width="280" alt="SwiftUI Chat" />
  <img src="docs/screenshots/choice-node.png" width="280" alt="Choice Node" />
  <img src="docs/screenshots/themed-chat.png" width="280" alt="Themed Chat" />
</p>

<p align="center">
  <img src="docs/screenshots/chat-widget.png" width="280" alt="Chat Widget" />
</p>

## Features

- **Drop-in chat UI** - SwiftUI `ChatView` and a UIKit `ChatViewController` presented with one line
- **Floating widget (FAB)** - `.conferBotWidget()` overlay that mirrors the web widget bubble, driven by your dashboard customizations
- **Headless mode** - `ConferBot.shared` is an `ObservableObject` with a full delegate protocol, so you can build a completely custom UI
- **Real-time messaging** - Socket.IO powered, same events as the Conferbot web widget
- **Node flow engine** - Renders the full flow-builder node set (choices, buttons, ratings, dates, file uploads, and more) natively. Text questions (ask-name, ask-email, ...) are answered by typing in the single bottom input bar, and answered choice pills stay in the transcript - exactly like the web widget
- **Live agent handover** - `initiateHandover(message:)` with agent join/leave/typing callbacks
- **Offline support** - Automatic message queuing and replay when connectivity returns
- **Session persistence** - Sessions and messages are restored across app restarts, with configurable expiry
- **Push notifications** - APNs token registration and notification handling
- **Knowledge base** - Built-in `KnowledgeBaseView` plus async APIs for categories, articles, search, ratings, and engagement tracking
- **Analytics** - Session, message, interaction, and goal tracking via `ChatAnalytics`
- **Theming** - Local `ConferBotCustomization` plus automatic server customizations from the dashboard

## Requirements

| Dependency | Version |
|------------|---------|
| iOS        | 14.0+ (SwiftUI/UIKit components; the SPM manifest declares iOS 13 for the core target) |
| Xcode      | 14.0+   |
| Swift      | 5.7 - 5.9 |
| Socket.IO  | socket.io-client-swift 16.x (pulled in automatically) |

## Installation

### Swift Package Manager (Recommended)

In Xcode, go to **File > Add Packages** and enter:

```
https://github.com/conferbot/conferbot-ios
```

Or add the dependency directly in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/conferbot/conferbot-ios", from: "1.0.0")
]
```

The package product is named `Conferbot` and depends on [socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) 16.x, which SPM resolves for you.

### CocoaPods

The podspec (`Conferbot.podspec`, version `1.0.0`) targets iOS 14.0 and depends on `Socket.IO-Client-Swift ~> 16.0`. Add to your `Podfile`:

```ruby
platform :ios, '14.0'
use_frameworks!

target 'YourApp' do
  pod 'Conferbot', '~> 1.0'
end
```

Then run:

```bash
pod install
```

## Getting Your API Key and Bot ID

You need two credentials to use the SDK:

1. **Log in** to [Conferbot Dashboard](https://app.conferbot.com)
2. **Create or select a bot** from the dashboard
3. **Find your Bot ID**: Go to **Bot Settings** > **General** - the Bot ID is displayed at the top
4. **API Key**: any placeholder works (e.g. `conf_test_key`); the bot ID is the credential

Just exploring? The public demo bot `691c970890527a0468f9b2c9` works without an account.

## Quick Start

The SDK is a singleton: `ConferBot.shared` (note the capital B - the module is `Conferbot`, the class is `ConferBot`). Initialize once, as early as possible in your app lifecycle. Initialization connects the socket, loads your bot's dashboard customizations, and silently restores any persisted session.

### Initialize

```swift
import Conferbot

// In AppDelegate.didFinishLaunching or your @main App init
ConferBot.shared.initialize(
    apiKey: "conf_YOUR_API_KEY",   // any non-empty key works - the bot ID is the credential
    botId: "YOUR_BOT_ID"
)
```

### Pattern 1 - Present as Modal (UIKit)

One line opens a full-screen chat modal wrapped in a navigation controller:

```swift
import Conferbot

class ViewController: UIViewController {
    @IBAction func openChat(_ sender: UIButton) {
        ConferBot.shared.present(from: self)
    }
}
```

### Pattern 2 - SwiftUI ChatView

Use the built-in `ChatView` inside a sheet, navigation destination, or any SwiftUI container. It starts the session itself on first appearance, so no extra wiring is needed:

```swift
import SwiftUI
import Conferbot

struct ContentView: View {
    @State private var showChat = false

    var body: some View {
        Button("Contact Support") {
            showChat = true
        }
        .sheet(isPresented: $showChat) {
            ChatView() // ChatView(enableKnowledgeBase: false) to hide the Help tab
        }
    }
}
```

### Pattern 3 - Floating Widget (FAB)

Overlay a floating chat bubble on any SwiftUI view, exactly like the web widget's bottom-right launcher. Tapping the bubble opens `ChatView` in a sheet; tapping again shows a close icon. The bubble reads your dashboard customizations automatically: background color, size, corner radius, left/right position, offsets, launcher icon (all 15 web widget icons), CTA tooltip text, and an unread-count badge.

```swift
import SwiftUI
import Conferbot

struct ContentView: View {
    var body: some View {
        NavigationView {
            MyAppContent()
        }
        .conferBotWidget() // Adds the floating FAB overlay
    }
}
```

You can also use the underlying container view directly:

```swift
ConferBotWidgetOverlay {
    MyAppContent()
}
```

### Pattern 4 - Headless (Custom UI)

Use the SDK as a messaging transport layer and render everything yourself, either through the delegate or by observing the published properties on `ConferBot.shared`:

```swift
import Conferbot

class ChatManager: ConferBotDelegate {
    init() {
        ConferBot.shared.delegate = self
        Task { try? await ConferBot.shared.startSession() }
    }

    func send(_ text: String) {
        Task { try? await ConferBot.shared.sendMessage(text) }
    }

    // Required delegate methods
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) { /* update your UI */ }
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent) {}
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent) {}
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String) {}
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String) {}
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int) {}
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool) {}
}
```

See [Advanced Usage](#advanced-usage) for the flow-engine and Combine sides of headless mode.

## Configuration

### ConferBotConfig

Pass a `ConferBotConfig` during initialization to control SDK behavior. These are the actual options (all have defaults):

```swift
let config = ConferBotConfig(
    enableNotifications: true,                          // default: true
    enableOfflineMode: true,                            // default: true
    apiBaseURL: ConferBotEndpoints.apiBaseURL,          // default: https://wdt.conferbot.com/api/v1/mobile
    socketURL: ConferBotEndpoints.socketURL             // default: https://wdt.conferbot.com
)

ConferBot.shared.initialize(
    apiKey: "conf_YOUR_API_KEY",
    botId: "YOUR_BOT_ID",
    config: config
)
```

Endpoints and network behavior can also be tuned globally (must be done before `initialize`):

```swift
// Point to a self-hosted embed server (HTTPS enforced)
ConferBotEndpoints.configure(
    apiBaseURL: "https://your-server.example.com/api/v1/mobile",
    socketURL: "https://your-server.example.com"
)

// Timeouts and reconnection policy
ConferBotNetworkConfig.configure(
    apiTimeout: 30,
    socketTimeout: 20,
    reconnectionAttempts: 5,
    reconnectionDelay: 1.0,
    reconnectionDelayMax: 5.0
)
```

### Session persistence

Sessions, messages, answers, and the transcript are persisted automatically and restored on the next launch while still valid:

```swift
ConferBot.shared.configureSessionStorage(expiryMinutes: 60 * 24)

if ConferBot.shared.hasValidStoredSession() {
    // startSession() will reuse it instead of creating a new one
}

// Force a brand new conversation
try await ConferBot.shared.startSession(forceNew: true)

// Log out / wipe the stored session
ConferBot.shared.clearStoredSession()
```

## Passing User Identity

Attach user context before starting a session so conversations carry identity and metadata into the dashboard:

```swift
let user = ConferBotUser(
    id: "user-123",
    name: "Jane Smith",
    email: "jane@example.com",
    phone: "+1234567890",
    metadata: [
        "plan": AnyCodable("premium"),
        "signupDate": AnyCodable("2024-01-15")
    ]
)

ConferBot.shared.identify(user: user)
try await ConferBot.shared.startSession()
```

Only `id` is required; `name`, `email`, `phone`, and `metadata` are optional. If you never call `identify`, the SDK generates a persistent anonymous visitor ID that survives app restarts.

## Theming and Flow-Builder Customizations

There are two sources of appearance settings, and they apply to different parts of the UI:

### 1. Server customizations (from the dashboard) - automatic

Whenever the socket connects, the SDK fetches your bot's configuration (the same `customizations` object the web widget uses) and exposes it as `ConferBot.shared.serverCustomizations`. These dashboard settings apply automatically, no client code required:

- **Floating widget (FAB)**: bubble background color (`widgetIconBgColor`, falling back to `headerBgColor`), size, corner radius, left/right position, edge offsets, launcher icon, and the CTA tooltip text (`chatIconCtaText`). The FAB is styled entirely from the server; there are currently no local overrides for it (`ConferBotFABConfig` is an empty placeholder reserved for future options).
- **Branding**: the server `hideBrand` flag takes precedence over the local `ConferBotCustomization.hideBrand` value for the "Powered by Conferbot" footer.
- **Bot identity**: the bot name from the dashboard is injected into the flow state, so flow nodes that reference it render correctly.
- **Flow content**: all flow-builder changes (messages, choices, node styling data) come from the server on every connect.

### 2. Local customization (ConferBotCustomization) - chat surface

The built-in chat UI (header, bubbles, avatar) is styled with a local `ConferBotCustomization` passed at initialization:

```swift
let customization = ConferBotCustomization(
    primaryColor: .systemBlue,          // send button / accents
    fontFamily: "SFProText-Regular",
    bubbleCornerRadius: 16,
    headerTitle: "Support",             // default: "Support Chat"
    showAvatar: true,
    avatarURL: URL(string: "https://example.com/avatar.png"),
    botBubbleColor: .systemGray6,
    userBubbleColor: .systemBlue,
    hideBrand: false
)

ConferBot.shared.initialize(
    apiKey: "conf_YOUR_API_KEY",
    botId: "YOUR_BOT_ID",
    customization: customization
)
```

**Precedence, precisely**: for the FAB and `hideBrand`, server settings win over local ones. For the chat header title, avatar, and bubble colors, only the local `ConferBotCustomization` applies today - the iOS chat surface does not yet remap dashboard theme colors onto bubbles the way the Flutter SDK's theme does. Dark mode follows the system appearance automatically via dynamic system colors.

## Push Notifications

Register for APNs and forward the device token to the SDK:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    ConferBot.shared.registerPushToken(token)
}
```

If no chat session exists yet, the token is held in memory; call `registerPushToken` again after `startSession()` to guarantee server-side registration.

Handle incoming notifications - the SDK claims only its own payloads (those with `type == "conferbot_message"`) and returns `false` for everything else:

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    if ConferBot.shared.handlePushNotification(userInfo) {
        completionHandler(.newData)
    } else {
        completionHandler(.noData)
    }
}
```

## Offline Support

With `enableOfflineMode` (the default), outbound messages sent while the device or socket is offline are queued locally and replayed automatically on reconnect. The room is also rejoined after every socket reconnection.

```swift
// Observe state (also available as @Published for SwiftUI)
ConferBot.shared.isOnline
ConferBot.shared.queuedMessageCount
ConferBot.shared.queuedMessages       // [QueuedMessage]

// Manual control
ConferBot.shared.flushMessageQueue()
ConferBot.shared.retryFailedMessages()
ConferBot.shared.clearMessageQueue()
```

Delegate hooks: `didChangeNetworkStatus` and `didUpdateQueuedMessageCount`.

## Knowledge Base

`ChatView` includes a knowledge base tab by default (`ChatView(enableKnowledgeBase: true)`), and `KnowledgeBaseView()` can be presented standalone. For custom UIs, the async APIs on `ConferBot.shared`:

```swift
let categories = try await ConferBot.shared.fetchKnowledgeBaseCategories()
let articles   = try await ConferBot.shared.fetchKnowledgeBaseArticles()
let results    = try await ConferBot.shared.searchKnowledgeBaseArticles(query: "refunds")
let article    = try await ConferBot.shared.getKnowledgeBaseArticle(id: "ARTICLE_ID")

// Feedback and engagement
ConferBot.shared.trackKnowledgeBaseArticleView(articleId: article.id)
ConferBot.shared.rateKnowledgeBaseArticle(articleId: article.id, helpful: true)
ConferBot.shared.startKnowledgeBaseArticleEngagement(articleId: article.id)
ConferBot.shared.updateKnowledgeBaseScrollDepth(0.8)
ConferBot.shared.sendKnowledgeBaseEngagement()

let related = ConferBot.shared.getRelatedKnowledgeBaseArticles(for: article, limit: 3)
```

## Advanced Usage

### Observing state with Combine / SwiftUI

`ConferBot` is an `ObservableObject`. Published properties include `isConnected`, `currentSession`, `messages`, `unreadCount`, `isAgentTyping`, `isLiveChatMode`, `currentAgent`, `hasRestoredSession`, `serverCustomizations`, `currentUIState`, `isProcessingNode`, `nodeErrorMessage`, `isFlowComplete`, `isOnline`, `queuedMessageCount`, `knowledgeBaseCategories`, and `isLoadingKnowledgeBase`.

```swift
struct MyChatScreen: View {
    @ObservedObject var bot = ConferBot.shared

    var body: some View {
        List(bot.messages, id: \.id) { message in
            Text(message.id) // render from your own bubble views
        }
    }
}
```

### Driving the node flow engine (headless)

When your bot uses the flow builder, bot responses arrive as flow nodes rather than plain text. In headless mode, render `currentUIState` (also delivered via `didUpdateUIState`) and answer through the typed handlers:

```swift
ConferBot.shared.handleNodeInput("Jane", forNodeId: nodeId)
ConferBot.shared.handleButtonClick(buttonId: "btn-1", forNodeId: nodeId)
ConferBot.shared.handleChoiceSelection(optionId: "Pricing", forNodeId: nodeId)
ConferBot.shared.handleMultipleChoiceSelection(optionIds: ["A", "B"], forNodeId: nodeId)
ConferBot.shared.handleRatingSelection(rating: 5, forNodeId: nodeId)
ConferBot.shared.handleDateSelection(date: Date(), forNodeId: nodeId)
ConferBot.shared.handleFileUpload(fileURL: url, forNodeId: nodeId)

ConferBot.shared.getCurrentNodeId()
ConferBot.shared.nodeRequiresInteraction("user-input")   // Bool
ConferBot.shared.resetFlow()                              // restart conversation, new session
```

### Live agent handover

```swift
ConferBot.shared.initiateHandover(message: "I need help with billing")
```

Agent lifecycle arrives via `agentDidJoin` / `agentDidLeave`, `isAgentTyping`, and `currentAgent`. During live chat, `sendTypingIndicator(isTyping:)` forwards visitor typing to the agent console.

### Goals, analytics, and raw socket events

```swift
ConferBot.shared.trackGoal(goalId: "signup", goalName: "Sign Up", value: 49.0)
ConferBot.shared.emitSocketEvent("custom-event", data: ["key": "value"])
ConferBot.shared.analytics // ChatAnalytics.shared - session/message/interaction tracking
```

### Logging

```swift
ConferBotLogger.isEnabled = true
ConferBotLogger.logHandler = { message, level in
    print("[\(level.rawValue)] \(message)")
}
```

### Feature parity notes

Compared with the Flutter SDK, the iOS SDK does not currently ship voice message recording/playback widgets or a message pagination toggle; markdown rendering in bubbles is limited. File uploads, offline queuing, session persistence, knowledge base, analytics, and the full node flow engine are all present.

## API Reference

### ConferBot (singleton: `ConferBot.shared`)

| Method | Description |
|--------|-------------|
| `initialize(apiKey: String, botId: String, config: ConferBotConfig = ConferBotConfig(), customization: ConferBotCustomization? = nil)` | Initialize the SDK, connect the socket, restore any stored session |
| `identify(user: ConferBotUser)` | Set the current user identity |
| `startSession(forceNew: Bool = false) async throws` | Start (or reuse a restored) chat session |
| `sendMessage(_ text: String, metadata: [String: AnyCodable]? = nil) async throws` | Send a text message (auto-queued offline) |
| `sendTypingIndicator(isTyping: Bool)` | Send visitor typing status |
| `initiateHandover(message: String? = nil)` | Request a live agent |
| `endSession(clearStorage: Bool = true)` | End the current session |
| `present(from viewController: UIViewController, animated: Bool = true)` | Present the UIKit chat modal |
| `registerPushToken(_ token: String)` | Register an APNs device token |
| `handlePushNotification(_ userInfo: [AnyHashable: Any]) -> Bool` | Handle an incoming push; returns true if it was a Conferbot message |
| `getUnreadCount() -> Int` / `resetUnreadCount()` | Read / reset the unread counter |
| `clearHistory()` | Clear local chat history |
| `disconnect()` | Disconnect the socket and release clients |
| `hasValidStoredSession() -> Bool` | Whether a restorable session exists |
| `getSessionExpiry() -> Date?` | Expiry of the current stored session |
| `clearStoredSession()` | Delete persisted session data |
| `configureSessionStorage(expiryMinutes: Int)` | Set session expiry window |
| `flushMessageQueue()` / `retryFailedMessages()` / `clearMessageQueue()` | Offline queue controls |
| `loadFlow(_ flowData: [String: Any])` / `startFlow()` / `resetFlow()` | Flow engine lifecycle |
| `handleNodeInput(_ input: Any, forNodeId: String)` | Answer the current input node |
| `handleButtonClick(buttonId: String, forNodeId: String)` | Answer a button node |
| `handleChoiceSelection(optionId: String, forNodeId: String)` | Answer a choice node |
| `handleMultipleChoiceSelection(optionIds: [String], forNodeId: String)` | Answer a multi-choice node |
| `handleRatingSelection(rating: Int, forNodeId: String)` | Answer a rating node |
| `handleDateSelection(date: Date, forNodeId: String)` | Answer a date node |
| `handleFileUpload(fileURL: URL, forNodeId: String)` | Complete a file-upload node |
| `getCurrentNodeId() -> String?` | Current flow node ID |
| `nodeRequiresInteraction(_ nodeType: String) -> Bool` | Whether a node type waits for user input |
| `trackGoal(goalId: String, goalName: String? = nil, value: Any? = nil)` | Track a conversion goal |
| `emitSocketEvent(_ event: String, data: [String: Any])` | Emit a raw socket event |
| `fetchKnowledgeBaseCategories() async throws -> [KnowledgeBaseCategory]` | KB categories |
| `fetchKnowledgeBaseArticles() async throws -> [KnowledgeBaseArticle]` | All KB articles |
| `searchKnowledgeBaseArticles(query: String) async throws -> [KnowledgeBaseArticle]` | Search KB |
| `getKnowledgeBaseArticle(id: String) async throws -> KnowledgeBaseArticle` | One article |
| `trackKnowledgeBaseArticleView(articleId: String)` | Track an article view |
| `rateKnowledgeBaseArticle(articleId: String, helpful: Bool, completion: ((Bool) -> Void)? = nil)` | Rate an article |
| `startKnowledgeBaseArticleEngagement(articleId: String)` / `updateKnowledgeBaseScrollDepth(_ scrollDepth: Double)` / `sendKnowledgeBaseEngagement()` | Engagement tracking |
| `getRelatedKnowledgeBaseArticles(for article: KnowledgeBaseArticle, limit: Int = 3) -> [KnowledgeBaseArticle]` | Related articles |

### UI Components

| Type | Description |
|------|-------------|
| `ChatView(enableKnowledgeBase: Bool = true)` | Drop-in SwiftUI chat screen with optional KB tab |
| `ChatViewWithKBSheet()` | Chat screen with the KB in a sheet instead of a tab |
| `KnowledgeBaseView()` | Standalone SwiftUI knowledge base browser |
| `MessageBubble(message: any RecordItem, customization: ConferBotCustomization?)` | Individual message bubble for custom layouts |
| `View.conferBotWidget(config: ConferBotFABConfig = ConferBotFABConfig())` | Floating FAB overlay modifier |
| `ConferBotWidgetOverlay(config:content:)` | The FAB overlay as a container view |
| `ChatViewController` | UIKit chat screen (used by `present(from:)`) |

### ConferBotDelegate

```swift
public protocol ConferBotDelegate: AnyObject {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem)
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent)
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent)
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool)
    // The following have default (empty) implementations:
    func conferBot(_ conferBot: ConferBot, didUpdateUIState state: NodeUIState?)
    func conferBot(_ conferBot: ConferBot, didCompleteFlow success: Bool)
    func conferBot(_ conferBot: ConferBot, didReachGoal goalName: String, value: Any?)
    func conferBot(_ conferBot: ConferBot, didUpdateQueuedMessageCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeNetworkStatus isOnline: Bool)
}
```

For the full reference, see [docs/API.md](docs/API.md) and [docs/USAGE.md](docs/USAGE.md).

## Documentation

- [Usage Tutorial](docs/USAGE.md)
- [Architecture Guide](docs/ARCHITECTURE.md)
- [UI Components](docs/COMPONENTS.md)
- [API Reference](docs/API.md)
- [Examples](docs/EXAMPLES.md)
- [Testing](docs/TESTING.md)
- [Publishing Guide](docs/PUBLISHING.md)
- [Full Documentation](https://docs.conferbot.com/mobile/ios)

## Example App

The [`Example/`](Example/) directory contains a SwiftUI sample project demonstrating the modal, embedded, and FAB patterns.

### Running the Example

```bash
# 1. Clone the repo
git clone https://github.com/conferbot/conferbot-ios.git
cd conferbot-ios

# 2. Open the example package in Xcode (it resolves the SDK dependency automatically)
open Example/SwiftUI/Package.swift

# 3. (Optional) Configure your bot credentials
#    The example is pre-configured with the public demo bot
#    (apiKey "conf_test_key_12345", botId "691c970890527a0468f9b2c9"),
#    so it works out of the box. To use your own bot, open
#    Example/SwiftUI/Sources/ExampleApp.swift and swap in your
#    credentials from the Conferbot dashboard.

# 4. Select a simulator or device and press Cmd+R to run
```

### What the Example Shows

| View | Pattern | Description |
|------|---------|-------------|
| **Widget (FAB)** | Overlay (default) | `.conferBotWidget()` floating bubble over demo app content, like the web widget embed |
| **Modal** | Sheet presentation | Full chat opens as a sheet - one line of code |
| **Embedded** | Inline SwiftUI | `ChatView` embedded directly in your view hierarchy |

### Demo video

A recorded demo requires building the example app on macOS (Xcode + iOS Simulator); unlike the other Conferbot SDK repos, an emulator recording cannot be produced on a Linux host. Build and run the example on a Mac to capture one.

## Troubleshooting

**Bot not appearing / no responses**

- Make sure the bot is **published** in the dashboard - draft bots do not serve traffic.
- Double-check the `botId` (Bot Settings > General) - it is the operative credential; any non-empty API key is accepted.
- Verify `https://wdt.conferbot.com` is reachable from the device (corporate networks and VPNs sometimes block websockets).
- Try the public demo bot ID `691c970890527a0468f9b2c9`, which works without an account. If the demo bot works, the issue is with your bot's configuration or credentials.

**Build errors with Socket.IO**

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
pod deintegrate && pod install
```

**Socket not connecting**

- Verify your bot ID is correct - it is the operative credential (`initialize` traps only on an empty key or bot ID; any non-empty API key is accepted).
- Check the device network connection and observe `ConferBot.shared.isOnline`.
- Hook `ConferBotLogger.logHandler` to capture SDK logs.

**Messages not appearing**

- Ensure `startSession()` has been called (the built-in `ChatView` does this for you).
- Confirm your delegate is set, or that your SwiftUI view observes `ConferBot.shared`.
- Check connection status via the `didChangeConnectionStatus` delegate callback or `isConnected`.

**FAB not styled like my web widget**

- FAB styling arrives with the `fetched-chatbot-data` socket event after connect; until then it renders with defaults (blue, bottom-right). If it never updates, the socket is not connecting.

## Contributing

Bug reports and pull requests are welcome on GitHub at [conferbot/conferbot-ios](https://github.com/conferbot/conferbot-ios). Please open an issue before starting any significant work so we can discuss the approach.

## License

Apache 2.0 - see [LICENSE](LICENSE) for details.

## Support

- GitHub Issues: [https://github.com/conferbot/conferbot-ios/issues](https://github.com/conferbot/conferbot-ios/issues)
- Email: support@conferbot.com
- Documentation: [https://docs.conferbot.com](https://docs.conferbot.com)
