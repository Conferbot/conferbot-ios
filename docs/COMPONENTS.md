# UI Components Guide

Complete guide to all UI components in the Conferbot iOS SDK, covering both UIKit and SwiftUI.

## Overview

The SDK provides native UI components for both UIKit and SwiftUI, allowing you to choose the best approach for your app.

## UIKit Components

### ChatViewController

Full-featured chat view controller ready to present modally or embed.

#### Basic Usage

```swift
import Conferbot

// Present modally
Conferbot.shared.present(from: self)

// Or embed in container
class ContainerViewController: UIViewController {
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

#### Features

- Message list with auto-scroll
- Typing indicator
- Connection status in navigation bar
- Keyboard management
- Pull-to-refresh (coming soon)

### MessageCell

Custom table view cell for displaying messages.

#### Automatic Handling

The SDK automatically:
- Positions bubbles (left for bot/agent, right for user)
- Shows/hides avatars
- Formats timestamps
- Applies custom colors
- Handles different message types

#### Message Types Rendered

1. **User Messages**: Right-aligned, blue bubble (customizable)
2. **Bot Messages**: Left-aligned, gray bubble (customizable)
3. **Agent Messages**: Left-aligned with agent avatar
4. **File Messages**: Shows file icon and name
5. **Audio Messages**: Shows audio icon
6. **System Messages**: Centered, light background

### ChatInputView

Text input component with send button.

#### Features

- Auto-expanding text view (up to 100pt)
- Placeholder text
- Character limit (5000)
- Send button disabled when empty
- Typing indicator integration

#### Delegate

```swift
protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String)
    func chatInputViewDidBeginEditing(_ inputView: ChatInputView)
    func chatInputViewDidEndEditing(_ inputView: ChatInputView)
}
```

#### Custom Usage

```swift
class CustomChatVC: UIViewController {
    let inputView = ChatInputView()

    override func viewDidLoad() {
        super.viewDidLoad()

        inputView.delegate = self
        view.addSubview(inputView)

        // Layout constraints...
    }
}

extension CustomChatVC: ChatInputViewDelegate {
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String) {
        Task {
            try? await Conferbot.shared.sendMessage(message)
        }
    }

    func chatInputViewDidBeginEditing(_ inputView: ChatInputView) {
        Conferbot.shared.sendTypingIndicator(isTyping: true)
    }

    func chatInputViewDidEndEditing(_ inputView: ChatInputView) {
        Conferbot.shared.sendTypingIndicator(isTyping: false)
    }
}
```

## SwiftUI Components

### ChatView

Main chat view for SwiftUI apps.

#### Basic Usage

```swift
import SwiftUI
import Conferbot

struct ContentView: View {
    @State private var showChat = false

