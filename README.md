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

## Features

- Real-time chat powered by Socket.IO
- Live agent handover with typing indicators
- Native UIKit and SwiftUI components
- Headless mode for fully custom UIs
- Push notifications via APNs
- Offline message queuing
- File and image uploads
- Knowledge base integration
- Session analytics and event tracking
- Full theming support with automatic dark mode

## Requirements

| Dependency | Version |
|------------|---------|
| iOS        | 14.0+   |
| Xcode      | 14.0+   |
| Swift      | 5.7+    |

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

### CocoaPods

Add to your `Podfile`:

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
3. **Find your Bot ID**: Go to **Bot Settings** > **General** -- the Bot ID is displayed at the top
4. **Find your API Key**: Go to **Workspace Settings** > **API Keys** -- copy the key starting with `conf_`

## Quick Start

Initialize the SDK early in your app lifecycle, then present chat using whichever pattern fits your project.

### Initialize

```swift
import Conferbot

// In AppDelegate or @main App init
Conferbot.shared.initialize(
    apiKey: "YOUR_API_KEY",
    botId: "YOUR_BOT_ID"
)
```

### Pattern 1 -- Present as Modal (UIKit)

The simplest integration. One line opens a full-screen chat modal:

```swift
import Conferbot

class ViewController: UIViewController {
    @IBAction func openChat(_ sender: UIButton) {
        Conferbot.shared.present(from: self)
    }
}
```

### Pattern 2 -- SwiftUI ChatView

Use the built-in `ChatView` inside a sheet, navigation destination, or any SwiftUI container:

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
            ChatView()
        }
    }
}
```

### Pattern 3 -- Floating Widget (FAB)

Overlay a floating chat button on any SwiftUI view. Tapping opens chat in a sheet. Reads server customizations automatically (color, icon, CTA text, position).

```swift
import SwiftUI
import Conferbot

struct ContentView: View {
    var body: some View {
        NavigationView {
            MyAppContent()
        }
        .conferBotWidget() // Adds floating FAB overlay
    }
}
```

### Pattern 4 -- Headless (Custom UI)

Use the SDK as a messaging transport layer and render everything yourself:

```swift
import Conferbot

class ChatManager: ConferBotDelegate {
    init() {
        Conferbot.shared.delegate = self
        Task { try? await Conferbot.shared.startSession() }
    }

    func send(_ text: String) {
        Task { try? await Conferbot.shared.sendMessage(text) }
    }

    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        // Route message to your custom UI
    }
}
```

## Configuration

### ConferBotConfig

Pass a `ConferBotConfig` during initialization to control SDK behavior:

```swift
let config = ConferBotConfig(
    enablePushNotifications: true,
    enableOfflineQueue: true,
    enableAnalytics: true,
    logLevel: .warning
)

Conferbot.shared.initialize(
    apiKey: "YOUR_API_KEY",
    botId: "YOUR_BOT_ID",
    config: config
)
```

### ConferBotCustomization

Customize the appearance of the built-in chat UI:

```swift
let customization = ConferBotCustomization(
    primaryColor: .systemBlue,
    fontFamily: "SFProText-Regular",
    bubbleCornerRadius: 16,
    headerTitle: "Support",
    showAvatar: true,
    avatarURL: URL(string: "https://example.com/avatar.png"),
    botBubbleColor: .systemGray6,
    userBubbleColor: .systemBlue
)

Conferbot.shared.initialize(
    apiKey: "YOUR_API_KEY",
    botId: "YOUR_BOT_ID",
    customization: customization
)
```

Dark mode is handled automatically. The SDK respects the system appearance by default.

### User Identification

Attach user context so conversations carry identity and metadata:

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

Conferbot.shared.identify(user: user)
```

## Push Notifications

Register for APNs and forward the device token to the SDK:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    Conferbot.shared.registerPushToken(token)
}
```

Handle incoming notifications:

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    if Conferbot.shared.handlePushNotification(userInfo) {
        completionHandler(.newData)
    } else {
        completionHandler(.noData)
    }
}
```

## Offline Support

When the device loses connectivity, outbound messages are queued locally and delivered automatically once the connection is restored. No additional setup is required beyond keeping `enableOfflineQueue` set to `true` (the default).

## Knowledge Base

If your bot is configured with a knowledge base on the Conferbot dashboard, the SDK surfaces those answers automatically during conversation. No client-side setup is needed.

## Analytics

When `enableAnalytics` is set to `true` in `ConferBotConfig`, the SDK reports session and message events to the Conferbot analytics dashboard. You can also listen for events locally via the `ConferBotDelegate` protocol.

## API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `initialize(apiKey:botId:config:customization:)` | Initialize the SDK |
| `identify(user:)` | Set the current user |
| `startSession()` | Start a chat session |
| `sendMessage(_:metadata:)` | Send a text message |
| `sendTypingIndicator(isTyping:)` | Send typing status |
| `initiateHandover(message:)` | Request a live agent |
| `endSession()` | End the current session |
| `present(from:animated:)` | Show the chat modal (UIKit) |
| `registerPushToken(_:)` | Register an APNs device token |
| `getUnreadCount()` | Get unread message count |
| `clearHistory()` | Clear local chat history |
| `disconnect()` | Disconnect the socket |

### ConferBotDelegate

```swift
protocol ConferBotDelegate: AnyObject {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem)
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent)
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent)
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool)
}
```

For the full API reference, see [docs/API.md](docs/API.md).

## Documentation

- [Architecture Guide](docs/ARCHITECTURE.md)
- [UI Components](docs/COMPONENTS.md)
- [API Reference](docs/API.md)
- [Examples](docs/EXAMPLES.md)
- [Testing](docs/TESTING.md)
- [Publishing Guide](docs/PUBLISHING.md)
- [Full Documentation](https://docs.conferbot.com/mobile/ios)

## Example App

The [`Example/`](Example/) directory contains a SwiftUI sample project demonstrating all integration patterns.

### Running the Example

```bash
# 1. Clone the repo
git clone https://github.com/conferbot/conferbot-ios.git
cd conferbot-ios

# 2. Open the example project in Xcode
open Example/SwiftUI/Package.swift

# 3. Configure your bot credentials
#    Open ExampleApp.swift and replace:
#      apiKey: "YOUR_API_KEY"
#      botId: "YOUR_BOT_ID"
#    with your own credentials from the Conferbot dashboard.

# 4. Select a simulator or device and press Cmd+R to run
```

### What the Example Shows

| View | Pattern | Description |
|------|---------|-------------|
| **Modal** | Sheet presentation | Full chat opens as a sheet -- one line of code |
| **Embedded** | Inline SwiftUI | `ChatView` embedded directly in your view hierarchy |
| **Headless** | ObservableObject | Full control via `ConferBot.shared` state observation |

## Troubleshooting

**Build errors with Socket.IO**

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
pod deintegrate && pod install
```

**Socket not connecting**

- Verify your API key and bot ID are correct.
- Check the device network connection.
- Enable debug logging via `ConferBotConfig(logLevel: .debug)`.

**Messages not appearing**

- Ensure `startSession()` has been called.
- Confirm your delegate is set or your SwiftUI view is subscribed.
- Check the socket connection status via `didChangeConnectionStatus`.

## Contributing

Bug reports and pull requests are welcome on GitHub at [conferbot/conferbot-ios](https://github.com/conferbot/conferbot-ios). Please open an issue before starting any significant work so we can discuss the approach.

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
