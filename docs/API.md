# API Reference

Complete API documentation for the Conferbot iOS SDK.

## Core Classes

### ConferBot

Main SDK singleton class.

#### Properties

```swift
// Observable properties (SwiftUI)
@Published public private(set) var isConnected: Bool
@Published public private(set) var currentSession: ChatSession?
@Published public private(set) var messages: [any RecordItem]
@Published public private(set) var unreadCount: Int
@Published public private(set) var isAgentTyping: Bool

// Configuration
public var customization: ConferBotCustomization?
public weak var delegate: ConferBotDelegate?
```

#### Methods

##### initialize(apiKey:botId:config:customization:)

Initialize the SDK. Must be called before any other methods.

```swift
public func initialize(
    apiKey: String,
    botId: String,
    config: ConferBotConfig = ConferBotConfig(),
    customization: ConferBotCustomization? = nil
)
```

**Parameters:**
- `apiKey`: Your Conferbot API key (get from dashboard)
- `botId`: Your bot identifier
- `config`: Optional configuration options
- `customization`: Optional UI customization

**Example:**
```swift
Conferbot.shared.initialize(
    apiKey: "conf_sk_...",
    botId: "bot_123"
)
```

##### identify(user:)

Identify the current user for personalized support.

```swift
public func identify(user: ConferBotUser)
```

**Parameters:**
- `user`: User identification object

**Example:**
```swift
let user = ConferBotUser(
    id: "user-123",
    name: "John Doe",
    email: "john@example.com"
)
Conferbot.shared.identify(user: user)
```

##### startSession()

Start a new chat session. Async function.

```swift
public func startSession() async throws
```

**Throws:** `ConferBotError`

**Example:**
```swift
Task {
    try await Conferbot.shared.startSession()
}
```

##### sendMessage(_:metadata:)

Send a text message. Async function.

```swift
public func sendMessage(
    _ text: String,
    metadata: [String: AnyCodable]? = nil
) async throws
```

**Parameters:**
- `text`: Message text (max 5000 characters)
- `metadata`: Optional custom metadata

**Throws:** `ConferBotError`

**Example:**
```swift
Task {
    try await Conferbot.shared.sendMessage("Hello!")
}

// With metadata
try await Conferbot.shared.sendMessage(
    "I need help with order #123",
    metadata: [
        "orderId": AnyCodable("123"),
        "amount": AnyCodable(99.99)
    ]
)
```

##### sendTypingIndicator(isTyping:)

Send typing status to agent.

```swift
public func sendTypingIndicator(isTyping: Bool)
```

**Parameters:**
- `isTyping`: true when user starts typing, false when stops

**Example:**
```swift
// User started typing
Conferbot.shared.sendTypingIndicator(isTyping: true)

// User stopped typing
Conferbot.shared.sendTypingIndicator(isTyping: false)
```

##### initiateHandover(message:)

Request to speak with a live agent.

```swift
public func initiateHandover(message: String? = nil)
```

**Parameters:**
- `message`: Optional message to agent

**Example:**
```swift
Conferbot.shared.initiateHandover(message: "I need human help")
```

##### endSession()

End the current chat session.

```swift
public func endSession()
```

**Example:**
```swift
Conferbot.shared.endSession()
```

##### present(from:animated:)

Present chat view controller modally (UIKit only).

```swift
public func present(
    from viewController: UIViewController,
    animated: Bool = true
)
```

**Parameters:**
- `viewController`: Presenting view controller
- `animated`: Animation flag

**Example:**
```swift
Conferbot.shared.present(from: self)
```

##### registerPushToken(_:)

Register APNs device token for push notifications.

```swift
public func registerPushToken(_ token: String)
```

**Parameters:**
- `token`: APNs device token (hex string)

**Example:**
```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    Conferbot.shared.registerPushToken(token)
}
```

##### handlePushNotification(_:)

Handle incoming push notification.

```swift
public func handlePushNotification(_ userInfo: [AnyHashable: Any]) -> Bool
```

**Parameters:**
- `userInfo`: Notification payload

**Returns:** `true` if notification was handled, `false` otherwise

**Example:**
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

##### getUnreadCount()

