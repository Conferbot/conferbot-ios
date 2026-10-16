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
- **Live agent handover** - the web widget's handover lifecycle: the "Connecting you with the team…" line and how the wait ended, the header's reply time, leaving the queue, waiting signals, and a live chat picked back up after the app restarts
- **While you wait** - while the visitor waits for a person: help articles for their question, the team's own pick with "That solved it", and seven small games (SwiftUI chat)
- **AI answers as on the web** - Tables, headings, quotes, code blocks and strikethrough in replies; "Helpful?" under the newest answer (a No is sent at once, then reasons, a comment, "Talk to a person", "Ask another way"; the vote can change); "That took too long" when a reply takes more than 45s; fallback replies muted; the phone's language sent so short messages are answered in it
- **Home screen** - with the home screen on in the dashboard, `ChatView` opens on it: a greeting by the time of day (or "Welcome back, Jamie"), "Ask anything" (your AI agent or your help articles), "Pick up where you left off", "Your requests", "Talk to us" with the reply time and your team, recent articles and topics, and your customer logos. Moves between home, chat and help centre in your chosen transition
- **Greet by name** - `{{first_name|there}}` in your greeting and home texts is filled from the signed-in user
- **Your requests** - the visitor's own conversations with your team: where each stands in plain words ("We replied", "We're on it", "Solved"), the conversation, and a reply box (a reply to a solved one opens it again). In the chat menu once the visitor has one ("Your requests · New reply" when a reply is unread), and `ConferBot.shared.requests` for your own screens and badge
- **Email me this chat** - From the chat menu (the header's ... in SwiftUI, the bar button in UIKit) the visitor gets the whole conversation in their inbox (`POST /api/v1/mobile/chat/transcript-email`)
- **Sounds** - the owner's message sound, sound pack and launcher sound, with Sound on / off in the chat menu (kept on the device); played under the ambient audio session, so the silent switch mutes them
- **Human touches** - the bot's emoji tapback on an answer, confetti for a booking, a payment or a perfect score, sparks and the word for a rating pick, a gentle "No rush" after a question waits, and "Edit" under the latest answer to change it (each can be turned off in the dashboard; no motion with Reduce Motion)
- **Your font** - the owner's font (or the theme's) from Google Fonts in the chat, loaded at run time and kept on the device
- **Widget languages** - the SDK's own words in English, Dutch, French, German or Spanish, chosen as the web widget chooses (see [Languages](#languages))
- **Offline support** - Automatic message queuing and replay when connectivity returns
- **Session persistence** - Sessions and messages are restored across app restarts, with configurable expiry
- **Push notifications** - APNs token registration and notification handling
- **Knowledge base** - Built-in `KnowledgeBaseView` plus async APIs for categories, articles, search, ratings, and engagement tracking
- **Analytics** - Session, message, interaction, and goal tracking via `ChatAnalytics`
- **Theming** - Local `ConferBotCustomization` plus automatic server customizations from the dashboard

## Requirements

| Dependency | Version |
|------------|---------|
| iOS        | 15.0+ for the SwiftUI components (13.0+ for the core and UIKit; the SPM manifest declares iOS 13) |
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

Or push it, or present it yourself:

```swift
navigationController?.pushViewController(ChatViewController(), animated: true)
present(UINavigationController(rootViewController: ChatViewController(enableKnowledgeBase: false)), animated: true)
```

**What the UIKit chat is (iOS 15+):** `ChatViewController` hosts the SwiftUI `ChatView` in a `UIHostingController` child, so a UIKit app gets exactly what SwiftUI apps get, from one implementation: the owner's home screen, the help centre, "Your requests", every step card, the wait cards and the waiting games, formatted (markdown) replies with tables and headings, the human touches (tapback, confetti, rating caption, "No rush", "Edit"), the owner's font, every typing style, the live chat cards, the post-chat rating and redirect, and the chat menu (Your requests, Email me this chat, Sound on / off). `enableKnowledgeBase` works as `ChatView`'s: `nil` (the default) and `true` follow the owner, `false` hides the help centre.

- **Header and navigation bar:** the chat draws the bot's own header (colours, logo, title, status line, menu and ✕; the home screen has its own ✕). The navigation bar is hidden while the chat is on screen and put back as it was when the chat goes (a pushed chat going back, a screen pushed over it). The header's colour runs up under the status bar, and the status bar text follows it.
- **✕:** pops the chat when it was pushed on your navigation stack, else dismisses it (`present(from:)` and your own presentation).
- **On iOS 13 / 14** the UIKit-drawn chat is used instead, as before: the navigation bar in the bot's colours with ✕ and the menu (Email me this chat, Sound on / off), plain-text bubbles, typing dots and the composer; typed questions are answered from the composer. The step cards, live chat cards, help centre, home screen, wait cards and requests need iOS 15.
- **No launcher in UIKit:** the greeting card, the mascot launcher, the launcher's entrance, attention and idle call, and auto-open belong to the floating launcher (`conferBotWidget()`, SwiftUI). A UIKit app opens the chat from its own button; it can still host the launcher in a `UIHostingController` if it wants one.

