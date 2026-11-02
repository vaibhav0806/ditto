# Ditto native prototype implementation plan

Source of truth: [product.md](../../../product.md). Execute inline, as requested by the user. The repository was empty; `main` contains the PRD baseline and implementation is on `feat/native-prototype`. Push each completed increment. No delegated review or implementation.

## Constraints and interfaces

Swift Package Manager; macOS 13+; AppKit/ApplicationServices/Carbon; system SQLite. No external dependencies. Core code must not depend on UI, permissions, or the user's clipboard. `ClipboardEntry` is the shared persisted/candidate model. `CompletionSession` derives a validated query and replacement range from actual text/selection snapshots. `HistoryStore` owns SQLite and expiry. App services run on the main thread; the event callback only decides key consumption and schedules work.

## Tasks

- [ ] Core completion: write failing ranking and Unicode/session validation tests; implement matching and bounded session verification; run `swift run DittoTests`; commit/push.
- [ ] Persistence: write temporary SQLite tests covering reopen, duplicate promotion, pin/delete, expiration and retention; implement `HistoryStore`; run full suite; commit/push.
- [ ] Native app: menu/status, permission onboarding, pasteboard polling, hotkey, event tap, accessibility snapshot/guarded insertion, compact panel and history. Build with `swift build`; test pure policies and targeted integration boundaries; commit/push.
- [ ] Finish: settings, local app bundle script, built-in practice field, launch smoke check and documentation; `swift run DittoTests`, `swift build -c release`, bundle verification; commit/push.

## Review focus

Wrong destination after focus changes; stale text/ranges; non-BMP Unicode and composed characters; clipboard changes during insertion; event-tap disable/permission denial. Test deterministic boundaries in the core and document real-app checks that require user-granted macOS permissions. Do not call a compiled app cross-app verified.

## Progress and rulings

- PRD committed/pushed first: `6cfaa2d`.
- Native Swift command-line tools are installed; full Xcode is not selected. Package/build workflow must work without Xcode.
- A small candidate panel is the first implementation; exact ghost-text rendering is deferred in the PRD.
- Ruling: Command Line Tools lack both XCTest and Swift Testing. Use a dependency-free `DittoTests` executable (`swift run DittoTests`) rather than require an Xcode installation or fetch a test framework. Initial tests failed on missing behavior before implementation. Matching/session tests now pass, including rejection of a cursor inside a surrogate pair.
