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
| #82 | Launcher entrance, attention and idle call (SwiftUI), ported from Android / RN (#73 / #57): the web's Web Animations tracks evaluated as Chrome plays them (`Keyframes`), the 12 entrances as sprites on a stage over the launcher, the 8 attention modes, the 5 idle calls with the blob mascot and its speech bubble; drawn with SwiftUI Canvas through a small SVG renderer (`FxSvg`). All default off / classic; Reduce Motion turns them off; never over an open chat. Entrance once per app session per bot and entrance, the greeting card hidden until the launcher lands, then fading up 150 ms later; attention pauses for the icon's idle / message moments, holds the idle moments and the load ripples while it moves the launcher, and is over for the session once the chat opens; idle call at most twice per session, 3 minutes apart, then 3 days' rest per bot in UserDefaults (`conferbot_idlecall_rest_<botId>`). **RN's Chrome golden passes: 447 cases, 19,275 samples** (max error rotate 0.005 deg, `left` 0.031 px, plane path 0.42 px; the rest under 0.001). | `Core/Customization/Keyframes.swift`, `FxPaint.swift`, `LauncherEntrance.swift`, `LauncherAttention.swift`, `LauncherIdleCall.swift`, `MascotArt.swift`, `LauncherFxControllers.swift`, `Launcher.swift` (settings), `UI/SwiftUI/FxSvg.swift`, `LauncherFxViews.swift`, `ConferBotWidgetView.swift`, `Tests/LauncherFxGoldenTests.swift` (golden in `Tests/Resources/launcherfx-golden.json`, from RN `7e4a2ca`), `Tests/LauncherFxControllersTests.swift` |
| #50, #51, #33, #42, #54 | Help centre: reads the server's payloads (socket `knowledgeBaseData` without bodies, REST `{data: {categories, recentArticles}}`, millisecond dates, populated `category`), fetches a body on open, searches with `query`, follows `enableKnowledgeBase` / `hideRecentArticles` (host `enableKnowledgeBase: false` only hides), opens AI sources and article cards by `articleId`, and opens articles from a topic or Related | `Models/KnowledgeBase.swift`, `Services/KnowledgeBaseService.swift`, `Core/Customization/HelpCentre.swift`, `UI/SwiftUI/ChatView.swift`, `UI/SwiftUI/AgentReplyViews.swift`, `UI/SwiftUI/KnowledgeBase/`, `Tests/HelpCentreTests.swift` (fixtures captured from a local embed-server in `Tests/KnowledgeBaseFixtures.swift`) |
| #21, #22, #23, #24, #25, #34, #36, #57 | Handover lifecycle, ported from RN (#28-#32, #58, #59 there): an AI escalating draws the Connecting line (an idle pause draws nothing) that settles to one of 4 outcomes; the 20s `cb:waiting-for-human` and the other waiting signals (`onWidgetSignal`); the header keeps the bot with Online and the reply time; "Talk to a person" only while nobody is coming or here, gone once tapped; the wait card's Cancel leaves the queue (`queue-self-resolve`, `queue-left`); an AI escalation's max wait plus 30s nudges the server (`handover-timeout`) and the SDK's own "no agents" line is gone; a restart saves the server record and asks `live-chat-state`; `initiate-handover` carries the step's email, sound and assignment settings | `Core/LiveChat/HandoverState.swift`, `HandoverWaiting.swift`, `ReplyTime.swift`, `HandoverLifecycle.swift`, `Core/ConferBot.swift`, `Core/NodeFlowEngine.swift` (`waitAt`, `resumeFrom`, `loadFlow(_:keepingState:)`), `Core/State/ChatState.swift` + `Storage/SessionStorage.swift` (record saved), `Core/Agent/AgentHandover.swift` (`stepSettings`), `UI/SwiftUI/MessageBubble.swift` (centred lines), `ChatView.swift` (header), `LiveChatCards.swift`, `Tests/Handover*Tests.swift`, `Tests/ReplyTimeTests.swift` |
| #26, #27, #28, #29, #30, #31, #45, #52, #53, #64, #67, #68, #69, #70 | Flow nodes: the engine and every step handler run the shared flow-node spec, ported from RN. **156 of 156 fixtures pass** (`Tests/FlowFixtureTests.swift`); none pending. See "Flow nodes" below. | `Core/NodeFlowEngine.swift`, `Core/Flow/*` (values, text, inputs, logic, calendar, control, rich, i18n, context, redact), `Core/Nodes/Handlers/*`, `Core/State/ChatState.swift` (answer variables), `Tests/FlowFixtureDriver.swift` |
| #45, #71, #72, #73 | Flow step views (SwiftUI): every step that waits for the visitor is answerable in the stock chat - rating, opinion scale, slider, date / time, calendar (with slots), file upload, check options, ranking, cards (carousel, product card), matrix, consent, payment, and the OTP / address / signature extras next to the composer. Each sends the spec's answer (`FlowStepAnswer`) through `ConferBot.answerStep`; the old unused `NodeRenderer` (`NodeComponents.swift`) is gone. See "Flow step views" below. | `UI/SwiftUI/FlowStepViews.swift`, `Core/Flow/FlowStepAnswers.swift`, `UI/SwiftUI/ChatView.swift`, `Core/ConferBot.swift` (`answerStep`, `waitingStep`), `Tests/FlowStepViewAnswerTests.swift` |
| #75, #76 | Chat layout (SwiftUI), as the web's `css/polish.css`: a bot message starts at the left edge with its 32pt avatar in a fixed column on the bubble's bottom line (the column stays when the avatar is hidden), so bubbles, the typing dots and the step cards under them (40pt in) line up; the visitor's ends at the right edge, 48pt clear of the left; system lines stay centred. The composer is one line and grows with the text to five, then scrolls (`TextField(axis: .vertical)` from iOS 16, a `TextEditor` sized by a hidden copy of its text on iOS 15); clearing it after a send no longer turns the typing signal back on (#77). | `UI/SwiftUI/MessageBubble.swift`, `UI/SwiftUI/Components/ComposerField.swift`, `ChatBottomBar.swift`, `ChatInput.swift`, `ChatView.swift` |
| #74 | Flow steps in the UIKit chat: `ChatViewController` draws the waiting step under the messages with the SwiftUI `FlowStepView` in a table cell (`UIHostingConfiguration` from iOS 16, a hosting controller on iOS 15), so every step the SwiftUI chat answers is answered the same way (`answerStep` / the pills); the composer sends through `submitText` (a typed question takes it as its answer, a refused one stays in the box with the reason over it). Step answers are drawn as the visitor's, answered pills as the options with the pick ticked; typing dots also show while the bot works on a step. | `UI/UIKit/ChatViewController.swift`, `ChatInputView.swift`, `MessageCell.swift` |
| #44 | Device language: every response record carries `visitorInsights: {v: 1, language: {browser}}` (the phone's preferred language, BCP 47 "de-DE"), so the AI answers short messages in it | `Core/State/DeviceLanguage.swift`, `ChatState.buildResponseData`, `Tests/DeviceLanguageTests.swift` |
| #43 | "Helpful?": a No is sent at once; reasons, an optional comment, "Talk to a person" (only while nobody is coming or here), "Ask another way"; the rated line's thumbs change the vote; only the newest unrated answer asks; the vote is kept on the message and the answer's record entry | `Core/Agent/AnswerFeedback.swift` (`HelpfulRow`), `ConferBot.sendAnswerFeedback(agentMessageId:feedback:)`, `UI/SwiftUI/AgentReplyViews.swift`, `Tests/AnswerFeedbackTests.swift` |
| #41 | Back in the queue (`live-chat-requeued`): "Connecting you to another agent..." / "Connecting you to <team>...", the agent cleared, a flow at its handover step waits again. `live-chat-transferred` kept in the record, not drawn. `isRepeatJoin` / `afterAI` were already in the handover port | `Core/LiveChat/LiveEvents.swift`, `HandoverLifecycle.onRequeued` / `onTransferred`, `Tests/LiveEventsTests.swift` |
| #40 | Blocked visitor (`visitor-blocked`, or `connect_error` `visitor_blocked` at the handshake, which now carries the visitor id in query and auth): "This conversation has been closed.", no input, no menu, no new chat. The same `chat-ended` again draws nothing and opens no second rating; each end has its own record id. Once a chat has ended with nothing going on: composer off ("Chat ended") and "Start a new chat" | `LiveEvents.swift` (`closedState`), `Services/SocketClient.swift`, `ConferBot` (`applyVisitorBlock`, `closedState`, `startNewChat`), `LiveChatExtras.block`, `LiveChatCards.swift` (`ClosedChatCard`), `ChatView.swift`, UIKit `ChatViewController` / `ChatInputView` |
| #49 | Markdown as the web's `agentHtml.ts`: tables (sideways scroll), h3-h6 (# and ## as 4), quotes, code blocks, strikethrough, also from a person's HTML; "That took too long. Try again, or ask for a human." after 45s with no AI reply (on screen only; never after a reply, the AI leaving or the end); `isFallback` replies italic at 85% | `Utils/ChatMarkdown.swift`, `AgentReplyViews.swift` (`ChatMarkdownText`), `AgentBot.swift` (`replyTimeoutNotice`), `Tests/ChatMarkdownTests.swift` |
| #39 | "Email me this chat" in the chat menu: one card (known email filled in), `POST {mobile base}/chat/transcript-email` `{chatSessionId, email}` with the SDK's headers (bot from `X-Bot-ID`); the server's reason on a 400 / 429; "Sent! Check your inbox at ..."; the address kept as the visitor's and the record sent | `Core/LiveChat/EmailTranscript.swift`, `APIClient.sendTranscriptEmail`, `LiveChatExtras.emailTranscript`, `LiveChatCards.swift` (`EmailTranscriptCard`), `Tests/EmailTranscriptTests.swift` (URLProtocol stub, nothing mailed) |
| #59 | `endSession` no longer sends `end-chat` (the server refuses it from a visitor); still waiting, it leaves the queue (`queue-self-resolve`). The handover step's `endChat` leaves the queue; its `surveySubmit` sends the rating as `submit-chat-rating` (`LiveChat.surveyRatingPayload`) | `ConferBot.endSession`, `IntegrationNodeHandlers.swift` (`HumanHandoverNodeHandler`), `LiveChat.swift` |
| #66 | After the agent ends the chat the flow moves to the handover step's next step, asking the step's post-chat survey questions first (web `enablePostChatSurveyQuestions`), also for a chat restored while live (the engine stands on the handover step, `standAt`) | `NodeFlowEngine.handoverEnded` / `standAt`, `HumanHandoverNodeHandler` (`ended`), `HandoverLifecycle` restore |
| #65 | A restored bot message keeps its avatar and bubble style: the bubble takes the bot's look when it is made (it was read once and never redrawn when the settings arrived after a restore), and a bot message's node data (image, answered pills) is saved with it (the encoder mixed a keyed and a single-value container) | `UI/SwiftUI/MessageBubble.swift`, `Models/Message.swift`, `Tests/RestoredMessagesTests.swift` |
| #78 | `SocketClient.connect()` from two threads at once crashed (each tore down the other's manager): serialized | `Services/SocketClient.swift` |
| #19 | Socket fixes found while testing the greeting: listeners added before `connect()` were dropped (the bot's settings never arrived), and `emit` sent its items as one array (`get-chatbot-data` got `[{botId}]`) | `Services/SocketClient.swift` |