**Migrating from the UIKit-drawn chat:** `ChatViewController()` and `present(from:)` are unchanged. What changed on iOS 15+: the chat no longer sets your navigation bar's appearance or its bar button items (it hides the bar and draws its own header), so customise the chat through the dashboard rather than `navigationBar` appearance; the table view, `MessageCell` and `ChatInputView` are no longer what is on screen (they stay public for custom layouts and are what iOS 13 / 14 draw); the interactive swipe-back may not work while the navigation bar is hidden, use ✕. `ChatViewController` was never subclassable outside the SDK (`public`, not `open`), and its `UITableViewDataSource` / `ChatInputViewDelegate` conformances are gone (they were internal plumbing).

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
            ChatView() // the Help tab follows the bot's help centre setting; ChatView(enableKnowledgeBase: false) hides it
        }
    }
}
```

### Pattern 3 - Floating Widget (FAB)

Overlay a floating chat bubble on any SwiftUI view, exactly like the web widget's bottom-right launcher. Tapping the bubble opens `ChatView` in a sheet; tapping again shows a close icon. The bubble reads your dashboard customizations automatically: background color, size, corner radius, left/right position, offsets, launcher icon (all 15 web widget icons), the greeting card, and an unread-count badge.

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
    socketURL: ConferBotEndpoints.socketURL,            // default: https://wdt.conferbot.com
    widgetLanguage: nil,                                // "en", "nl", "fr", "de", "es" or "auto"; nil = the bot's setting
    onPostChatRedirect: nil,                            // (String) -> Bool: true = the app handled the post-chat redirect
    disablePostChatRedirect: false                      // true = never follow the owner's post-chat redirect
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

### Languages

The SDK draws its own words (buttons, hints, errors, the handover lines, the queue card, the help centre, "Helpful?", the requests, the home screen, the games, the greeting card, the step cards and their checks, "5 min ago") in English, Dutch, French, German or Spanish, as the web widget does. The language is the owner's choice (dashboard: `widgetLanguage`); with "auto", or a bot that never chose, it is the phone's first supported language (`Locale.preferredLanguages`), else English. `ConferBotConfig(widgetLanguage:)` overrides both. What the owner wrote (greetings, messages, buttons in the flow) is shown as written; the stock English defaults a new bot comes with ("Hi there 👋") are shown in the language. Dates and numbers follow the language, keeping the phone's region when it matches (nl-BE).

```swift
ConferBot.shared.initialize(apiKey: "conf_YOUR_API_KEY", botId: "YOUR_BOT_ID",
                            config: ConferBotConfig(widgetLanguage: "de"))

ConferBot.shared.widgetLanguage   // .de (published, for your own views)
I18n.t("chat.composer.send")      // "Senden"
```

The words come from the React Native SDK's `scripts/parity/i18n/strings.json` (the web widget's tables plus the SDK-only words), bundled as `Resources/i18n-strings.json`; `scripts/sync-i18n.sh` copies a newer one.

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

The user (its `metadata`, then `id`, `name`, `email`, `phone`) also travels with every message record as the chat's visitor context, as the web widget's `visitorContext` does, so the dashboard shows the visitor's name, email and your own fields.

### Identity verification

To stop anyone posing as one of your users, turn on identity verification in your workspace and pass a `hash`: the HMAC-SHA256 (hex) of the user's `id` (or `email` when there is no id), keyed with your workspace's identity secret. Make it on your server and never ship the secret in the app.

```swift
ConferBot.shared.identify(user: ConferBotUser(id: "user-123", email: "jane@example.com", hash: hashFromYourServer))
```

The server checks the hash and drops it before storing. A chat with a matching hash is filed as verified; a wrong hash is rejected, and no hash leaves it unverified.

### Signing out

On a shared device, sign the user out so the next person doesn't see their requests or name:

```swift
ConferBot.shared.identify(user: nil)
```

The last user's "Your requests" list is dropped at once (a list still on its way for them is ignored) and read again for whoever is next. Texts that greet by name (`{{first_name|there}}`, `{{name}}`, `{{company}}` in the greeting and home screen texts) follow the user, else their fallback.

## Your requests

The visitor's conversations with your team (the web widget's "Your requests"): the list, one request with a banner saying where it stands, the messages, and a reply box. Team replies arrive live while one is open; a reply to a solved request opens it again.

- **Whose:** only the visitor's own. The device remembers, per bot, the last 30 chats the visitor wrote in and when each request was last read (UserDefaults); the server lists a conversation only when its id is one of those and the visitor id matches. A user you sign in with a valid `hash` (see Identity verification) also sees their verified conversations from any device. A chat the AI answered on its own is not a request. A first-time visitor asks nothing.
- **Stock UI:** the chat menu shows "Your requests" once there is one (`ChatView`'s header menu, also in the UIKit `ChatViewController`, which hosts `ChatView`, iOS 15). The screens sit over the chat in the bot's colours.
- **Your own UI or badge:**

```swift
@ObservedObject var requests = ConferBot.shared.requests   // main actor

