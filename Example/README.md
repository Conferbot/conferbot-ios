# Conferbot iOS SDK - Example App

Demonstrates how to integrate the Conferbot iOS SDK using SwiftUI.

## Prerequisites

- **Xcode** 15.0 or later
- **iOS 15.0+** simulator or device
- A Conferbot **API Key** and **Bot ID** from your dashboard

## Setup

1. Open the `Example/SwiftUI/` directory in Xcode:
   - File > Open, then select the `Example/SwiftUI/` folder.
   - Xcode will detect the `Package.swift` and resolve the SDK dependency automatically.

2. Open `Sources/ExampleApp.swift` and replace the placeholder values:

```swift
ConferBot.shared.initialize(
    apiKey: "YOUR_API_KEY",   // Replace with your API key
    botId: "YOUR_BOT_ID",    // Replace with your bot ID
)
```

3. Select an iOS simulator (iPhone 15 or later recommended).
4. Click **Run** (or press Cmd+R).

## What's Inside

The example app demonstrates two integration patterns, switchable via a segmented picker:

### Modal Pattern
- Tap "Start Chat" to open the SDK's `ChatView` as a sheet.
- Shows connection status (green/orange indicator).
- Displays unread message count badge.

### Embedded Pattern
- `ChatView` rendered inline within your view hierarchy.
- Same full functionality, no modal.

### Demonstrated Features
- SDK initialization with custom configuration
- Real-time connection status via `@ObservedObject`
- Unread count tracking
- Light/dark mode support
- User identification (commented out, ready to enable)

## Project Structure

```
Example/
  SwiftUI/
    Package.swift              -- SPM manifest with local SDK dependency
    Sources/
      ExampleApp.swift         -- @main entry point, SDK initialization
      ContentView.swift        -- Main view with modal and embedded patterns
      Info.plist               -- App configuration
```

## UIKit Example

A UIKit example is not included in this directory. For UIKit integration, see the SDK README which demonstrates:

```swift
// Present as a modal from any UIViewController
ConferBot.shared.present(from: self)
```
