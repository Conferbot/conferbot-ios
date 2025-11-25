# Changelog

All notable changes to the Conferbot iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-25

### Added

#### Core Features
- Initial release of Conferbot iOS SDK
- Native Swift implementation (Swift 5.7+)
- iOS 13.0+ support
- Real-time Socket.IO communication
- RESTful API client with async/await
- Singleton architecture with `ConferBot` class

#### Models
- Complete data model matching embed-server schema
- `Agent` and `AgentDetails` models
- `RecordItem` protocol with subclasses:
  - `UserMessageRecord`
  - `BotMessageRecord`
  - `AgentMessageRecord`
  - `AgentMessageFileRecord`
  - `AgentMessageAudioRecord`
  - `AgentJoinedMessageRecord`
  - `SystemMessageRecord`
- `ChatSession` model
- `ConferBotUser` for user identification
- `ConferBotConfig` for SDK configuration
- `ConferBotCustomization` for UI theming
- `MessageType` enum with all message types
- `SocketEvents` constants matching embed-server

#### Networking
- `APIClient` with URLSession
  - `initSession()` - Start new chat session
  - `getSessionHistory()` - Retrieve message history
  - `sendMessage()` - Send user messages
  - `registerPushToken()` - Register APNs token
- `SocketClient` with Socket.IO
  - Auto-reconnection (5 attempts with exponential backoff)
  - Event-based architecture
  - All embed-server socket events supported
  - Connection status monitoring

#### UIKit Components
- `ChatViewController` - Full-featured chat screen
  - Message list with UITableView
  - Auto-scroll to bottom
  - Keyboard handling with iOS 15+ keyboardLayoutGuide
  - Connection status indicator
  - Navigation bar customization
- `MessageCell` - Custom table view cell
  - Dynamic bubble positioning
  - Avatar support with async loading
  - Time stamps
  - Support for all message types
  - Customizable colors and corner radius
- `TypingIndicatorCell` - Animated typing indicator
- `ChatInputView` - Text input component
  - Auto-expanding UITextView (up to 100pt)
  - Placeholder text
  - Character limit enforcement (5000)
  - Send button with SF Symbols
  - Delegate pattern for events

#### SwiftUI Components
- `ChatView` - Main chat interface
  - Reactive updates via Combine
  - Auto-scroll to new messages
  - Connection status header
  - Typing indicator integration
- `MessageBubble` - Message display view
  - Dynamic styling based on message type
  - Avatar support with AsyncImage
  - Time stamps
  - Customizable appearance
- `ChatInput` - Text input component
  - TextEditor with placeholder overlay
  - Send button
  - Character limit
  - Editing state callbacks
- `TypingIndicator` - Animated dots indicator

#### State Management
- Combine framework integration
- `@Published` properties for SwiftUI reactivity
- Delegate pattern for UIKit callbacks
- Observable `ConferBot` class

#### Features
- User identification with metadata
- Push notification support (APNs)
- Typing indicators (bidirectional)
- Unread message counter
- Connection status monitoring
- Live agent handover
- Session management
- Message history retrieval
- Offline message handling
- Debug logging in DEBUG builds

#### Customization
- Primary color
- Font family
- Bubble corner radius
- Header title
- Avatar visibility and URL
- Bot bubble color
- User bubble color
- Full theme support

#### Distribution
- Swift Package Manager support
- CocoaPods support
- Minimum iOS 13.0
- Xcode 14.0+ required
- Swift 5.7+ required

#### Documentation
- Comprehensive README.md
- Architecture guide (ARCHITECTURE.md)
- Component guide (COMPONENTS.md)
- API reference (API.md)
- Usage examples (EXAMPLES.md)
- Publishing guide (PUBLISHING.md)
- Installation instructions
- Code examples for UIKit and SwiftUI
- Integration patterns (drop-in, embedded, headless)

#### Examples
- E-commerce product support
- Banking secure chat with biometrics
- SaaS dashboard integration
- Healthcare HIPAA-compliant chat
- Custom UI implementations
- Deep linking support
- Notification handling

#### Developer Experience
- Type-safe API with Swift protocols
- Async/await for modern concurrency
- Combine publishers for reactive programming
- Comprehensive error handling
- Memory management best practices
- Thread-safe implementation
- Clean architecture with clear separation of concerns

### Dependencies
- Socket.IO-Client-Swift (~> 16.0)

### Platform Support
- iOS 13.0+
- iPadOS 13.0+
- Xcode 14.0+
- Swift 5.7+

### Known Issues
- None at initial release

### Migration Guide
- N/A - Initial release

---

## [Unreleased]

### Planned Features
- Core Data persistence for offline mode
- Rich media support (images, videos)
- Voice message recording and playback
- File upload with progress indicator
- Read receipts
- Message reactions
- End-to-end encryption
- Multi-language localization
- Built-in analytics
- Accessibility enhancements
- iPad split-view optimization
- macOS Catalyst support
- watchOS companion app
- Widget support
- Siri shortcuts integration

### Planned Improvements
- Performance optimizations
- Reduced memory footprint
- Faster message rendering
- Image caching improvements
- Background fetch optimization
- More customization options
- Additional UI themes
- Enhanced error messages
- Better offline support
- Comprehensive test coverage

### Future Considerations
- SwiftUI-only mode (dropping UIKit)
- iOS 15+ minimum (leveraging new APIs)
- visionOS support
- App Intents framework
- ActivityKit for Live Activities

---

## Version History

- **1.0.0** (2025-11-25) - Initial release

---

## Upgrade Notes

### From Pre-release to 1.0.0
N/A - First stable release

---

## Breaking Changes

### 1.0.0
- N/A - Initial release

---

## Deprecations

### 1.0.0
- None

---

## Security Updates

### 1.0.0
- Secure socket communication over HTTPS
- API key authentication
- No sensitive data logged
- Secure user identification

---

## Performance Improvements

### 1.0.0
- Optimized message rendering with cell reuse
- Lazy loading for SwiftUI
- Efficient socket reconnection strategy
- Minimal memory footprint
- Async image loading for avatars

---

## Bug Fixes

### 1.0.0
- N/A - Initial release

---

## Contributors

Thanks to everyone who contributed to the initial release:
- Conferbot Team
- Early beta testers
- Community feedback

---

## Links

- [GitHub Repository](https://github.com/conferbot/conferbot-ios)
- [Documentation](https://docs.conferbot.com/mobile/ios)
- [CocoaPods](https://cocoapods.org/pods/Conferbot)
- [Issue Tracker](https://github.com/conferbot/conferbot-ios/issues)
- [Discord Community](https://discord.gg/conferbot)

---

[1.0.0]: https://github.com/conferbot/conferbot-ios/releases/tag/1.0.0
[Unreleased]: https://github.com/conferbot/conferbot-ios/compare/1.0.0...HEAD
