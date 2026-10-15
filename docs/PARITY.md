# Web widget parity: iOS

This file tracks how far this SDK matches the web widget: what's done, what's left, and how to pick the work up. Features are built in the React Native SDK first; its `docs/PARITY.md` and `src/core/*.ts` are the reference.

UIs:

- **SwiftUI:** `UI/SwiftUI/`. `ConferBotWidgetView` is the floating launcher.
- **UIKit:** `UI/UIKit/ChatViewController`, no launcher.

## Done in this SDK

| Issue | Feature | Key files |
|---|---|---|
| #9 | iOS 14/15 compile fixes, SVG path parser | `Utils/SVGPathParser.swift` |
| #10 | Live chat max wait / handover timeout | `Core/LiveChat/` |
| #11, #12 | Customization basics, SwiftUI + UIKit | `Core/Customization/Customizations.swift`, `UI/SwiftUI/CustomizationViews.swift` |
| #13 | Chat background | `ChatBackground.swift`, `UI/SwiftUI/ChatBackgroundView.swift` |
| #14 | 27 themes, light/dark/auto, palette | `WidgetTheme.swift`, `WidgetThemesData.swift` (generated) |
| #15 | Launcher resolver | `Launcher.swift`, `UI/SwiftUI/ConferBotWidgetView.swift` |
| #16 | 56 icons (SwiftUI Canvas) | `LauncherIcons.swift`, `UI/SwiftUI/LauncherIconView.swift` |
| #17 | Launcher motion, passes the golden test | `LauncherMotion.swift`, `LauncherMotionData.swift` |
| #18 | User as `visitorContext` + identity hash | `Models/Configuration.swift` (`toVisitorContext`), `Core/State/ChatState.swift`, `Core/ConferBot.swift` (`identify`) |
| #20 | Greeting card: rules, smart greetings, frequency, per-bot memory, 11 styles and their reveals (SwiftUI), in place of the plain tooltip | `Core/Customization/Greeting.swift`, `GreetingState.swift`, `UI/SwiftUI/GreetingCardView.swift`, `ConferBotWidgetView.swift`, `Tests/GreetingTests.swift` |
| #50, #51, #33, #42, #54 | Help centre: reads the server's payloads (socket `knowledgeBaseData` without bodies, REST `{data: {categories, recentArticles}}`, millisecond dates, populated `category`), fetches a body on open, searches with `query`, follows `enableKnowledgeBase` / `hideRecentArticles` (host `enableKnowledgeBase: false` only hides), opens AI sources and article cards by `articleId`, and opens articles from a topic or Related | `Models/KnowledgeBase.swift`, `Services/KnowledgeBaseService.swift`, `Core/Customization/HelpCentre.swift`, `UI/SwiftUI/ChatView.swift`, `UI/SwiftUI/AgentReplyViews.swift`, `UI/SwiftUI/KnowledgeBase/`, `Tests/HelpCentreTests.swift` (fixtures captured from a local embed-server in `Tests/KnowledgeBaseFixtures.swift`) |
| #21, #22, #23, #24, #25, #34, #36, #57 | Handover lifecycle, ported from RN (#28-#32, #58, #59 there): an AI escalating draws the Connecting line (an idle pause draws nothing) that settles to one of 4 outcomes; the 20s `cb:waiting-for-human` and the other waiting signals (`onWidgetSignal`); the header keeps the bot with Online and the reply time; "Talk to a person" only while nobody is coming or here, gone once tapped; the wait card's Cancel leaves the queue (`queue-self-resolve`, `queue-left`); an AI escalation's max wait plus 30s nudges the server (`handover-timeout`) and the SDK's own "no agents" line is gone; a restart saves the server record and asks `live-chat-state`; `initiate-handover` carries the step's email, sound and assignment settings | `Core/LiveChat/HandoverState.swift`, `HandoverWaiting.swift`, `ReplyTime.swift`, `HandoverLifecycle.swift`, `Core/ConferBot.swift`, `Core/NodeFlowEngine.swift` (`waitAt`, `resumeFrom`, `loadFlow(_:keepingState:)`), `Core/State/ChatState.swift` + `Storage/SessionStorage.swift` (record saved), `Core/Agent/AgentHandover.swift` (`stepSettings`), `UI/SwiftUI/MessageBubble.swift` (centred lines), `ChatView.swift` (header), `LiveChatCards.swift`, `Tests/Handover*Tests.swift`, `Tests/ReplyTimeTests.swift` |
| #26, #27, #28, #29, #30, #31, #45, #52, #53, #64, #67, #68, #69, #70 | Flow nodes: the engine and every step handler run the shared flow-node spec, ported from RN. **156 of 156 fixtures pass** (`Tests/FlowFixtureTests.swift`); none pending. See "Flow nodes" below. | `Core/NodeFlowEngine.swift`, `Core/Flow/*` (values, text, inputs, logic, calendar, control, rich, i18n, context, redact), `Core/Nodes/Handlers/*`, `Core/State/ChatState.swift` (answer variables), `Tests/FlowFixtureDriver.swift` |
| #19 | Socket fixes found while testing the greeting: listeners added before `connect()` were dropped (the bot's settings never arrived), and `emit` sent its items as one array (`get-chatbot-data` got `[{botId}]`) | `Services/SocketClient.swift` |

