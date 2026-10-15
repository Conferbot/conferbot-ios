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

## Left in this SDK

1. **Greeting card** (see "Porting the greeting card" below): SwiftUI in `ConferBotWidgetView`, with UserDefaults key `conferbot.greeting.<botId>`.
2. The rest of the list below.
3. **UIKit gaps:** UIKit lags SwiftUI (initials avatar, typing styles). Audit it against the SwiftUI chat.
4. `initialize(...)` takes no user. Only `identify(user:)` sets the visitor context. Consider an optional `user:` parameter, as Android has.

## How to test

- **Linux (no Mac needed):**
  - Build and test the core in `swift:5.10-jammy` docker, with `#if canImport(FoundationNetworking)` imports and the UI folders left out.
  - The 28 tests in RN's `scripts/parity/ios-linux-baseline-fails.txt` already fail on Linux; only failures outside that list matter.
  - One run segfaulted (signal 11) partway through and passed on the rerun, so rerun once before investigating a crash.
- **UI changes:**
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
| Greeting card (rules, frequency, 11 styles) | done | logic done, UI on a branch | todo | todo |
| Launcher entrance / attention / idle call | todo | todo | todo | todo |
| Home screen | todo | todo | todo | todo |
| Mascots (incl. `mascotInGreeting`) | todo | todo | todo | todo |
| `widgetLanguage` (i18n) | todo | todo | todo | todo |
| Message sounds | todo | todo | todo | todo |
| Celebrations / reactions | todo | todo | todo | todo |
| Reply-time wording | todo | todo | todo | todo |

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

### Porting the greeting card (from RN)

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
