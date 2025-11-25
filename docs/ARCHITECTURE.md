# Conferbot iOS SDK Architecture

This document explains the architecture and design patterns used in the Conferbot iOS SDK.

## Overview

The Conferbot iOS SDK follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────┐
│          UI Layer (UIKit/SwiftUI)       │
│  ChatViewController, ChatView, etc.     │
├─────────────────────────────────────────┤
│          Core Layer                     │
│  ConferBot (Singleton + ObservableObject)│
├─────────────────────────────────────────┤
│          Services Layer                 │
│  APIClient, SocketClient                │
├─────────────────────────────────────────┤
│          Models Layer                   │
│  Agent, Message, ChatSession, etc.      │
└─────────────────────────────────────────┘
```

## Core Components

### 1. Models Layer

**Location**: `Sources/Conferbot/Models/`

All data models follow the Codable protocol and match the embed-server schema exactly.

#### Agent.swift
```swift
- Agent: Live agent representation
- AgentDetails: Detailed agent information from messages
```

#### Message.swift
```swift
- MessageType: Enum of all message types
- RecordItem: Protocol for all message records
- UserMessageRecord: User-sent messages
- BotMessageRecord: Bot responses
- AgentMessageRecord: Agent messages
- AgentMessageFileRecord: File attachments
- AgentMessageAudioRecord: Audio messages
- AgentJoinedMessageRecord: Agent join events
- SystemMessageRecord: System notifications
- AnyRecordItem: Type-erased wrapper for heterogeneous arrays
- AnyCodable: Wrapper for dynamic JSON values
```

#### ChatSession.swift
```swift
- ChatSession: Complete chat session state
  - id: MongoDB ObjectID
  - chatSessionId: UUID for socket communication
  - botId: Bot identifier
  - visitorId: Optional visitor identifier
  - record: Array of RecordItem messages
  - chatDate: Session start time
  - visitorMeta: Custom metadata
  - isActive: Session status
```

#### Configuration.swift
```swift
- ConferBotUser: User identification
- ConferBotConfig: SDK configuration
- ConferBotCustomization: UI customization options
```

#### SocketEvents.swift
```swift
- SocketEvents: String constants matching embed-server socket.js
  - Client → Server events
  - Server → Client events
  - Connection events
```

### 2. Services Layer

**Location**: `Sources/Conferbot/Services/`

#### APIClient.swift

Handles REST API communication using URLSession and async/await.

```swift
class APIClient {
    // REST endpoints
    func initSession(userId: String?) async throws -> ChatSession
    func getSessionHistory(chatSessionId: String) async throws -> [AnyRecordItem]
    func sendMessage(chatSessionId: String, message: String, metadata: [String: AnyCodable]?) async throws
    func registerPushToken(token: String, chatSessionId: String) async throws
}
```

**Key Features**:
- Native URLSession (no third-party dependencies)
- Async/await for modern Swift concurrency
- Automatic JSON encoding/decoding
- ISO8601 date handling
- Custom headers (X-API-Key, X-Bot-ID, X-Platform)
- 30-second timeout
- Proper error handling with ConferBotError enum

#### SocketClient.swift

Manages real-time Socket.IO connection.

```swift
class SocketClient {
    // Socket operations
    func connect()
    func disconnect()
    func mobileInit(chatSessionId: String, visitorId: String?, deviceInfo: [String: Any]?)
    func joinChatRoom(chatSessionId: String)
    func leaveChatRoom(chatSessionId: String)
    func sendVisitorMessage(chatSessionId: String, record: [String: Any], answerVariables: [[String: Any]], visitorMeta: [String: Any]?)
    func sendTypingStatus(chatSessionId: String, isTyping: Bool)
    func initiateHandover(chatSessionId: String, message: String?)
    func endChat(chatSessionId: String)
    func on(_ event: String, callback: @escaping NormalCallback)
    func off(_ event: String)
}
```

**Key Features**:
- Socket.IO-Client-Swift v16.0+
- Auto-reconnection (5 attempts, exponential backoff)
- Connection state monitoring
- Event-based architecture
- Custom headers for authentication
- Debug logging in DEBUG builds

### 3. Core Layer

**Location**: `Sources/Conferbot/Core/`

#### ConferBot.swift

Main singleton class that serves as the SDK entry point.

```swift
class ConferBot: ObservableObject {
    static let shared = ConferBot()