requests.requests        // [RequestSummary]?, newest replies first
requests.unread          // replies not read on this device: your badge
requests.open()          // the list over a view that has RequestsPortalView()
requests.open(requestId: id)
await requests.refresh(force: true)

// SwiftUI: put the screens over your own view (nothing is drawn while closed)
MyScreen().overlay(RequestsPortalView())

// UIKit (iOS 15)
present(RequestsViewController(), animated: true)
```

English only for now; replies are text.

## Home screen

When the owner turns the home screen on (Customize > Home, `enableInitialPage`), the SwiftUI `ChatView` opens on it, as the web widget does:

- the greeting by the visitor's clock ("Good morning") or "Welcome back, Jamie" once they've chatted before, the logo and name, the title and description (`{{first_name|there}}` filled in);
- **Ask anything** (`homeAskBox`): with an AI agent, "Ask “…”" opens the chat and asks it; the help articles that answer it are listed too (also matches inside article text from the server); a flow bot with nothing found offers "Chat with us";
- **Pick up where you left off** (AI agent bots): the conversation on the device, or the question asked again;
- **Your requests**: two rows and "See all (n)", above "Talk to us" when a reply is new;
- **Talk to us**: who answers, Online and the reply time (`hideOnlineStatus` hides both), your team's photos, up to three of your agent's questions, the rating;
- the **help card** (recent articles unless `hideRecentArticles`, topics, See all; its own search when the ask box is off), and your customer logos with their line.

The chat header's ‹ goes back home, and so does the help centre's Back; articles and "Your requests" open over the home. Views move in the owner's `viewTransition` (fade; slide; the other styles slide), a short fade with Reduce Motion. Your own screens can use `ConferBot.shared.home` (`view`, `model()`, `showHome()`, `showChat(_:)`, `showHelp(categoryId:)`) and draw `HomeScreenView`. The UIKit `ChatViewController` hosts `ChatView`, so it opens on the home screen too (iOS 15+); `ChatViewWithKBSheet` opens straight on the chat. English only.

## Theming and Flow-Builder Customizations

There are two sources of appearance settings, and they apply to different parts of the UI:

### 1. Server customizations (from the dashboard) - automatic

Whenever the socket connects, the SDK fetches your bot's configuration (the same `customizations` object the web widget uses) and exposes it as `ConferBot.shared.serverCustomizations`. These dashboard settings apply automatically, no client code required:

- **Floating widget (FAB)**: drawn as the web widget draws it on a phone. Colour or left-to-right gradient, icon ink that stays readable on light colours, launcher icon or uploaded image, left/right position, the phone size and offsets (`mobileWidgetSize`, `mobileOffsetBottom`, `mobileOffsetSide`; else 16pt from the edges), shape (`launcherShape`: speech bubble by default, circle, squircle, tab, peek), style (`launcherStyle`: icon, the bot's avatar with an online dot, the owner's mascot, or the label pill on iPad; iPhone shows the round button, as the web does), a soft glow in the header colour, and the greeting card (below). All 56 dashboard launcher icons are drawn as on the web, and they move as on the web: an idle moment about 2s after the launcher shows and a few more after (`launcherAnimation` subtle / lively; off stops it), a reaction when a message arrives while the chat is closed, and the ripple rings. Nothing moves while the chat is open, after it was opened, or with Reduce Motion on. The FAB is styled entirely from the server; there are currently no local overrides for it (`ConferBotFABConfig` is an empty placeholder reserved for future options).
- **Launcher entrance, attention and idle call** (all off unless chosen in the dashboard): `launcherEntrance` plays how the launcher arrives the first time it shows (lightning, rocket, portal, ufo, drop, confetti, coin, meteor, magic, parachute, plane, egg; classic just appears), once per app session per bot; the greeting card stays hidden until it lands and fades up 150ms later. `launcherAttention` loops a "look here" motion (pulse, wobble, bounce, shine, heartbeat and orbit on the launcher; wave and float on the greeting card) from 1.5s after it shows, pausing for the icon's own moments and stopping for the session once the chat is opened. `launcherIdleCall` sends the owner's mascot out from behind the launcher after `launcherIdleCallDelay` seconds (5-120, default 12) unopened (psst, peek, wave, knock, tap), with a speech bubble (`launcherIdleCallText`) that opens the chat: at most twice per app session, 3 minutes apart, then 3 days' rest per bot (UserDefaults `conferbot_idlecall_rest_<botId>`); closing the greeting stops calls for the session. None of them plays over an open chat or with Reduce Motion on. Drawn with SwiftUI Canvas; the timing matches the web (checked against Chrome in `Tests/LauncherFxGoldenTests.swift`).
- **Mascot**: the owner's mascot from the dashboard (`mascotShape`: 27 characters, from the blob, cat and fox to the medic, chef and laptop; `mascotEyes`, `mascotAccessory`, `mascotColor`, `mascotName`). With `launcherStyle` "mascot" the launcher is its head and body peeking over a soft light button (`mascotLauncherScale` 70-150%, default 112), blinking now and then; a reply arriving while the chat is closed makes it hop with a big smile. With `mascotInGreeting` it greets on the greeting card in place of the avatar, by its name, waving twice. `mascotMotion` sets how the card and its figure move: lively (default: the card springs up, the figure pops in, waves, nods and breathes, then at most three small gestures and still), subtle (a rise and one head tilt) or off; when the card goes, the figure hands off toward the launcher (opened) or bows (its x). The idle call is the same mascot. Reduce Motion keeps only the happy smile. Draw it in your own screens with `MascotView(look:accent:size:mood:)` (idle, wave, think, happy), for example on the home screen: `HomeScreenView(renderMascot: { AnyView(MascotView($0, size: 72, mood: "wave")) })`.
- **Greeting card**: the web widget's card by the closed launcher, 12pt above it and in line with its edge. It shows the bot's greeting (`chatIconCta` / `chatIconCtaText`) or the highest-priority greeting rule that fits the app (an app counts as the home page "/"; rules for given pages, countries, sources or page attributes never apply), including the smart greetings and the old proactive teaser, after `greetingDelay` seconds. `greetingFrequency` is honoured (every launch with a 5-minute rest after a close, once per app session, or once in N days), and so are rules' audience (new / returning, signed in), schedule, `minVisits`, "chatted" and own limits. Signed in means `identify(user:)` gave an id or email. The X dismisses it (its rule counts as dismissed); a tap opens the chat (or sends the greeting, or opens its link, per `greetingClickAction`), and starter chips send their text. All 11 `greetingStyle`s are drawn with their reveals: card, note, imessage (default), postcard, sticky, typewriter, glass, notification, neon, voice and aurora; Reduce Motion drops the motion and the tilts. Memory is kept per bot in UserDefaults under `conferbot.greeting.<botId>`.
- **Branding**: the server `hideBrand` flag takes precedence over the local `ConferBotCustomization.hideBrand` value for the "Powered by Conferbot" footer.
- **Chat look**: header colours, logo, title, tagline or "Online"; bot, visitor and option bubble colours and corners; avatar size and shape; font size; typing style (`typingStyle`: dots, wave, shimmer, pencil, or the mascot swaying by three thought dots, read out as "<name> is typing"; still with Reduce Motion; the UIKit chat on iOS 13 / 14 draws dots); custom footer text. Applied in `ChatView` and `ChatViewController`.
- **Chat background**: solid, gradient (linear, radial, mesh, blur), image with its mask, or one of the 13 patterns (patterns and gradients on iOS 15+; iOS 13-14 show the base colour).
- **Widget theme**: all 27 dashboard themes (Classic, Minimal, Glass, Neo-brutal, Midnight, Aurora and the rest). Each brings its surfaces, text colours, corner radii and bubble outline, as on the web widget. **Appearance** light, dark, or auto (follows the phone's dark mode, also when it changes while the chat is open); Midnight, Neon, Chalkboard, Cyberpunk and Space are always dark. **Colours** "Brand" keeps your colours; "Theme palette" swaps in the theme's own header, bubble, option and send-button colours. Your own bubble radius, option radius and chat background still win over the theme. The theme's font is used too (a "body" font for all text, a "display" one for the header title), unless the owner picked their own font (below).
- **Font**: the owner's `font` (any font of the dashboard's catalog, fetched from Google Fonts at run time as TrueType, registered for the app's process with Core Text and kept in Caches as `conferbot-fonts/<family>/<weight>.ttf`; a system or unknown font by its name) wins over the theme's. It draws the bubbles, the agent's replies, the composer, the header title, the home screen and the step cards' buttons; nothing changes until it has loaded, and on any failure the system font stays. The help centre and the live chat cards keep the system font, as does the UIKit-drawn chat on iOS 13 / 14 (the UIKit chat on iOS 15+ is `ChatView`).
- **Sounds**: `messageSound` (pop, chime, bubble) when a bot step or a person's / the AI's message arrives, at most every 800 ms; a `soundPack` (soft, playful, retro, bubbly, premium) for the chat opening, a message, the visitor sending and closing, in place of the others; the launcher sound file (`enableWidgetToggleSound`) when the chat opens and closes. The tones are worked out as the web's Web Audio plays them and rendered to a small WAV in memory (no files shipped), played with `AVAudioPlayer`. The SDK sets the `.ambient` audio session category only while your app has not chosen one, so the silent switch mutes the chat and other audio keeps playing. Sound on / off is in the chat menu (both chats) when the bot has a sound, kept in UserDefaults under `conferbot-sound-enabled`; `ConferBot.shared.sounds` for your own screens. No haptics.
- **Human touches** (SwiftUI chat; each on unless turned off: `botReactions`, `celebrations`, `stallNudges`, `allowChangeAnswer`): 550 ms after an answer, the bot's tapback on the bubble (a wave for a name, a party for a booking or payment, a heart, thumbs up or thank-you for a score); a second of confetti in the bot's colours for a booking, a payment or a perfect score; the rating's sparks and its word ("Good") on a pick; "No rush - ..." under a question that has waited 40 s with the chat on screen and nothing typed or touched for 15 s (once per question); "Edit" under the visitor's latest answer once the bot is quiet, while only safe steps ran since (no booking, payment, upload, code, AI call or person since), which puts the conversation back to that question and asks it again. No confetti or sparks with Reduce Motion. The UIKit chat draws them too (it hosts `ChatView`, iOS 15+); on iOS 13 / 14 it plays the sounds but draws none of these.
- **Auto-open** (`botAutoOpen`, `botAutoOpenDelay` seconds): the floating widget opens the chat on its own for a first visit only (no conversation yet), once per app launch per bot, and not within 2 minutes of the visitor closing it.
- **Typing preview** (`visitorDraftPreview`, on unless off): while a person (not the AI) is in the chat, they see what the visitor is typing (`visitor-draft`, at most every 300 ms, cleared on send); never from a secure field. Both chats.
- **Booked calendar slots**: times already booked (the bot's `calendarBookings` and the step's own) are greyed out and refused; a fully booked day says so.
- **The wait card**: the server's estimate in the visitor's language ("About 2 min"), else the team's usual wait ("Typical wait: a few minutes", from the routed team or the reply time; none for Fixed or Hide), else "Our team will be with you soon"; the usual wait again under a live estimate. Under them the step's max wait counts down once a second ("Max wait 1:05") and stops at 0:00; after a restart it counts from the server's time left (SwiftUI chat).
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

**Precedence, precisely**: once the bot's dashboard settings arrive they win over the local `ConferBotCustomization` for the FAB, `hideBrand`, the header, bubbles and the chat background. Before they arrive (or for a bot with none), the local customization applies. Light or dark follows the bot's theme appearance; with Classic in light and no theme, the system colours stay.

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

The help centre follows the bot owner's settings, as on the web widget:

- `ChatView` shows the Help tab only while the owner has the help centre on (`enableKnowledgeBase` in the dashboard). The server sends no articles otherwise.
- `ChatView(enableKnowledgeBase:)` is the host app's override. `nil` (the default) and `true` follow the owner; `false` hides the tab even when the owner turned it on. It cannot turn the help centre on against the owner's setting.
- Recent articles sit at the top of the help centre unless the owner hid them (`hideRecentArticles`).
- The topics and recent articles come with the connection (`fetched-chatbot-data`), without their bodies; an article's body is fetched when it opens. Without that payload the help centre loads over REST.
- A help article an AI answer cites (its sources) opens in the help centre by its id while the help centre is on (the Help tab, or a sheet when the host hid the tab), else its public page; with neither it says "Help article" and does not open. An article card opens its public page when it has one, else the article in the help centre. `ConferBot.shared.openHelpArticle(id:)` does the same from your own UI; `HelpCentre.isOn(ConferBot.shared.serverCustomizations)` (or `ConferBot.shared.isHelpCentreOn`) tells you whether the owner has it on.

`KnowledgeBaseView()` (or `KnowledgeBaseView(articleId:)`) can be presented standalone. For custom UIs, the async APIs on `ConferBot.shared`:

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

## How bot flows run

The bot's flow runs on the device as the web widget runs it: the SDK passes all 156 cases of the shared flow-node spec (`Tests/FlowFixtureTests.swift`, fixtures from conferbot-react-native `scripts/parity/flows`).

- The chat starts at the first welcome step. A step that doesn't branch leaves by its first edge; a branching one by its exact handle, and with no edge there the chat ends. Unknown step types are passed along their first edge.
- Answers are saved under each step's answer variable and fill `{name}`, `${name}`, `{{name}}` in later text (an unknown one shows nothing). Card numbers, ids and passwords are masked in what is saved and sent unless the bot's `redactSensitive` is off.
- GPT, AI route / extract, knowledge-base answers, OTP codes, address search and payments go through the bot server; the owner's keys never reach the app. Integrations (Sheets, HubSpot, Slack...) run on the server.
- Bot messages written in the rich-text editor are drawn formatted (bold, italic, links, lists).
- The SwiftUI chat draws every step that waits for the visitor: choice pills, stars or faces, the opinion scale, a slider, the date / time picker, the calendar and its slots, file upload, check options, ranking, cards, the matrix, consent, payment, and the OTP / address / signature extras next to the composer, in the bot's option colours. The UIKit `ChatViewController` is the same chat (it hosts `ChatView`, iOS 15+); on iOS 13 / 14 it answers typed questions from its composer only.
- Headless: answer the waiting step with `ConferBot.shared.answerStep(_:forNodeId:)` and the spec's answer built with `FlowStepAnswer` (`.value(4)`, `.calendar(date:slot:)`, `.checked(ids)`, `.matrix(...)`...), or `handleNodeInput(_:forNodeId:)` (typed text), `handleButtonClick(buttonId:forNodeId:)`, `handleMultipleChoiceSelection(optionIds:forNodeId:)`. `waitingStep(nodeId)` gives the step's type and data.

## Advanced Usage

### Observing state with Combine / SwiftUI

`ConferBot` is an `ObservableObject`. Published properties include `isConnected`, `currentSession`, `messages`, `unreadCount`, `isAgentTyping`, `isLiveChatMode`, `currentAgent`, `hasRestoredSession`, `serverCustomizations`, `currentUIState`, `isProcessingNode`, `nodeErrorMessage`, `isFlowComplete`, `isOnline`, `queuedMessageCount`, `knowledgeBaseCategories`, `isLoadingKnowledgeBase`, and `helpArticleToOpen`.

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
ConferBot.shared.handleFileUpload(fileURL: url, forNodeId: nodeId)    // a local copy: the step uploads it

// Any step, with the flow-node spec's answer
ConferBot.shared.answerStep(FlowStepAnswer.value(4), forNodeId: nodeId)                          // rating, scale, slider
ConferBot.shared.answerStep(FlowStepAnswer.calendar(date: "2026-10-21", slot: "09:30"), forNodeId: nodeId)
ConferBot.shared.answerStep(FlowStepAnswer.consent(agreed: true), forNodeId: nodeId)
ConferBot.shared.waitingStep(nodeId)                                                               // (type, data)

ConferBot.shared.getCurrentNodeId()
ConferBot.shared.nodeRequiresInteraction("user-input")   // Bool
ConferBot.shared.resetFlow()                              // restart conversation, new session
```