## Left in this SDK

1. The rest of the list below.
2. **UIKit gaps:** UIKit lags SwiftUI (initials avatar, typing styles; no launcher, so no greeting card). Audit it against the SwiftUI chat.
3. **Greeting card leftovers:** the plain `card` style does not take a widget theme's tokens yet (RN doesn't either); the agent's initials avatar and reply field (proactive agent message), mascots (`mascotInGreeting`) and the exit/collapse animations are not drawn; the word fade-up is opacity only (no rise or blur); chips wrap from iOS 16 and stack one per line on iOS 15. Fonts are the phone's nearest (Noteworthy, Marker Felt, Georgia, Courier New); nothing is bundled.
4. **Help centre leftovers:** search uses REST only (the web also searches over the socket's `search-kb-articles` and merges its own title matches); bodies are fetched over REST, not `get-kb-article`. Recent articles sit at the top of the help centre, as there is no home screen yet. UIKit has no help centre.
5. **Handover leftovers:** the smart-wait help card while queued (`queue-help`, "That solved it") is not drawn (#58). UIKit has the wait card's Cancel, the lines and the bot-name title, but no status line under the title (no reply time). The handover step's `endChat` / `surveySubmit` actions are handled (#59) but no stock view sends them (the web has no visitor end-chat button either; the post-chat survey questions are typed in the composer).
6. **Live chat extras leftovers (#39-#44, #49):** "Ask another way" settles the Helpful row but doesn't focus the composer (`ChatBottomBar` has no focus binding). A blocked visitor refused at the handshake keeps the host header's "Connecting..." (the bot's settings never arrive). `ChatViewWithKBSheet` doesn't turn its composer off for the closed chat. UIKit bubbles are still plain text, so tables / headings aren't drawn there.
7. **Flow step views:** both chats answer every step (UIKit hosts the SwiftUI `FlowStepView`, #74). UIKit needs iOS 15 for the step views (on iOS 13 / 14 only typed steps can be answered). UIKit's own bubbles are still plain text (no formatting, images or files drawn; answered pills are a line of labels), and its bot rows don't follow the SwiftUI row layout (#75).
   Leftovers in the step views: the image-choice step is drawn as label pills (no images); the calendar can't grey out closed or fully booked days in the system picker (a closed day says so under it); the address step has no "use my location"; signatures draw in one ink (the step's `penColor` is not read); the owner's font family is not applied (#46).
8. **Launcher effects leftovers (#82):** filters (brightness, glows, blur) are left out, as in RN and Android; the mascot is always the classic blob (mascots feature); UIKit has no launcher, so none of it. The bounce's shadow, the mascot and the entrance sprites are drawn on a full-screen layer over the host's content (no hit testing).
9. `initialize(...)` takes no user. Only `identify(user:)` sets the visitor context. Consider an optional `user:` parameter, as Android has.

## How to test

- **Linux (no Mac needed):**
  - Build and test the core in `swift:5.10-jammy` docker, with `#if canImport(FoundationNetworking)` imports and the UI folders left out.
  - The 28 tests in RN's `scripts/parity/ios-linux-baseline-fails.txt` already fail on Linux; only failures outside that list matter.
  - One run segfaulted (signal 11) partway through and passed on the rerun, so rerun once before investigating a crash.
- **Mac with Xcode (simulator):**
  - Flow fixtures alone: add `-only-testing:ConferbotTests/FlowFixtureTests`. If the destination by name isn't found (an older runtime), use `id=<udid>` from `xcrun simctl list devices`.
  - Tests: `xcodebuild test -scheme Conferbot -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` from the repo root. `swift test` does not work (the package is iOS only). On 2026-10-16 (iOS 18.4 simulator) 12-13 tests fail on `main`, all outside the flow work: FileUploadService (1), KnowledgeBaseService (2), OfflineManager (7), SocketClient (2), and ChatAnalytics `testFinalizeChatAnalytics_returnsAfterAStart` now and then; crashes restart the run a few times (OfflineManager's `testQueuedMessageCount_publishesChanges` fulfils its expectation twice). After the live chat extras batch (#39-#44, #49, #59, #65, #66) the same set fails, no new ones (a run's crash can hide a few of the OfflineManager ones).
  - Agent side for a live check: a temp bot in the local DB (copy a bot, give it `version: "v2"` or the server converts its elements as x6), then a node socket.io client with a dashboard JWT plays the agent: `accept-handover`, `end-chat`, `block-visitor` (`duration` "24h" / "7d" / "permanent"). Delete the bot and its responses, tickets and `visitorblocks` afterwards.
  - Example app: `Example/SwiftUI` is a SwiftPM executable, not an Xcode app. Build it with `xcodebuild build -scheme ConferbotExample -destination ...` from `Example/SwiftUI`, copy the `ConferbotExample` binary from `Build/Products/Debug-iphonesimulator` into a `ConferbotExample.app` folder with `Sources/Info.plist` (`$(EXECUTABLE_NAME)` replaced, ATS `NSAllowsLocalNetworking` on for a local server), `codesign -s -` it, then `xcrun simctl install booted` and `xcrun simctl launch booted com.conferbot.example`.
  - Against a local embed-server: pass `ConferBotConfig(apiBaseURL: "http://localhost:8001/api/v1/mobile", socketURL: "http://localhost:8001")` and a local bot id in `ExampleApp.swift` (don't commit it). `xcrun simctl io booted screenshot <file>` for screenshots.
  - Steps that reach real services (OTP mail, AI, KB, geocoding, Stripe, media storage) go through `URLSession.shared` to `/api/v1/bot/:id/<path>`: a `URLProtocol` registered in the Example answers them without sending anything. To walk a flow without tapping, a temporary hook can watch `ConferBot.shared.$currentUIState` and answer each step after a pause with `FlowStepAnswer` / `submitText`, while a host script screenshots on each step (`simctl launch --console-pty` prints the hook's lines). Revert the Example afterwards.
  - The UIKit chat in the Example: a temporary `UIViewControllerRepresentable` wrapping `UINavigationController(rootViewController: ChatViewController())` as the root view. The hook can type into it through the real composer (find `ChatInputView`'s `UITextView`, set the text, call `textViewDidChange`, then `sendActions(for: .touchUpInside)` on its button). On a loaded Mac the host-side screenshot loop falls behind; the hook can shoot the app's own window instead (`drawHierarchy` into a PNG written straight to a host path given in `SIMCTL_CHILD_*`, as the simulator shares the Mac's file system).
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
| Launcher entrance / attention / idle call | done | done | done | done |
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

### Flow step views (SwiftUI)

Done in iOS (2026-10-16), #45. `ChatView` (and `ChatViewWithKBSheet`) draw the waiting step with `FlowStepView` (`UI/SwiftUI/FlowStepViews.swift`), picked from `currentUIState` and the step's type (`ConferBot.waitingStep`): a `.opinionScale` of a slider-node is a slider, a `.multiChoice` of a ranking-node a list to reorder, a `.calendar` of a datetime-node the date / time picker, and so on.

| Step | View | Answer sent (`FlowStepAnswer`) |
|---|---|---|
| rating-choice, user-rating | 1...n stars or the five faces; a tap answers | `["value": n]` |
| opinion-scale | from...to number buttons, end labels | `["value": n]` |
| slider | slider on the step grid, unit, Send | `["value": n]` |
| datetime | system picker (date / time / both) inside min / max date, Send | `["value": "2026-10-19" \| "14:30" \| "2026-10-19T14:30"]` |
| calendar | month picker from today (past / excluded days say so); with time selection the day's free slots on the bot's clock, shown in the visitor's time | `["date": "YYYY-MM-DD", "slot": "HH:MM"?]` |
| ask-file, user-input (file) | system document picker (the step's types), size hint, Skip when optional; the file is copied locally and the step uploads it | `["file": [uri, name, type, size]]`, `["skip": true]` |
| n-check-options | tick any, Submit | `["buttonIds": [ids]]` |
| ranking | items with up / down, Submit | `["order": [ids]]` |
| carousel, product-card | cards side by side; a path button answers, a link opens, Continue when there's no path button | `["buttonId", "cardId"]`, `["action": "continue"]` |
| matrix | each row with its columns (radio or check), Submit | `["cells": [row: col \| [cols]]]` |
| consent | box with the consent text (links open), Continue | `["agreed": Bool]` |
| payment | Pay now (opens the checkout), I've paid, Cancel | `["action": "open" \| "check" \| "cancel"]` |
| otp | e-mail and code typed in the composer; Resend, Skip (when allowed) | typed text, `["action": "resend" \| "skip"]` |
| address | search (results come back as pills) or typed by hand | `["action": "search", "q"]`, pill `["buttonId": index]`, `["action": "manual", ...]` |
| signature | a box to sign in (PNG), full name when required; typed name in the composer | `["action": "sign", "method": "drawn", "image", ...]`, typed text |
| choices, yes/no, dynamic choices, navigate, quiz, n-select, image choice | the pills, as before | `["buttonId": id]` |

- **Look:** options are filled in the bot's option bubble colour and option text colour with the option radius and font size (as the web's `__chat__choice__bubble`); Send / Submit, stars and picked marks use the accent (header colour). Live choice pills use the option colours too (#71). Nothing animates.
- **The visitor's bubble** is the step's own reply line ("⭐⭐⭐⭐", "Oct 19, 2026", "Signed: ..."): `answerStep` mirrors the step's user lines (`ChatState.onUserEntryAppended`) until the flow moves on, so a refused answer shows none; the reason comes as a bot line. Pills and the composer still add their own bubble.
- **Tests:** `Tests/FlowStepViewAnswerTests.swift` plays every visitor action of the fixtures for these steps (and the QA - All Nodes tour) as the views send them - the same `FlowStepAnswer` builders and view state (`RankingOrder`, `MatrixPicks`), the composer for typed answers, the pills for picks - and requires the web's whole outcome (ports, variables, answers, end). Only `signEmpty` is played by the driver (Sign is off until something is drawn); a drawn PNG is checked separately.
- **Also fixed:** `handleFileUpload` sent a `file://` path the step saved as the uploaded URL (#72); `handleDateSelection` broke time-only steps and recorded calendar slots twice (#73).
- **UIKit (#74):** `ChatViewController` puts the same `FlowStepView` in the table's step section (messages, step, typing dots), redrawn in place while the step is the same (an OTP moving to its code) and re-measured when its content changes size; plain typed questions draw nothing there and go through the composer's `submitText`; the handover wait card stays in the live strip.
- **Checked on the simulator (2026-10-16)** against a local embed-server with "QA - All Nodes" (OTP, address, matrix, AI extract / route, KB, signature), "Answer Vars Test" (rating, scale, calendar, file, check options, the ask-* steps) and the fixtures' slider, ranking, carousel, product card, consent, datetime, user-rating, dynamic-choices and payment steps loaded with `loadFlow`; every bot-API call that reaches a real service (otp, ai, kb, geo, pay, media) was answered by a temporary `URLProtocol` stub in the Example, which was then reverted.

### Porting the live chat extras (from RN #46-#48, #50, #51, #56; iOS #39-#44, #49)

Done in iOS (2026-10-16). Each RN pure file has its Swift twin and test: `deviceLanguage.ts` -> `DeviceLanguage.swift`, `answerFeedback.ts` -> `AnswerFeedback.swift` (`HelpfulRow`), `liveEvents.ts` -> `LiveEvents.swift`, `emailTranscript.ts` -> `EmailTranscript.swift`, `chatMarkdown.ts` -> `ChatMarkdown.swift`. What iOS did its own way:

- **Where the state lives:** blocked and "Email me this chat" are on `LiveChatExtras` (`blocked`, `emailTranscriptOpen`, `emailTranscriptSentTo`), so both chats (UIKit through `LiveChatStrip`) draw the cards. `ConferBot.closedState` is computed from the server record, `liveChat.blocked`, the waiting step and the live agent.
- **The rating card once per end:** `LiveChatExtras` no longer opens it on its own `chat-ended` listener; ConferBot calls `liveChat.chatEnded()` after the same-end check, so the two listeners can't race.
- **The handshake:** `SocketClient.visitorId` (the stored session's visitor) goes in the connect params and the `connect(withPayload:)` auth; socket.io-client-swift reports the refusal as an `error` event with `[{message: "visitor_blocked"}]`, then the client stops reconnecting and calls `onBlocked`.
- **The end of a live chat (#66):** `NodeFlowEngine.handoverEnded()` sends the handover step `["action": "ended"]`; the step asks the web's post-chat survey questions (typed, email / phone checked, `post-chat-survey-question` and `-response` entries) and then moves on. A chat restored while live is put on its handover step with nothing drawn (`standAt`), so the end carries on there too; ended while the app was closed, the restore runs the same.
- **Markdown views:** SwiftUI `ChatMarkdownText` draws the new blocks; a muted fallback reply is italic through the attributed string (`View.italic` is iOS 16).

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