    // Published properties (for SwiftUI)
    @Published var isConnected: Bool
    @Published var currentSession: ChatSession?
    @Published var messages: [any RecordItem]
    @Published var unreadCount: Int
    @Published var isAgentTyping: Bool

    // Configuration
    func initialize(apiKey: String, botId: String, config: ConferBotConfig, customization: ConferBotCustomization?)
    func identify(user: ConferBotUser)

    // Session management
    func startSession() async throws
    func endSession()

    // Messaging
    func sendMessage(_ text: String, metadata: [String: AnyCodable]?) async throws
    func sendTypingIndicator(isTyping: Bool)
    func initiateHandover(message: String?)

    // Push notifications
    func registerPushToken(_ token: String)
    func handlePushNotification(_ userInfo: [AnyHashable: Any]) -> Bool

    // UI presentation (UIKit)
    func present(from: UIViewController, animated: Bool)

    // Delegate for UIKit
    weak var delegate: ConferBotDelegate?
}
```

**Design Patterns**:
1. **Singleton**: Single shared instance
2. **ObservableObject**: SwiftUI Combine integration
3. **Delegate Pattern**: UIKit event callbacks
4. **Factory Pattern**: Creates API and Socket clients
5. **Observer Pattern**: Socket event handlers

**State Management**:
- Uses `@Published` properties for reactive SwiftUI updates
- Uses delegate callbacks for UIKit integration
- Manages socket listeners internally
- Thread-safe with `@MainActor` for UI updates

### 4. UI Layer

**Location**: `Sources/Conferbot/UI/`

#### UIKit Components

**ChatViewController.swift**
- Full-screen chat interface
- UITableView for message list
- Custom navigation bar with connection status
- Keyboard handling with keyboardLayoutGuide
- Combine subscriptions for reactive updates

**MessageCell.swift**
- Custom UITableViewCell for messages
- Dynamic bubble positioning (left/right)
- Avatar support with async image loading
- Time stamps
- Customizable colors and corner radius

**TypingIndicatorCell.swift**
- Animated three-dot indicator
- Appears while agent is typing

**ChatInputView.swift**
- UITextView with placeholder
- Auto-expanding height (up to 100pt)
- Send button with SF Symbols
- Character limit enforcement (5000 chars)
- Delegate pattern for events

#### SwiftUI Components

**ChatView.swift**
- Main chat container
- Header with connection status
- ScrollView with LazyVStack
- Auto-scroll to bottom on new messages
- Keyboard avoidance

**MessageBubble.swift**
- SwiftUI message view
- Dynamic styling based on message type
- Avatar support with AsyncImage
- Time stamps

**TypingIndicator.swift**
- SwiftUI animated typing dots
- Repeating fade animation

**ChatInput.swift**
- TextEditor with placeholder overlay
- Send button
- Height constraints
- Character limit

## Design Patterns

### 1. Singleton Pattern

```swift
public class ConferBot: ObservableObject {
    public static let shared = ConferBot()
    private init() {}
}
```

**Why**: Ensures single source of truth for chat state across the app.

### 2. Delegate Pattern (UIKit)

```swift
public protocol ConferBotDelegate: AnyObject {
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem)
    // ... other methods
}
```

**Why**: Provides event callbacks without tight coupling, follows iOS conventions.

### 3. ObservableObject (SwiftUI)

```swift
@Published public private(set) var messages: [any RecordItem] = []
```

**Why**: Enables reactive UI updates in SwiftUI views.

### 4. Protocol-Oriented Design

```swift
public protocol RecordItem: Codable {
    var id: String { get }
    var type: MessageType { get }
    var time: Date { get }
}
```

**Why**: Allows polymorphic handling of different message types.

### 5. Type Erasure

```swift
public struct AnyRecordItem: Codable {
    public let value: any RecordItem
}
```

**Why**: Enables heterogeneous arrays of RecordItem types while maintaining Codable.

### 6. Async/Await

```swift
public func sendMessage(_ text: String) async throws {
    // Network call
}
```

**Why**: Modern Swift concurrency for cleaner async code.

### 7. Combine Framework

```swift
ConferBot.shared.$messages
    .receive(on: DispatchQueue.main)
    .sink { messages in
        // Update UI
    }