Get current unread message count.

```swift
public func getUnreadCount() -> Int
```

**Returns:** Number of unread messages

**Example:**
```swift
let count = Conferbot.shared.getUnreadCount()
badgeLabel.text = "\(count)"
```

##### clearHistory()

Clear local chat history.

```swift
public func clearHistory()
```

**Example:**
```swift
Conferbot.shared.clearHistory()
```

##### disconnect()

Manually disconnect socket connection.

```swift
public func disconnect()
```

**Example:**
```swift
Conferbot.shared.disconnect()
```

## Protocols

### ConferBotDelegate

Event callback protocol for UIKit apps.

```swift
public protocol ConferBotDelegate: AnyObject {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem)
    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent)
    func conferBot(_ conferBot: ConferBot, agentDidLeave agent: Agent)
    func conferBot(_ conferBot: ConferBot, didStartSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didEndSession sessionId: String)
    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int)
    func conferBot(_ conferBot: ConferBot, didChangeConnectionStatus isConnected: Bool)
}
```

**Example:**
```swift
class ChatManager: ConferBotDelegate {
    init() {
        Conferbot.shared.delegate = self
    }

    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        print("New message: \(message.id)")
    }

    func conferBot(_ conferBot: ConferBot, agentDidJoin agent: Agent) {
        showAlert("Agent \(agent.name) joined")
    }

    func conferBot(_ conferBot: ConferBot, didUpdateUnreadCount count: Int) {
        updateBadge(count)
    }
}
```

## Models

### ConferBotUser

User identification model.

```swift
public struct ConferBotUser: Codable {
    public let id: String
    public let name: String?
    public let email: String?
    public let phone: String?
    public let metadata: [String: AnyCodable]?
}
```

**Example:**
```swift
let user = ConferBotUser(
    id: "user-123",
    name: "John Doe",
    email: "john@example.com",
    phone: "+1234567890",
    metadata: [
        "tier": AnyCodable("premium"),
        "signupDate": AnyCodable("2024-01-15"),
        "preferences": AnyCodable(["darkMode": true])
    ]
)
```

### ConferBotConfig

SDK configuration options.

```swift
public struct ConferBotConfig {
    public let enableNotifications: Bool
    public let enableOfflineMode: Bool
    public let apiBaseURL: String
    public let socketURL: String

    public init(
        enableNotifications: Bool = true,
        enableOfflineMode: Bool = true,
        apiBaseURL: String = ConferBotConstants.defaultApiBaseURL,
        socketURL: String = ConferBotConstants.defaultSocketURL
    )
}
```

**Example:**
```swift
let config = ConferBotConfig(
    enableNotifications: true,
    enableOfflineMode: true
)
```

### ConferBotCustomization

UI customization options.

```swift
public struct ConferBotCustomization {
    public let primaryColor: UIColor?
    public let fontFamily: String?
    public let bubbleCornerRadius: CGFloat?
    public let headerTitle: String?
    public let showAvatar: Bool
    public let avatarURL: URL?
    public let botBubbleColor: UIColor?
    public let userBubbleColor: UIColor?
}
```

**Example:**
```swift
let customization = ConferBotCustomization(
    primaryColor: .systemRed,
    fontFamily: "SFProText-Regular",
    bubbleCornerRadius: 16,
    headerTitle: "24/7 Support",
    showAvatar: true,
    avatarURL: URL(string: "https://example.com/avatar.png"),
    botBubbleColor: .systemBlue,
    userBubbleColor: .systemGray5
)
```

### ChatSession

Chat session model.

```swift
public struct ChatSession: Codable, Identifiable {
    public let id: String
    public let chatSessionId: String
    public let botId: String
    public let visitorId: String?
    public let record: [AnyRecordItem]
    public let chatDate: Date?
    public let visitorMeta: [String: AnyCodable]?
    public let isActive: Bool
}
```

### Agent

Agent model.

```swift
public struct Agent: Codable, Identifiable {
    public let id: String
    public let name: String
    public let email: String?
    public let avatar: String?
    public let title: String?
    public let status: String?
}
```

### MessageType

Enumeration of message types.

