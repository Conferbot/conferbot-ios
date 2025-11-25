# Conferbot iOS SDK

Native iOS SDK for integrating Conferbot AI-powered customer support chat into your iOS applications.

[![Platform](https://img.shields.io/badge/platform-iOS-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-13.0+-green.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

## Features

- **Real-time Chat**: Socket.IO powered instant messaging
- **Live Agent Handover**: Seamless transition from bot to human agent
- **Native UI**: Both UIKit and SwiftUI support with native design patterns
- **Push Notifications**: APNs integration for agent responses
- **Offline Support**: Messages queued when offline, sent when back online
- **File Uploads**: Support for images and documents
- **Typing Indicators**: See when agent is typing
- **Full Customization**: Colors, fonts, avatars, and more
- **Dark Mode**: Automatic light/dark theme adaptation

## Requirements

- iOS 13.0+
- Xcode 14.0+
- Swift 5.7+
- CocoaPods or Swift Package Manager

## Installation

### Swift Package Manager (Recommended)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/conferbot/conferbot-ios", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Packages
2. Enter: `https://github.com/conferbot/conferbot-ios`
3. Select version: `1.0.0`

### CocoaPods

Add to your `Podfile`:

```ruby
platform :ios, '13.0'
use_frameworks!

target 'YourApp' do
  pod 'Conferbot', '~> 1.0'
end
```

Then run:
```bash
pod install
```

## Quick Start

### UIKit

**1. Initialize in AppDelegate:**

```swift
import UIKit
import Conferbot

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Conferbot.shared.initialize(
            apiKey: "conf_sk_your_api_key_here",
            botId: "your_bot_id_here"
        )
        return true
    }
}
```

**2. Open Chat:**

```swift
import Conferbot

class ViewController: UIViewController {
    @IBAction func openChatTapped(_ sender: UIButton) {
        Conferbot.shared.present(from: self)
    }
}
```

### SwiftUI

**1. Initialize in App:**

```swift
import SwiftUI
import Conferbot

@main
struct YourApp: App {
    init() {
        Conferbot.shared.initialize(
            apiKey: "conf_sk_your_api_key_here",
            botId: "your_bot_id_here"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**2. Show Chat:**

```swift
import SwiftUI
import Conferbot

struct ContentView: View {
    @State private var showChat = false

    var body: some View {
        Button("Support Chat") {
            showChat = true
        }
        .sheet(isPresented: $showChat) {
            ChatView()
        }
    }
}
```

## Advanced Usage

### User Identification

```swift
let user = ConferBotUser(
    id: "user-123",
    name: "John Doe",
    email: "john@example.com",
    phone: "+1234567890",
    metadata: [
        "plan": AnyCodable("premium"),
        "signupDate": AnyCodable("2024-01-15")
    ]
)

Conferbot.shared.identify(user: user)
```

### Customization

```swift
let customization = ConferBotCustomization(
    primaryColor: UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0),
    fontFamily: "SFProText-Regular",
    bubbleCornerRadius: 16,
    headerTitle: "Customer Support",
    showAvatar: true,
    avatarURL: URL(string: "https://your-domain.com/avatar.png"),
    botBubbleColor: UIColor(red: 0.0, green: 0.0, blue: 0.93, alpha: 1.0),
    userBubbleColor: UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)
)

Conferbot.shared.initialize(
    apiKey: "conf_sk_...",
    botId: "bot_...",
    customization: customization
)
```

### Event Handling (UIKit)

```swift
class ChatCoordinator: ConferBotDelegate {
    init() {
        Conferbot.shared.delegate = self
    }

    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        print("New message received")
    }

    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent) {
        print("Agent joined: \(agent.name)")
    }

    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int) {
        // Update badge
    }
}
```

### Programmatic Messaging

```swift
// Send a message
Task {
    try? await Conferbot.shared.sendMessage("Hello, I need help!")
}

// Initiate handover to agent
Conferbot.shared.initiateHandover(message: "I need to speak with a human")

// End session
Conferbot.shared.endSession()
```

### Push Notifications

**1. Register for Notifications:**

```swift
import UserNotifications

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge]
    ) { granted, error in
        if granted {
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }
    return true
}

func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    Conferbot.shared.registerPushToken(token)
}
```

**2. Handle Notifications:**

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

## Usage Patterns

### 1. Drop-in Widget (Modal)

```swift
// UIKit
Conferbot.shared.present(from: self)

// SwiftUI
.sheet(isPresented: $showChat) {
    ChatView()
}
```

### 2. Embedded in View (UIKit)

```swift
class SupportViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let chatVC = ChatViewController()
        addChild(chatVC)
        view.addSubview(chatVC.view)
        chatVC.view.frame = view.bounds
        chatVC.didMove(toParent: self)
    }
}
```

### 3. Headless (API Only)

```swift
class CustomChatManager: ConferBotDelegate {
    func setupHeadless() {
        Conferbot.shared.delegate = self

        Task {
            try? await Conferbot.shared.startSession()
        }
    }

    func sendCustomMessage(_ text: String) {
        Task {
            try? await Conferbot.shared.sendMessage(text)
        }
    }

    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        // Handle message in your custom UI
    }
}
```

## API Reference

### `ConferBot` Class

| Method | Description |
|--------|-------------|
| `initialize(apiKey:botId:config:customization:)` | Initialize the SDK |
| `identify(user:)` | Identify current user |
| `startSession()` | Start a new chat session |
| `sendMessage(_:metadata:)` | Send a message |
| `sendTypingIndicator(isTyping:)` | Send typing status |
| `initiateHandover(message:)` | Request live agent |
| `endSession()` | End current session |
| `present(from:animated:)` | Show chat modal (UIKit) |
| `registerPushToken(_:)` | Register APNs token |
| `getUnreadCount()` | Get unread message count |
| `clearHistory()` | Clear chat history |
| `disconnect()` | Disconnect socket |

### `ConferBotDelegate` Protocol

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

## Documentation

- [Architecture Guide](docs/ARCHITECTURE.md)
- [UI Components](docs/COMPONENTS.md)
- [API Reference](docs/API.md)
- [Examples](docs/EXAMPLES.md)
- [Publishing Guide](docs/PUBLISHING.md)

## Example App

Check out the `Example/` directory for complete UIKit and SwiftUI implementations.

## Troubleshooting

**Issue: Build errors with Socket.IO**
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Update dependencies
pod deintegrate && pod install
```

**Issue: Socket not connecting**
- Verify API key and Bot ID are correct
- Check network connection
- Enable logging: `print` statements are enabled in DEBUG mode

**Issue: Messages not appearing**
- Ensure `startSession()` is called
- Check delegate/publisher subscriptions
- Verify socket connection status

## Support

- **Documentation**: https://docs.conferbot.com/mobile/ios
- **GitHub Issues**: https://github.com/conferbot/conferbot-ios/issues
- **Discord**: https://discord.gg/conferbot
- **Email**: mobile-support@conferbot.com

## License

Proprietary - Copyright 2025 Conferbot. All rights reserved.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