## Left in this SDK

1. The rest of the list below.
2. **UIKit gaps:** UIKit lags SwiftUI (initials avatar, typing styles; no launcher, so no greeting card). Audit it against the SwiftUI chat.
3. **Greeting card leftovers:** the plain `card` style does not take a widget theme's tokens yet (RN doesn't either); the agent's initials avatar and reply field (proactive agent message), mascots (`mascotInGreeting`) and the exit/collapse animations are not drawn; the word fade-up is opacity only (no rise or blur); chips wrap from iOS 16 and stack one per line on iOS 15. Fonts are the phone's nearest (Noteworthy, Marker Felt, Georgia, Courier New); nothing is bundled.
4. **Help centre leftovers:** search uses REST only (the web also searches over the socket's `search-kb-articles` and merges its own title matches); bodies are fetched over REST, not `get-kb-article`. Recent articles sit at the top of the help centre, as there is no home screen yet. UIKit has no help centre.
5. **Handover leftovers:** the smart-wait help card while queued (`queue-help`, "That solved it") is not drawn (#58). UIKit has the wait card's Cancel, the lines and the bot-name title, but no status line under the title (no reply time). The handover node's own survey and end-chat actions are not drawn on iOS (RN's `submit-chat-rating` survey and `queue-self-resolve` on end chat have nothing to port to). `endSession` still sends `end-chat`, which the server refuses from a visitor (harmless).
6. **Flow node UI (#45):** the engine and handlers run every step; the chat draws the button steps as pills (choices, yes/no, consent, payment, navigate, dynamic choices, quiz) and the composer steps (ask-*, OTP, AI, KB, signature by typed name, address as the street line). Not drawn yet: the rating, opinion scale / slider, calendar / datetime, file upload, multi-choice (n-check-options, ranking), cards (carousel, product) and matrix (`.rich`) states, so a visitor can't answer those in the stock ChatView; a custom UI answers them through `ConferBot.handleNodeInput` / `handleButtonClick` / `handleMultipleChoiceSelection`.
7. `initialize(...)` takes no user. Only `identify(user:)` sets the visitor context. Consider an optional `user:` parameter, as Android has.

## How to test

- **Linux (no Mac needed):**
  - Build and test the core in `swift:5.10-jammy` docker, with `#if canImport(FoundationNetworking)` imports and the UI folders left out.
  - The 28 tests in RN's `scripts/parity/ios-linux-baseline-fails.txt` already fail on Linux; only failures outside that list matter.
  - One run segfaulted (signal 11) partway through and passed on the rerun, so rerun once before investigating a crash.
- **Mac with Xcode (simulator):**
  - Flow fixtures alone: add `-only-testing:ConferbotTests/FlowFixtureTests`. If the destination by name isn't found (an older runtime), use `id=<udid>` from `xcrun simctl list devices`.
  - Tests: `xcodebuild test -scheme Conferbot -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` from the repo root. `swift test` does not work (the package is iOS only). On 2026-10-15 the same 29 tests fail on `main` with and without the greeting work (ChatState, FileUploadService, KnowledgeBaseService, NodeFlowEngine, NodeHandlerRegistry, among others), and one XCTestExpectation "multiple calls to fulfill" crash restarts the run.
  - Example app: `Example/SwiftUI` is a SwiftPM executable, not an Xcode app. Build it with `xcodebuild build -scheme ConferbotExample -destination ...` from `Example/SwiftUI`, copy the `ConferbotExample` binary from `Build/Products/Debug-iphonesimulator` into a `ConferbotExample.app` folder with `Sources/Info.plist` (`$(EXECUTABLE_NAME)` replaced, ATS `NSAllowsLocalNetworking` on for a local server), `codesign -s -` it, then `xcrun simctl install booted` and `xcrun simctl launch booted com.conferbot.example`.
  - Against a local embed-server: pass `ConferBotConfig(apiBaseURL: "http://localhost:8001/api/v1/mobile", socketURL: "http://localhost:8001")` and a local bot id in `ExampleApp.swift` (don't commit it). `xcrun simctl io booted screenshot <file>` for screenshots.
- **UI changes without a Mac:**
  - Push to a `build/<name>` branch and wait for the "iOS build" GitHub Actions check (`.github/workflows/ios-build.yml`, macOS simulator build).
  - Then fast-forward `main` and delete the branch.

## The goal

Every web widget feature works the same in the 4 mobile SDKs: customization, launcher, greeting and the live chat / agent features. The web widget (`conferbot-widget/src`) is the reference. Each feature is built and checked against the web in React Native first, then ported to Android, iOS and Flutter. The web source file it came from is named in a comment.

## Status across the SDKs (2026-10-15)

| Feature | RN | Android | iOS | Flutter |
|---|---|---|---|---|
| Customization basics (header, bubbles, avatar, typing styles, composer, footer) | done | done | done | done |
| Chat background (solid, gradient, image + mask, patterns) | done | done | done | done |
| 27 widget themes, light/dark/auto, theme palette | done | done | done | done |
| Launcher shape, size, offsets, gradient, image, avatar, label, glow | done | done | done | done |
| 56 launcher icons, drawn from the widget SVGs | done | done | done | done |
| Launcher motion (idle moments, message reaction, ripple) | done | done | done | done |
| Signed-in user as `visitorContext` + identity hash | done | done | done | done |
| Greeting card (rules, frequency, 11 styles) | done | logic done, UI on a branch | done | todo |
| Launcher entrance / attention / idle call | todo | todo | todo | todo |
| Home screen | todo | todo | todo | todo |
| Mascots (incl. `mascotInGreeting`) | todo | todo | todo | todo |
| `widgetLanguage` (i18n) | todo | todo | todo | todo |
| Message sounds | todo | todo | todo | todo |
| Celebrations / reactions | todo | todo | todo | todo |
| Reply-time wording (header) | done | todo | done | todo |
| Handover lifecycle (Connecting line, outcomes, signals, leave queue, restore) | done | todo | done | todo |
| Flow nodes: shared spec, 156 fixtures (RN `scripts/parity/flows/`) | 156/156 | todo | 156/156 | todo |

Live chat / agent features (handover, queue card, receipts, rating, files, prefill, max-wait timeout, agent bot replies, suggestion chips) are done in all 4.

Each SDK repo has its own `docs/PARITY.md`. The React Native one also covers the generators in `scripts/parity/` and the greeting card spec in `docs/greeting-card-native-spec.md`.

### Web sources for the features still to do

All paths are under `conferbot-widget/src/`.

- **Launcher entrance / attention / idle call (all default off):**
  - `ts/launcher/entrance.ts`, setting `launcherEntrance`: classic default; lightning, rocket, portal, ufo, drop, confetti, coin.
  - `ts/launcher/attention.ts`, setting `launcherAttention`: off, pulse, wobble, bounce, wave, float, shine, heartbeat, orbit.
  - `ts/launcher/idleCall.ts`, setting `launcherIdleCall`: off, psst, peek, wave, knock, tap; delay 12.
  - The CSS is in `css/`.
- **Home screen:** `ts/home/` (homeCopy, askBox, trust, pageAware, visitorMemory).
- **Mascots:** `ts/home/mascotMotion.ts`, `ts/launcher/launcherStyle.ts`, `ts/launcher/art3d.ts`, `ts/visibility/greeting.ts`. The `mascot` typing style is accepted but not drawn yet.
- **i18n:** `ts/i18n.ts` + `ts/i18n/{en,de,es,fr,nl}.ts`.
- **Sounds:** `ts/chat/messageSound.ts`.
- **Celebrations:** `ts/chat/delight/` (celebrate, reactions, rules) and `ts/chat/ratingFx.ts`.
- **Reply time:** `ts/chat/replyTime.ts`, `replyTimeView.ts`, `headerPresence.ts`.

### Flow nodes (the shared spec)

Done in iOS (2026-10-16): `FlowFixtureTests` runs all 156 fixtures of conferbot-react-native `scripts/parity/flows` (copied to `Tests/Resources/flows` by `scripts/sync-flow-fixtures.sh`, from RN `eb7b2f1`; the revision is in `Tests/Resources/flows/REVISION`) through the real `NodeFlowEngine` and `registerAllHandlers()`. 156 pass, none pending. The driver (`Tests/FlowFixtureDriver.swift`) is RN's `flowDriver.ts`:

- **Virtual clock:** the engine takes a `FlowClock` (`Config.clock`); the driver's runs every timeout in time order and skips intervals while settling (a countdown or a status poll), as RN's. Everything in the flow runs on the main actor, so "settled" is a few `Task.yield()`s.
- **Server:** the engine's `FlowTransport` (`Config.transport`) gets the real `URLRequest`s; the fake answers from `server.http` by the path after `/api/v1/bot/:id/` (a list: call n gets item n; missing `media` returns a URL; anything else missing is a network error). The fake `FlowSocket` answers `execute-integration` (50 ms) and `initiate-handover` (no agents after 1000 ms) and leaves `response-record` and `join-chat-room-visitor` out of `emits`.
- **Compared** as RN: path (node, type, via), ports, variables (key + value; `consent_at` / `signature_at` as timestamps), end, error nodes, answers, rendered plain text, emits, unsupported, http (path + body keys), flowVariables, and the pace between shown steps (+-50 ms) except RN's `timingSkip` (the web cards' own focus / debounce / animation timers).
- **What changed in the SDK:** `NodeHandler` gained `handleResponse` and the engine hands each step a `FlowContext` (bot API, socket, clock, edges) under `node["ctx"]`; `NodeResult` gained `.port`, `.invalid`, `.end`; `ChatState` keeps the web's answer variables (`registerAnswerVariable`, `setAnswerVariable`, `saveVariableByName`, `lookupVariable`; sent as `answerVariables` `[{nodeId, key, value}]`, saved for a restore) and masks card numbers, ids and passwords unless `redactSensitive` is false; `resolveVariables` fills as the web (unknown is blank, gaps tidied). The old guessed-key handlers and `MissingNodeHandlers.swift` are gone. GPT, AI route / extract, KB, OTP, address and payment go through the bot server; webhooks still run from the device in the background (RN does the same; the spec marks them web-only).
- **App glue:** `ConferBot` fans `integration-result`, `payment-status` and `no-agents-available` out to the steps (`FlowEventHub`); the handover step now says the fallback itself. Bot bubbles draw the owner's HTML formatted (#64).

### Porting the handover lifecycle (from RN, #28-#32, #58, #59)

Done in iOS (2026-10-15). RN's notes (its `docs/PARITY.md`) hold for Android and Flutter; what iOS did differently:

- **The record is the server record** (`ChatState.serverRecord`): `HandoverState` reads `[[String: Any]]` entries. The on-screen lines are `AgentLeftMessageRecord` (`handover`, `settled`) and `AgentJoinedMessageRecord` (`afterAI`), with the same ids as their server entries, so a restore can copy the annotations across.
- **Saving the record (#22):** `StoredChatState` now carries `serverRecordJSON` and `currentNodeId`; `ConferBot.saveChatState` writes it and `restoreChatState` reads it back. Without them a restart had nothing to read the handover from. A chat ended is recorded as `agent-chat-ended` (it was a `system-message`).
- **`HandoverLifecycle`** takes closures (`Hooks`), not the socket, so `HandoverLifecycleTests` drives it with a fake socket and clock (`FakeClock` in `HandoverWaitingTests.swift`). ConferBot calls it from its own `agent-accepted`, `agent-left`, `no-agents-available`, `chat-ended` and `ai-agent-inactive-close` handlers, in that order before drawing anything; it listens to `handover-waiting` and `queue-left` itself.
- **Restore:** the flow is loaded with `loadFlow(_:keepingState: true)` (the old `loadFlow` reset the answers), then `resumeRestored`. On connect a restored session joins its room again: the join sent from `initialize` went out before the socket was connected.
- **The AI escalation's nudge** (web `armAIEscalationNudge`) is armed on the Connecting line with the step's max wait (the flow's handover step, or an agent bot's shell step) and cleared by every answer from the server.

### Porting the greeting card (from RN)

Done in iOS (2026-10-15): `Greeting.swift` (pure, with `GreetingTests`), `GreetingState.swift` (`GreetingStore`, per-bot JSON in UserDefaults), `GreetingCardView.swift` (the 11 styles, reveals and `GreetingController`). The notes below stay for Flutter.

- **`src/core/greeting.ts`** is pure and tested. Port it with its tests.
  - `decideGreeting(c, facts)` picks the card:
    - The app counts as path "/". Rules for given pages, countries, sources, page attributes or browser-only behaviour never apply.
    - The rest are checked for audience (new/returning, signed in), schedule, `minVisits`, chatted, and their own limits (`maxShows` within `windowDays`, `quietDaysAfterDismiss`). They are ranked by priority, then by order.
    - A "show nothing" rule silences the card. A smart rule (sgpric, sgads0, sgretn, sgengd, sgcust, sgchko) gives way when the owner's own talking rule applies.
    - The legacy `proactivePrompt*` teaser has a delay of 8. Text is capped at 140 characters.
  - `frequencyAllows`:
    - page: 300s rest after a close or after the chat opens.
    - session: once per app session.
    - visitor: once every N days.
- **`FloatingWidget/useGreeting.ts`** holds the state, stored per bot as `{visits, chatted, shows, dismissed, closedAt, shownAt, last}`.
  - Visits are counted once per app session.
  - The X calls `dismiss()`, which records a dismissal of that rule. Tapping the card calls `closeForNow()`, which only rests it.
  - Opening the chat sets `chatted` and rests the card.
  - Signed in means the visitor context has an id or email.
- **`FloatingWidget/GreetingCard.tsx`** draws the 11 styles: card, note, imessage (default), postcard, sticky, typewriter, glass, notification, neon, voice, aurora. The geometry, colours, reveal timings and native font fallbacks are in RN's `docs/greeting-card-native-spec.md`.

## Conventions

- One commit per file: `feat|fix|style|test|docs|ci(scope): ... (#issue)`.
- One GitHub issue per bug, in this repo. Close it with the commit hashes.
- Update the README in the same batch.