```swift
public enum MessageType: String, Codable {
    case userMessage = "user-message"
    case botMessage = "bot-message"
    case agentMessage = "agent-message"
    case agentMessageFile = "agent-message-file"
    case agentMessageAudio = "agent-message-audio"
    case agentJoinedMessage = "agent-joined-message"
    case visitorDisconnectedMessage = "visitor-disconnected-message"
    case visitorReconnectedMessage = "visitor-reconnected-message"
    case systemMessage = "system-message"
}
```

### RecordItem Protocol

Base protocol for all message types.

```swift
public protocol RecordItem: Codable {
    var id: String { get }
    var type: MessageType { get }
    var time: Date { get }
}
```

**Concrete Types:**
- `UserMessageRecord`
- `BotMessageRecord`
- `AgentMessageRecord`
- `AgentMessageFileRecord`
- `AgentMessageAudioRecord`
- `AgentJoinedMessageRecord`
- `SystemMessageRecord`

### UserMessageRecord

```swift
public struct UserMessageRecord: RecordItem {
    public let id: String
    public let type: MessageType  // .userMessage
    public let time: Date
    public let text: String
    public let metadata: [String: AnyCodable]?
}
```

### BotMessageRecord

```swift
public struct BotMessageRecord: RecordItem {
    public let id: String
    public let type: MessageType  // .botMessage
    public let time: Date
    public let text: String?
    public let nodeData: [String: AnyCodable]?
}
```

### AgentMessageRecord

```swift
public struct AgentMessageRecord: RecordItem {
    public let id: String
    public let type: MessageType  // .agentMessage
    public let time: Date
    public let text: String
    public let agentDetails: AgentDetails
}
```

## Errors

### ConferBotError

```swift
public enum ConferBotError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noData
    case notInitialized
    case socketNotConnected

    public var errorDescription: String? { ... }
}
```

**Example:**
```swift
Task {
    do {
        try await Conferbot.shared.sendMessage("Hello")
    } catch ConferBotError.notInitialized {
        print("SDK not initialized")
    } catch ConferBotError.socketNotConnected {
        print("No internet connection")
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}
```

## Constants

### ConferBotConstants

```swift
public struct ConferBotConstants {
    public static let defaultApiBaseURL: String
    public static let defaultSocketURL: String
    public static let apiTimeout: TimeInterval
    public static let socketTimeout: TimeInterval
    public static let maxMessageLength: Int
    public static let maxFileSize: Int
}
```

## SwiftUI Views

### ChatView

```swift
@available(iOS 14.0, *)
public struct ChatView: View {
    public init()
}
```

**Example:**
```swift
struct ContentView: View {
    var body: some View {
        ChatView()
    }
}
```

### MessageBubble

```swift
@available(iOS 14.0, *)
public struct MessageBubble: View {
    public init(message: any RecordItem, customization: ConferBotCustomization?)
}
```

### ChatInput

```swift
@available(iOS 14.0, *)
public struct ChatInput: View {
    public init(
        text: Binding<String>,
        onSend: @escaping (String) -> Void,
        onEditingChanged: @escaping (Bool) -> Void
    )
}
```

### TypingIndicator

```swift
@available(iOS 14.0, *)
public struct TypingIndicator: View {
    public init()
}
```

## UIKit Components

### ChatViewController

```swift
public class ChatViewController: UIViewController
```

### MessageCell

```swift
public class MessageCell: UITableViewCell {
    public func configure(with message: any RecordItem, customization: ConferBotCustomization?)
}
```

### ChatInputView

```swift
public class ChatInputView: UIView {
    public weak var delegate: ChatInputViewDelegate?
}
```

### ChatInputViewDelegate

```swift
public protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String)
    func chatInputViewDidBeginEditing(_ inputView: ChatInputView)
    func chatInputViewDidEndEditing(_ inputView: ChatInputView)
}
```

## Type Aliases

```swift
// None currently, but reserved for future use
```

## Deprecations

```swift
// None in v1.0.0
```

## Version History

- **1.0.0** - Initial release
  - Core messaging functionality
  - UIKit and SwiftUI support
  - Real-time socket communication
  - Push notifications
  - Full customization