### Redirect after chat

When the owner sets a URL in Customize > Conversations > Post-chat redirect, the SDK follows it as the web widget does: once the conversation ends (the flow reaches its end, or an agent ends the chat) and the post-chat rating is sent or put away, a quiet line reads "Taking you to example.com in 10s" with Cancel (`ChatView`, so the UIKit chat too), then the URL opens in the system browser (`UIApplication.shared.open`). It stops if the visitor cancels, starts a new chat, closes the chat or the app goes to the background, and it is offered only once per conversation (remembered in UserDefaults). Only `http(s)` addresses are followed.

```swift
let config = ConferBotConfig(
    // Open it in your own screen instead; true = handled, no countdown.
    onPostChatRedirect: { url in
        router.showWeb(URL(string: url)!)
        return true
    }
    // Or turn it off: disablePostChatRedirect: true
)
```

Headless: `ConferBot.shared.postChatRedirect.line` (published `RedirectLine`: `text`, `said`, `phase`, `cancelLabel`), `.cancel()`, `.continueNow()`; `PostChatRedirectLineView` draws it.

### Live agent handover

```swift
ConferBot.shared.initiateHandover(message: "I need help with billing")
```

Agent lifecycle arrives via `agentDidJoin` / `agentDidLeave`, `isAgentTyping`, and `currentAgent`. During live chat, `sendTypingIndicator(isTyping:)` forwards visitor typing to the agent console.