    var body: some View {
        Button("Open Chat") {
            showChat = true
        }
        .sheet(isPresented: $showChat) {
            ChatView()
        }
    }
}
```

#### Embedded Usage

```swift
struct SupportView: View {
    var body: some View {
        NavigationView {
            ChatView()
                .navigationTitle("Support")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

#### Features

- Reactive updates via Combine
- Auto-scroll to new messages
- Connection status indicator
- Typing indicator
- Keyboard avoidance

### MessageBubble

SwiftUI view for individual messages.

#### Custom Usage

```swift
import SwiftUI
import Conferbot

struct CustomChatView: View {
    @ObservedObject var conferBot = ConferBot.shared

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(Array(conferBot.messages.enumerated()), id: \.offset) { index, message in
                    MessageBubble(
                        message: message,
                        customization: conferBot.customization
                    )
                }
            }
        }
    }
}
```

#### Customization

```swift
// The MessageBubble automatically reads from ConferBotCustomization
let customization = ConferBotCustomization(
    bubbleCornerRadius: 20,
    botBubbleColor: .systemBlue,
    userBubbleColor: .systemGreen
)
```

### ChatInput

SwiftUI text input component.

#### Custom Usage

```swift
struct CustomChatView: View {
    @State private var inputText = ""

    var body: some View {
        VStack {
            // Your message list
            Spacer()

            ChatInput(text: $inputText) { message in
                // Handle send
                Task {
                    try? await Conferbot.shared.sendMessage(message)
                }
            } onEditingChanged: { isEditing in
                // Handle typing indicator
                Conferbot.shared.sendTypingIndicator(isTyping: isEditing)
            }
        }
    }
}
```

### TypingIndicator

Animated three-dot indicator.

#### Usage

```swift
struct ChatView: View {
    @ObservedObject var conferBot = ConferBot.shared

    var body: some View {
        VStack {
            // Messages...

            if conferBot.isAgentTyping {
                TypingIndicator()
            }
        }
    }
}
```

## Customization

### Colors

```swift
let customization = ConferBotCustomization(
    primaryColor: UIColor.systemRed,
    botBubbleColor: UIColor.systemBlue,
    userBubbleColor: UIColor.systemGreen
)

Conferbot.shared.initialize(
    apiKey: "...",
    botId: "...",
    customization: customization
)
```

### Fonts

```swift
let customization = ConferBotCustomization(
    fontFamily: "SFProText-Regular"
)
```

Note: Font changes affect the SDK internally. For SwiftUI, you can override with `.font()` modifier.

### Corner Radius

```swift
let customization = ConferBotCustomization(
    bubbleCornerRadius: 20
)
```

### Avatar

```swift
let customization = ConferBotCustomization(
    showAvatar: true,
    avatarURL: URL(string: "https://your-domain.com/avatar.png")
)
```

### Header

```swift
let customization = ConferBotCustomization(
    headerTitle: "Customer Support"
)
```

## Building Custom UI

### Headless Mode (UIKit)

```swift
class CustomChatViewController: UIViewController, ConferBotDelegate {
    private var messages: [any RecordItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        Conferbot.shared.delegate = self

        Task {
            try? await Conferbot.shared.startSession()
        }
    }

    // Implement your own UI
    func conferBot(_ conferBot: ConferBot, didReceiveMessage message: any RecordItem) {
        messages.append(message)
        // Update your custom UI
    }

    @IBAction func sendButtonTapped() {
        Task {
            try? await Conferbot.shared.sendMessage(messageTextField.text ?? "")
        }
    }
}
```

### Headless Mode (SwiftUI)

```swift
struct CustomChatView: View {
    @ObservedObject var conferBot = ConferBot.shared
    @State private var inputText = ""

    var body: some View {
        VStack {
            // Custom message list
            List(conferBot.messages, id: \.id) { message in
                CustomMessageRow(message: message)
            }

            // Custom input
            HStack {
                TextField("Message", text: $inputText)
                Button("Send") {
                    Task {
                        try? await conferBot.sendMessage(inputText)
                        inputText = ""
                    }
                }
            }
        }
        .task {
            try? await conferBot.startSession()
        }
    }
}
```

## Advanced Examples

### Custom Message Cell (UIKit)

```swift
class CustomMessageCell: UITableViewCell {
    func configure(with message: any RecordItem) {
        if let userMessage = message as? UserMessageRecord {
            // Custom user message layout
        } else if let botMessage = message as? BotMessageRecord {
            // Custom bot message layout
        }
    }
}

class CustomChatVC: UIViewController, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CustomCell") as! CustomMessageCell
        cell.configure(with: messages[indexPath.row])
        return cell
    }
}
```

### Custom Message Bubble (SwiftUI)

```swift
struct CustomMessageBubble: View {
    let message: any RecordItem

    var body: some View {
        HStack {
            if isUserMessage {
                Spacer()
            }

            VStack(alignment: .leading) {
                // Author name
                if !isUserMessage {
                    Text(authorName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Message
                Text(messageText)
                    .padding()
                    .background(bubbleColor)
                    .cornerRadius(16)

                // Timestamp
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isUserMessage {
                Spacer()
            }
        }
    }

    // Helper computed properties...
}
```

### Custom Input with Attachments (UIKit)

```swift
class EnhancedChatInputView: UIView {
    private let textView = UITextView()
    private let sendButton = UIButton()
    private let attachButton = UIButton()

    func setupUI() {
        // Add attachment button
        attachButton.setImage(UIImage(systemName: "paperclip"), for: .normal)
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)

        // Layout with text view and both buttons
    }

    @objc func attachTapped() {
        // Show file picker
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf])
        // ...
    }
}
```

### Custom Input with Voice (SwiftUI)

```swift
struct VoiceChatInput: View {
    @State private var text = ""
    @State private var isRecording = false

    var body: some View {
        HStack {
            if isRecording {
                // Recording UI
                RecordingWaveform()
                Button("Send") {
                    // Send voice message
                }
            } else {
                TextField("Message", text: $text)
                Button(action: startRecording) {
                    Image(systemName: "mic.fill")
                }
            }
        }
    }

    func startRecording() {
        // Start audio recording
    }
}
```

## Accessibility

All components support VoiceOver and Dynamic Type:

```swift
// UIKit - automatically handled
messageLabel.adjustsFontForContentSizeCategory = true

// SwiftUI - automatically handled
Text("Message")
    .font(.body)  // Scales with Dynamic Type
```

### Custom Accessibility Labels

```swift
// UIKit
sendButton.accessibilityLabel = "Send message"
sendButton.accessibilityHint = "Sends your message to the support team"

// SwiftUI
Button("Send") { }
    .accessibilityLabel("Send message")
    .accessibilityHint("Sends your message to the support team")
```

## Dark Mode Support

All components automatically adapt to dark mode. No configuration needed.

### Custom Dark Mode Colors

```swift
let lightColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
let darkColor = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)

let adaptiveColor = UIColor { traitCollection in
    traitCollection.userInterfaceStyle == .dark ? darkColor : lightColor
}

let customization = ConferBotCustomization(
    botBubbleColor: adaptiveColor
)
```

## Performance Tips

1. **Use LazyVStack** in SwiftUI for long message lists
2. **Reuse cells** in UIKit (automatically handled by SDK)
3. **Async image loading** for avatars (built-in)
4. **Debounce typing indicator** (built-in)

## Testing UI Components

### UIKit Testing

```swift
import XCTest
@testable import Conferbot

class ChatViewControllerTests: XCTestCase {
    func testMessageDisplay() {
        let vc = ChatViewController()
        _ = vc.view  // Trigger viewDidLoad

        // Add test messages
        // Verify table view
    }
}
```

### SwiftUI Testing

```swift
import SwiftUI
import ViewInspector
@testable import Conferbot

class ChatViewTests: XCTestCase {
    func testMessageList() throws {
        let view = ChatView()
        let messages = try view.inspect().find(ViewType.List.self)
        XCTAssertNotNil(messages)
    }
}
```

## Component Lifecycle

### UIKit

```swift
// Initialization
let chatVC = ChatViewController()

// Presentation
present(chatVC, animated: true)

// Cleanup (automatic)
dismiss(animated: true)  // Removes observers
```

### SwiftUI

```swift
// Initialization
ChatView()  // Creates on first render

// Presentation
.sheet(isPresented: $show) { ChatView() }

// Cleanup (automatic)
// onDisappear called when dismissed
```

## Best Practices

1. **Always initialize SDK before showing UI**
2. **Use provided components** for consistency
3. **Customize through ConferBotCustomization** not direct modification
4. **Handle errors gracefully** in custom UI
5. **Test on different screen sizes** and orientations
6. **Support Dark Mode** if building custom UI
7. **Follow iOS HIG** for custom components
