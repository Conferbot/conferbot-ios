# Changelog

All notable changes to the Conferbot iOS SDK are documented in this file.
This is the only changelog for the SDK (the old copy in `docs/` was merged in here).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
  Proposed next version: 2.0.0. The breaking changes below (the SwiftUI views
  need iOS 15, the removed handler classes and node views, NodeResult's new
  cases, the UIKit chat's removed conformances) need a major bump under semver.
  Bump s.version in Conferbot.podspec when cutting the release and tag the
  same version (SwiftPM and the podspec's :tag both read the git tag).
-->

## [Unreleased]

Everything since 1.0.0: the SDK now behaves like the Conferbot web widget, from the
launcher to the AI agent, the handover and the help centre. `docs/PARITY.md` tracks each
feature with its issue and its files.

The 1.0.0 tag does not compile (duplicate declarations, missing members, SwiftUI views
marked iOS 14 that use iOS 15 APIs; #1). Apps that pinned 1.0.0 should move to the next
release. The changes below are listed against 1.0.0's source.

### Breaking changes & migration

1. **`ChatViewController` hosts the SwiftUI chat on iOS 15+.** `ChatViewController()`,
   `ConferBot.shared.present(from:)` and pushing the controller are unchanged, and
   `ChatViewController(enableKnowledgeBase: Bool? = nil)` is new. On iOS 15 and later the
   controller is a `UIHostingController` child running `ChatView`, so UIKit apps get the
   home screen, help centre, "Your requests", step cards, wait cards and games, formatted
   replies and the chat menu (#96, #56, #81, #84).
   - The navigation bar is **hidden** while the chat is on screen (the chat draws the bot's
     own header with ✕) and put back as it was when the chat goes. The chat no longer sets
     your navigation bar's appearance or bar button items; customise it in the dashboard.
     The interactive swipe-back may not work while the bar is hidden; ✕ pops or dismisses.
   - The `UITableView`, `MessageCell`, `TypingIndicatorCell` and `ChatInputView` are no
     longer what is on screen on iOS 15+. `MessageCell` and `ChatInputView` stay public for
     custom layouts.
   - `ChatViewController`'s `UITableViewDataSource`, `UITableViewDelegate` and
     `ChatInputViewDelegate` conformances (and their public `tableView(_:...)` /
     `chatInputView(_:...)` methods) are gone.
   - **iOS 13 / 14** keep a UIKit-drawn chat (`UIKitChatViewController`, internal) in the
     navigation bar as before: plain-text bubbles, typing dots, the composer, the menu with
     Email me this chat and Sound on / off. Step cards, live chat cards, the help centre,
     home screen, wait cards and requests need iOS 15.
2. **The SwiftUI views need iOS 15** (`@available(iOS 15.0, *)`; they were marked iOS 14
   but use `AsyncImage` and `.task`) (#1).
3. **`ChatView(enableKnowledgeBase: Bool? = nil)`** (was `Bool = true`). The owner's help
   centre setting in the dashboard decides: `nil` (the default) and `true` follow it,
   `false` hides the Help tab even when the owner turned it on. It can no longer turn the
   help centre on against the owner's setting (the server sends no articles then) (#33).
4. **Node handlers** (only for apps that write their own):
   - `NodeHandler.handle(node:state:)` is `@MainActor`, and the protocol has
     `handleResponse(_:node:state:) async -> NodeResult?` (default `nil`: move on along
     the first edge) for the visitor's answer.
   - `NodeResult` has new cases: `.port(String, fallback: String?)` (leave by an exact
     handle), `.invalid(String, uiState: NodeUIState?, inCard: Bool)` (a refused answer;
     the step waits) and `.end`. `NodeUIState` has `.rich(type:data:nodeId:)`. An
     exhaustive `switch` needs the new cases.
   - Removed: `MissingNodeHandlers.swift` and the guessed-key handler classes that
     duplicated the registry (for example `SendMessageHandler`, `AskQuestionHandler`,
     `ButtonsNodeHandler`, `TextInputNodeHandler`), `DisplayHandlerRegistry`,
     `IntegrationHandlerRegistry`, `BaseIntegrationHandler`, `IntegrationNodeHandler`,
     `NodeState`, `NodeHandlerResult`, and the device-side AI handlers (`OpenAIHandler`,
     `ClaudeHandler`, `GeminiHandler`, `GroqHandler`, `PerplexityHandler`,
     `CustomLLMHandler`, `DialogflowHandler`, `GptNodeHandler`). GPT, AI and
     integration steps run on Conferbot's server; the app holds no AI key (#26, #28, #45).
     `NodeHandlerRegistry` registers every step of the shared spec.
   - `InputValidation` in `Utils/ValidationUtils.swift` is now `ValidationKind` (it
     clashed with the node input validation type of the same name) (#1).
5. **The SwiftUI node views are gone** (`NodeComponents.swift`: `NodeRenderer`,
   `NodeRenderState`, `TextInputView`, `SingleChoiceView`, `ButtonsView`, `RatingView`,
   `CalendarPicker`, `PaymentView` and the rest, with their `...State` types and
   `ChatTheme`). The chat draws each waiting step itself (`FlowStepView`). A custom UI
   answers a step with `ConferBot.shared.answerStep(_:forNodeId:)` and `FlowStepAnswer`,
   reading the step from `waitingStep(_:)` (#45).
6. **`identify(user: ConferBotUser?)`** takes an optional. `identify(user: nil)` signs the
   user out: their "Your requests" list goes at once, an answer still on its way for them is
   ignored, greet-by-name texts fall back, and the device's push token is unregistered from
   their conversation. Existing `identify(user:)` calls compile unchanged (#86, #97).
7. **Push.** `registerPushToken(_:)` is deprecated (renamed `setPushToken(_:type:)`) and
   still works. New: `setPushToken(_ deviceToken: Data)`, `setPushToken(_:type:)`,
   `unregisterPush()`. `handlePushNotification(_:open:)` gained `open` (default `true`:
   a tap opens its conversation; `false` only counts it unread), is
   `@discardableResult`, and returns `true` only for a Conferbot push of this bot (1.0.0
   took any `type: "conferbot_message"`). `APIClient.registerPushToken(token:chatSessionId:)`
   is deprecated for `registerPushToken(_ body:)` (#97).
8. **`ChatState.resolveVariables(text:)`** fills `{x}`, `${x}`, `{{x}}`, `${ANSWERS.x}` and
   `$${x}` as the web does, from the answers, then the flow variables, then the visitor's
   details. An unknown, null or empty variable now shows **nothing** (1.0.0 left the
   placeholder in the text). `resolveVariables(html:)` escapes the values for owner HTML.
   `resolveVariablesInDictionary` was removed (#28, #67).
9. **`endSession(clearStorage:)` no longer sends `end-chat`** (the server takes it only
   from an agent). While the visitor waits for a person it leaves the queue instead (#59).
10. **English wording.** The SDK's own words come from the web widget's table, so some
    English texts changed, for example "Related Articles" is "Related articles" and
    "Searching..." is "Searching…". UI tests that match the old English need updating. What
    the owner wrote in the dashboard is shown as written (#89).

### Added

- **Dashboard customisation, as the web widget draws it:** header, bubbles, avatar and
  option corners, the chat background (gradients, image with mask, 13 patterns), all 27
  widget themes with light / dark / auto and the theme palette, in SwiftUI and UIKit
  (#11-#14).
- **The floating launcher (`.conferBotWidget()`):** shapes and styles, all 56 icons and
  their motion, entrance effects (12), attention modes (8), idle call (5), the 27 mascots
  with their moods, and the greeting card with its rules, frequency and 11 styles (#15-#17,
  #20, #82, #88, #47).
- **Flow engine at parity:** the shared flow-node spec's 156 cases pass. Every step the
  dashboard builds runs, with a SwiftUI view for every step that waits for the visitor
  (consent, OTP, address, signature, matrix, ranking, slider, date / time, calendar with
  booked slots, payment, cards); loops and sub-flows; card numbers, ids and passwords
  masked (`redactSensitive`); `answerStep(_:forNodeId:)`, `FlowStepAnswer`, `waitingStep(_:)`
  (#26-#31, #45, #52, #53, #64, #67-#73).
- **AI agent:** formatted replies (tables, headings, quotes, code), sources and article
  cards, "Helpful?" with reasons and comments (`sendAnswerFeedback(agentMessageId:feedback:)`,
  and `sendAnswerFeedback(agentMessageId:helpful:reason:)`), the 45 s "took too long"
  notice, question chips, the inactivity close, the phone's language on every record (#4,
  #32, #43, #44, #49, #94).
- **Handover lifecycle:** "Connecting you with the team…" and its outcomes, the header's
  reply time, `leaveQueue(_:)`, the waiting signals (`onWidgetSignal(_:_:)`, `WidgetSignal`),
  back in the queue, transfers, a restored live chat, the max-wait countdown and
  `handover-timeout`, the post-chat survey, `startNewChat()`, `closedState`, a blocked
  visitor's closed chat (#6, #7, #10, #21-#25, #34-#36, #40, #41, #57, #66, #93).
- **While you wait:** help articles 6 s into a wait, the server's pick with "That solved
  it", seven games (`ConferBot.shared.waiting`) (#37, #58, #83).
- **Home screen** (`enableInitialPage`): greeting, "Ask anything", "Talk to us", recent
  articles, customer logos, view transitions; `ConferBot.shared.home`, `HomeScreenView`
  (#85, #87).
- **"Your requests":** `ConferBot.shared.requests` (`requests`, `unread`, `open(requestId:)`,
  `refresh(force:)`), `RequestsPortalView`, `RequestsViewController` (#38).
- **Help centre:** follows `enableKnowledgeBase` / `hideRecentArticles`, bodies fetched on
  open, search over the socket with snippets, `openHelpArticle(id:)`, `isHelpCentreOn`,
  `KnowledgeBaseView(articleId:categoryId:onBack:)` (#33, #42, #50, #51, #54, #55).
- **"Email me this chat":** `openEmailTranscript()`, `emailTranscript(_:done:)` (#39).
- **Widget languages:** English, Dutch, French, German and Spanish, chosen as the web
  chooses; `ConferBotConfig(widgetLanguage:)`, `ConferBot.shared.widgetLanguage`, `I18n.t`;
  the words ship as a SwiftPM resource and in the pod's `Conferbot.bundle` (#89).
- **The owner's font** from Google Fonts, registered with Core Text and cached (#46).
- **Sounds** (`ConferBot.shared.sounds`, Sound on / off in the menu), **human touches**
  (tapbacks, confetti, "No rush", "Edit" on the latest answer), **auto-open** and the
  agent's **typing preview** (#48, #90, #91).
- **Post-chat redirect** (`redirectUrl`): a 10 s countdown line with Cancel, then the
  system browser; `ConferBotConfig(onPostChatRedirect:disablePostChatRedirect:)`,
  `ConferBot.shared.postChatRedirect` (#92). The post-chat rating at the flow's end (#95,
  #98).
- **Identity verification:** `ConferBotUser(hash:)`, the user sent with every record as the
  visitor context (#18).
- **Push notifications:** `setPushToken`, `unregisterPush()`, `handlePushNotification(_:open:)`,
  `onPushOpen`, `pushToOpen`, `PushTokenType`, `ConferbotPush`, `parseConferbotPush(_:)`,
  `isConferbotPush(_:)`; the token registered per conversation over HTTP; no push library
  in the SDK (#97).

### Changed

- The flow is loaded from the bot's data on connect and started with the session; agent
  bots open on the agent chat (#1-#4).
- The flow runs as the web runs it: exact handles, the first edge for a step that does not
  branch, the end of a path ends the chat, unknown steps pass along their first edge,
  pacing as on the web (#5, #27, #52, #69).
- The composer is one line and grows with the text (#76, #77).

### Fixed

- The package compiles: one calendar handler, no duplicate `InputValidation`, the missing
  `NodeTypes` member, the SwiftUI availability (#1, #9).
- Agent details decode without an email (#3).
- A new session starts from the server's `session/init` payload and belongs to the
  client's bot (#60); `startSession()` no longer hangs on the analytics lock (#61).
- The flow's steps send `chatSessionId` and `botId`, so a handover makes a ticket (#62).
- Socket listeners added before `connect()` are kept, and items are emitted as separate
  arguments; two `connect()` calls at once no longer crash (#19, #78).
- A restored bot message keeps its avatar and bubble style (#65).
- A picked file goes to its step to be checked and uploaded; a picked date reaches its step
  on the right clock (#72, #73).
- A visitor refused at connect no longer sees "Connecting..." for good; the closed chat's
  composer is off in `ChatViewWithKBSheet` too (#79, #80).
- `OfflineManager` publishes its queue count at once and runs one flush at a time (a
  message could be sent twice); `FileUploadService` no longer leaks through its
  `URLSession` (#99).
- A message sent while the socket is reconnecting is queued and sent on the next connect,
  not lost; the queue's messages keep their retries. Socket.IO's `reconnect` fires when
  reconnection starts, and the SDK no longer takes it as connected (#101).

### Security

- Identity verification: with `ConferBotUser.hash` the server files the chat under the
  verified user; when the workspace requires it, a missing or wrong hash drops the claimed
  name, email and id. The secret never ships in the app (#18).
- Sign-out (`identify(user: nil)`) and switching users drop the last user's requests and
  ignore answers still on their way for them, for shared devices (#86).
- Card numbers, ids and passwords a visitor types are masked in answers and records unless
  the bot's `redactSensitive` is off; the typing preview is never sent from a secure field
  (#30, #48).
- The post-chat redirect follows only `http(s)` URLs and opens them in the system browser,
  never in the chat (#92).
- A push is handled only when it is Conferbot's and for this bot (#97).
- The socket handshake carries the visitor id, so a visitor the workspace blocked is
  refused at connect (#40).

## [1.0.0] - 2026-04-23

### Added
- Initial release of the Conferbot iOS SDK (Swift 5.7+)
- `ConferBot.shared` singleton, Combine `@Published` state and `ConferBotDelegate`
- Real-time messaging via Socket.IO, REST via `URLSession` with async/await
- UIKit `ChatViewController`, `MessageCell`, `ChatInputView`; SwiftUI `ChatView`,
  `MessageBubble`, `ChatInput`
- Node flow engine with 50+ node types
- Live agent handover support, typing indicators
- Message reactions and read receipts
- File and image uploads
- Knowledge base integration
- Session persistence
- Push notification support (APNs)
- User identification and metadata
- Full theming and customization (`ConferBotCustomization`)
- Offline message queuing
- Analytics and event tracking
- Swift Package Manager and CocoaPods manifests

[Unreleased]: https://github.com/Conferbot/conferbot-ios/compare/1.0.0...HEAD
[1.0.0]: https://github.com/Conferbot/conferbot-ios/releases/tag/1.0.0
