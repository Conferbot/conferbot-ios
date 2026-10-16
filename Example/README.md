# Conferbot iOS SDK: example app

A small SwiftUI app that shows the SDK three ways: the floating launcher, the chat in a sheet, and the chat embedded in a screen. It depends on the SDK in this repository (`.package(path: "../..")`), so it always runs the code on your checkout.

## Prerequisites

- A Mac with Xcode (built and tested with Xcode 26) and an iOS 15+ simulator
- No account needed: the app starts with the public demo bot

## Build and run

`Example/SwiftUI` is a Swift package with an executable target, not an Xcode app project, so Xcode builds it but cannot launch it on the simulator by itself. Build it, wrap the binary in an `.app`, and install that:

```bash
cd Example/SwiftUI

# 1. Pick a simulator and boot it
xcrun simctl list devices available | grep iPhone
SIM=<the simulator's id>
xcrun simctl boot $SIM

# 2. Build (the device id is more reliable than its name)
xcodebuild build -scheme ConferbotExample -destination "id=$SIM" -derivedDataPath build

# 3. Wrap the binary and its resource bundles in an app
P=build/Build/Products/Debug-iphonesimulator
rm -rf build/ConferbotExample.app && mkdir -p build/ConferbotExample.app
cp $P/ConferbotExample build/ConferbotExample.app/
cp -R $P/*.bundle build/ConferbotExample.app/
sed 's/$(EXECUTABLE_NAME)/ConferbotExample/' Sources/Info.plist > build/ConferbotExample.app/Info.plist
codesign -s - --force build/ConferbotExample.app

# 4. Install and launch
open -a Simulator
xcrun simctl install $SIM build/ConferbotExample.app
xcrun simctl launch $SIM com.conferbot.example
```

The resource bundles carry the SDK's words in its five languages; without them the chat falls back to its keys. Delete `Example/SwiftUI/build` when you are done (it is not committed).

## Run it against Conferbot's cloud

This is the default: the app talks to `https://wdt.conferbot.com` with the demo bot and shows "Connected" at the top. To use your own bot, change the bot ID in `Sources/ExampleApp.swift` (from the dashboard's **Share** tab, **Mobile apps**; publish the bot first):

```swift
ConferBot.shared.initialize(
    apiKey: "conf_test_key_12345",          // any non-empty value
    botId: "691c970890527a0468f9b2c9",      // the demo bot; put your bot ID here
    config: config,
    customization: customization
)
```

## Run it against a local server

For Conferbot developers running the embed-server on their Mac.

1. Start the embed-server on port 8001 (in the `embed-server` repository, with its `.env` set up):

   ```bash
   PORT=8001 npm run dev
   ```

2. Point the app at it. The simulator shares the Mac's network, so `localhost` is your Mac. In `Sources/ExampleApp.swift`:

   ```swift
   let config = ConferBotConfig(
       enableNotifications: true,
       enableOfflineMode: true,
       apiBaseURL: "http://localhost:8001/api/v1/mobile",
       socketURL: "http://localhost:8001"
   )

   ConferBot.shared.initialize(apiKey: "conf_test_key_12345", botId: "YOUR_LOCAL_BOT_ID",
                               config: config, customization: customization)
   ```

   Pass the URLs in `ConferBotConfig`. `ConferBotEndpoints.configure(...)` accepts only `https://` URLs.

3. Let App Transport Security allow plain `http` to local addresses. In `Sources/Info.plist`, under `NSAppTransportSecurity`, add:

   ```xml
   <key>NSAllowsLocalNetworking</key>
   <true/>
   ```

   Your own app needs the same for a local server; never ship it for production.

4. Use a bot that exists in your local database, and publish it. Build, wrap and install again (steps 2 to 4 above).

5. On a real iPhone, `localhost` is the phone itself: use your Mac's address on the same Wi-Fi (`http://192.168.x.y:8001`). `NSAllowsLocalNetworking` covers `.local` names and local IP addresses.

Revert the URL and `Info.plist` changes before committing.

## What's inside

| Tab | What it shows |
|---|---|
| **Widget (FAB)** (default) | `.conferBotWidget()`: the floating launcher over the app, styled from the dashboard |
| **Modal (Sheet)** | `ChatView` in a sheet, the connection state and the unread count |
| **Embedded** | `ChatView` inside the app's own screen |

`ExampleApp.swift` initializes the SDK with a `ConferBotConfig` and a `ConferBotCustomization`, has an `identify(user:)` call ready to uncomment, and an `AppDelegate` that registers for push and forwards notifications (`setPushToken`, `handlePushNotification`).

## Push on the simulator

The simulator has no real APNs, but you can drop a payload on the app:

```bash
xcrun simctl push $SIM com.conferbot.example payload.apns
```

With the app in the foreground, a Conferbot payload for the demo bot is counted as unread and shows no banner. See the main [README](../README.md#push-notifications) for the payload and the server switch.

## Project structure

```
Example/SwiftUI/
  Package.swift              SPM manifest, the SDK as a local dependency
  Sources/
    ExampleApp.swift         @main, SDK initialization, push AppDelegate
    ContentView.swift        the three tabs
    Info.plist               bundle id com.conferbot.example, ATS
```

More on testing on the simulator (a UIKit check, a local agent, screenshots) in [docs/PARITY.md](../docs/PARITY.md#how-to-test).