The chat follows the handover as the web widget does:

- **The Connecting line.** When an AI agent hands the visitor to the team, the chat shows "Connecting you with the team…" with typing dots. It settles to how the wait ended: "Connected with the team", "The team couldn't join just now", "You left the queue" or "Chat ended before the team joined". A person joining after the AI gets "They can see your conversation so far". An AI pausing an idle visitor draws nothing on that line.
- **The header** keeps the bot's name. Under it: the team's reply time ("Typically replies in a few minutes", "Online · team back Monday 9 AM"), then plain "Online" once a person is in the chat. An AI agent bot shows "Online" only.
- **"Talk to a person"** (AI agent bots with the owner's switch on) is offered only while nobody is coming or here, and goes once tapped.
- **Leaving the queue.** The wait card's Cancel tells the server (`queue-self-resolve`) and the flow carries on. A person who already accepted keeps the chat. Call it yourself with `leaveQueue`:

```swift
ConferBot.shared.leaveQueue { left in
    // false: a person already picked the chat up
}
```

- **The AI's inactivity close** (`ai-agent-inactive-close`): "Chat paused" with "Send a message to pick up where you left off". The composer stays on and the visitor's next message brings the AI back. When the agent's close action is `continue_flow` on a flow bot: "Chat ended", and the flow goes on from its handover step's next edge (no post-chat survey). An AI agent bot is always only paused. The line is recorded once, so a restart shows the same line.
- **Max wait.** A flow handover asks the server to decide once the step's max wait passes (unset or 0 is 2 minutes); the wait card counts down to that moment, and a restored wait counts from the server's time left. After an AI hands the visitor on (not a person), the SDK waits the max wait plus 30 seconds, then nudges the server (`handover-timeout`) and draws nothing itself; an AI agent bot's silent handover step gives the max wait.
- **Restart.** A restored session asks the server where its live chat stands (`live-chat-state`): back live with the agent and the join line it missed, back on the handover step's wait without asking again, or the flow carries on. The server record and the flow's step are saved with the session for this.
- **Waiting signals**, as the web widget's `cb:*` events:

```swift
let stop = ConferBot.shared.onWidgetSignal(.waitingForHuman) { detail in
    // 20s into a wait with nobody yet, or the server's handover-waiting.
    // detail.offline, detail.reason ("offline" / "busy"), detail.backAt
}
ConferBot.shared.onWidgetSignal(.humanJoined) { detail in print(detail.name ?? "") }
ConferBot.shared.onWidgetSignal(.waitOver) { detail in print(detail.reason ?? "") } // unavailable, cancelled, ended
stop() // unsubscribe
```

The handover step's own settings (team email on or off, sound, assignment method and skills) are sent with the request.

- **Back in the queue.** When the agent leaves and the chat goes back to the queue, "Connecting you to another agent..." (or "Connecting you to Sales..." after a team transfer) is drawn and a flow at its handover step waits again. A transfer is kept in the conversation's record.
- **The end.** The same end twice (an agent's double click) draws one "Chat has ended" line and one rating card. The flow moves to the handover step's next step, asking the step's post-chat survey questions first when it has them; this also works for a chat restored after a restart. Once the chat has ended and nothing is going on, the composer turns off and "Start a new chat" starts a fresh conversation (`startNewChat()`). A blocked visitor refused at the handshake sees the bot's name (remembered from the last settings this device saw for the bot) and no "Connecting..." line. `ChatViewWithKBSheet` turns its message box off for a closed chat the same way and draws the closed line, "Start a new chat" and the live chat cards.
- **The post-chat rating at the flow's end.** As on the web, when a flow reaches its end (not a sub-flow's) and the owner has post-chat feedback on (`csatConfig`), the rating card is offered, once per conversation (not again after an agent's end already asked, never for a blocked visitor); the post-chat redirect waits for it. It opens at once (the web draws it 1.5 s later).
- **Blocked visitor.** A visitor the workspace blocked sees "This conversation has been closed." (mid-chat, or at connect: the visitor id goes with the socket handshake) and can't type or start a new chat. `closedState` says which closed state the chat is in.
- **Ending.** `endSession` leaves the queue (`queue-self-resolve`) when the visitor is still waiting; it never sends `end-chat`, which the server takes only from an agent.

### While you wait

While the visitor waits for a person, the SwiftUI chat (`ChatView`, `ChatViewWithKBSheet`) offers something to do, as the web widget does. Nothing to set up; the cards sit in the conversation and are never saved.

- **Help articles.** 6 seconds into the wait, up to two help-centre articles that match the visitor's last real question ("While you wait, this might help"), when the help centre is on. When the server keeps a queue it sends its own pick (`queue-help`) instead, with **That solved it**: the visitor leaves the queue (`queue-self-resolve` with the article) and sees "You left the queue. Glad that helped." Once the wait is over the card stays as "Articles that might help". An article opens in the help centre (with the help centre off, the team's pick is fetched by id and shown on its own), a page in the browser.
- **Games.** 2.5 seconds after the waiting signal the owner's line ("While you wait - fancy a quick game? 🎮") offers rock paper scissors, tic-tac-toe, a quick quiz, memory match, a reflex test, emoji riddles and a word scramble, set in the dashboard (`waitingGames`). "Not now" or the x stops the offers for the app session; typing "play" or "games" while waiting opens the menu. When a person joins, an unused offer goes and a game under way is saved ("Sam's here!", "Finish my game"). Reduce Motion turns the card's motion off.
- **In code:** `ConferBot.shared.waiting` publishes `helpCard` and `gamesCard` for a custom UI; `solveWait()`, `openHelpItem(_:)` and `interceptPlay(_:)` are the actions. A custom chat that draws the cards calls `waiting.setDrawing(true)` while it is on screen (without it the games aren't offered). The UIKit chat draws them (it hosts `ChatView`, iOS 15+).

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
| `identify(user: ConferBotUser?)` | Set the current user identity; `nil` signs out |
| `startSession(forceNew: Bool = false) async throws` | Start (or reuse a restored) chat session |
| `sendMessage(_ text: String, metadata: [String: AnyCodable]? = nil) async throws` | Send a text message (auto-queued offline) |
| `sendTypingIndicator(isTyping: Bool)` | Send visitor typing status |
| `initiateHandover(message: String? = nil)` | Request a live agent |
| `leaveQueue(_ done: @escaping (Bool) -> Void = { _ in })` | Leave the handover queue (`done(false)` when a person already has the chat) |
| `onWidgetSignal(_ signal: WidgetSignal, _ listener: @escaping (WidgetSignalDetail) -> Void) -> () -> Void` | Listen to `.waitingForHuman`, `.humanJoined`, `.waitOver`; returns the unsubscribe |
| `endSession(clearStorage: Bool = true)` | End the current session (leaves the queue when still waiting) |
| `closedState: LiveEvents.ClosedState?` | The closed chat: `.blocked` (no input, no new chat) or `.ended` (composer off, offer a new chat), else nil |
| `startNewChat()` | "Start a new chat" after an ended chat (not for a blocked visitor) |
| `openEmailTranscript()` / `closeEmailTranscript()` | Show / hide the "Email me this chat" card |
| `emailTranscript(_ email: String, done: @escaping (TranscriptEmailResult) -> Void = { _ in })` | Email the transcript to this address; on success the address is kept as the visitor's |
| `sendAnswerFeedback(agentMessageId: String, feedback: AnswerFeedback)` | A "Helpful?" vote (`helpful`, `reason`, `comment`), kept on the answer and sent as `ai-answer-feedback` |
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
| `handleFileUpload(fileURL: URL, forNodeId: String)` | Answer a file step with a local file (the step uploads it) |
| `answerStep(_ response: Any, forNodeId: String)` | Answer any step with the spec's answer (`FlowStepAnswer`); the visitor's bubble is the step's reply |
| `waitingStep(_ nodeId: String) -> (type: String, data: [String: Any])?` | The waiting step's type and data |
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
| `openHelpArticle(id: String) -> Bool` | Open a help article in the chat's help centre (false while the owner has it off) |

### UI Components

| Type | Description |
|------|-------------|
| `ChatView(enableKnowledgeBase: Bool? = nil)` | Drop-in SwiftUI chat screen; the Help tab follows the owner, `false` hides it |
| `ChatViewWithKBSheet()` | Chat screen with the KB in a sheet instead of a tab |
| `KnowledgeBaseView(articleId: String? = nil)` | Standalone SwiftUI knowledge base browser, optionally opened on one article |
| `MessageBubble(message: any RecordItem, customization: ConferBotCustomization?)` | Individual message bubble for custom layouts |
| `View.conferBotWidget(config: ConferBotFABConfig = ConferBotFABConfig())` | Floating FAB overlay modifier |
| `ConferBotWidgetOverlay(config:content:)` | The FAB overlay as a container view |
| `ChatViewController(enableKnowledgeBase: Bool? = nil)` | UIKit chat screen (used by `present(from:)`): hosts `ChatView` on iOS 15+, the UIKit-drawn chat on iOS 13 / 14 |

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