```

**Why**: Reactive programming for automatic UI updates.

## Data Flow

### Sending a Message

```
User Input
    ↓
ChatInputView/ChatInput
    ↓
ConferBot.sendMessage()
    ↓
Add to local messages array (optimistic update)
    ↓
SocketClient.sendVisitorMessage()
    ↓
Socket.IO → embed-server
```

### Receiving a Message

```
embed-server → Socket.IO
    ↓
SocketClient receives event
    ↓
ConferBot handles event
    ↓
Decode JSON to RecordItem
    ↓
Add to messages array
    ↓
@Published triggers update
    ↓
UI automatically refreshes (SwiftUI)
    ↓
Delegate callback (UIKit)
```

### Session Lifecycle

```
1. Initialize SDK
   ConferBot.shared.initialize(apiKey:botId:)
   ↓
2. Connect Socket
   SocketClient.connect()
   ↓
3. Start Session
   APIClient.initSession() → ChatSession
   ↓
4. Socket Init
   SocketClient.mobileInit(chatSessionId:)
   ↓
5. Join Room
   SocketClient.joinChatRoom(chatSessionId:)
   ↓
6. Exchange Messages
   SocketClient.sendVisitorMessage() ↔ Socket events
   ↓
7. End Session
   SocketClient.endChat()
   SocketClient.leaveChatRoom()
```

## Threading Model

- **Main Thread**: All UI updates via `@MainActor`
- **Background**: Network requests (URLSession manages its own queue)
- **Socket Events**: Callback on socket.io queue, dispatched to main for UI updates

```swift
socketClient?.on(SocketEvents.botResponse) { [weak self] data, _ in
    // Socket.IO queue
    self?.handleBotResponse(data: data)
}

private func handleBotResponse(data: [Any]) {
    // Decode on current queue
    Task { @MainActor in
        // Update UI on main thread
        self.messages.append(message.value)
    }
}
```

## Error Handling

```swift
public enum ConferBotError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noData
    case notInitialized
    case socketNotConnected

    public var errorDescription: String? {
        // User-friendly messages
    }
}
```

**Strategy**:
- Throw errors from async functions
- Catch and log in UI layer
- Show user-friendly messages
- Graceful degradation (offline mode)

## Memory Management

- **Weak References**: Delegates and closure captures
- **Proper Cleanup**: `deinit` removes observers and disconnects
- **No Retain Cycles**: Careful use of `[weak self]` in closures

```swift
socketClient?.on(SocketEvents.connect) { [weak self] _, _ in
    guard let self = self else { return }
    // Safe to use self
}
```

## Security

- **API Key**: Sent in headers, never logged
- **HTTPS Only**: All API calls use HTTPS
- **Socket Auth**: Headers included in socket connection
- **Input Validation**: Message length limits, text sanitization
- **No Sensitive Data**: User metadata is optional

## Testing Strategy

- **Unit Tests**: Models, utilities, and business logic
- **Integration Tests**: API and Socket clients with mock servers
- **UI Tests**: Basic flow tests for critical paths
- **Mock Objects**: Test doubles for network layers

## Performance Considerations

1. **Lazy Loading**: Messages loaded on demand
2. **Image Caching**: Avatar images cached by URLSession
3. **Efficient Rendering**: SwiftUI LazyVStack, UITableView cell reuse
4. **Debouncing**: Typing indicator debounced
5. **Background Fetch**: Socket maintains connection in background

## Extension Points

1. **Custom UI**: Use headless mode with custom views
2. **Custom Events**: Listen to socket events directly
3. **Middleware**: Intercept messages before display
4. **Custom Storage**: Implement offline message queue

## Dependencies

- **Socket.IO-Client-Swift** (v16.0+): Real-time communication
- **UIKit**: iOS UI framework
- **SwiftUI**: Modern declarative UI
- **Combine**: Reactive programming
- **Foundation**: Core Swift framework

## Minimum Requirements

- iOS 13.0+ (UIKit, URLSession, Combine)
- Swift 5.7+ (async/await, some View)
- Xcode 14.0+

## Future Enhancements

1. **Offline Queue**: Persistent message storage with Core Data
2. **Rich Media**: Image/video preview and upload
3. **Voice Messages**: Audio recording and playback
4. **End-to-End Encryption**: Message encryption layer
5. **Analytics**: Built-in event tracking
6. **Localization**: Multi-language support
