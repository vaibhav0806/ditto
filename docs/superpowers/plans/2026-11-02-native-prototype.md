# Ditto native prototype implementation plan

Source of truth: [product.md](../../../product.md). Execute inline, as requested by the user. The repository was empty; `main` contains the PRD baseline and implementation is on `feat/native-prototype`. Push each completed increment. No delegated review or implementation.

## Constraints and interfaces

Swift Package Manager; macOS 13+; AppKit/ApplicationServices/Carbon; system SQLite. No external dependencies. Core code must not depend on UI, permissions, or the user's clipboard. `ClipboardEntry` is the shared persisted/candidate model. `CompletionSession` derives a validated query and replacement range from actual text/selection snapshots. `HistoryStore` owns SQLite and expiry. App services run on the main thread; the event callback only decides key consumption and schedules work.

## Tasks

- [x] Core completion: write failing ranking and Unicode/session validation tests; implement matching and bounded session verification; run `swift run DittoTests`; commit/push.
- [x] Persistence: write temporary SQLite tests covering reopen, duplicate promotion, pin/delete, expiration and retention; implement `HistoryStore`; run full suite; commit/push.
- [x] Native app: menu/status, permission onboarding, pasteboard polling, hotkey, event tap, accessibility snapshot/guarded insertion, compact panel and history. Build with `swift build`; test pure policies and targeted integration boundaries; commit/push.
- [x] Finish: settings, local app bundle script, built-in practice field, launch smoke check and documentation; `swift run DittoTests`, `swift build -c release`, bundle verification; commit/push.

## Review focus

Wrong destination after focus changes; stale text/ranges; non-BMP Unicode and composed characters; clipboard changes during insertion; event-tap disable/permission denial. Test deterministic boundaries in the core and document real-app checks that require user-granted macOS permissions. Do not call a compiled app cross-app verified.

## Progress and rulings

- PRD committed/pushed first: `6cfaa2d`.
- Native Swift command-line tools are installed; full Xcode is not selected. Package/build workflow must work without Xcode.
- A small candidate panel is the first implementation; exact ghost-text rendering is deferred in the PRD.
- Ruling: Command Line Tools lack both XCTest and Swift Testing. Use a dependency-free `DittoTests` executable (`swift run DittoTests`) rather than require an Xcode installation or fetch a test framework. Initial tests failed on missing behavior before implementation. Matching/session tests now pass, including rejection of a cursor inside a surrogate pair.
- Core completion: complete, 5 checks passed. SQLite persistence: implemented after four expected failing integration checks; 9 total checks now pass. Local DB is mode 0600; capture is bounded and SQL uses bound values.
- Native app compiles. Added session-only event interception, AX text/range revalidation, local clipboard capture (opt-in), setup, practice field, history filtering/preview/pin/delete/copy, capture settings, and login controls. Keyboard/confidential-marker policies passed after expected failing checks (11 total tests).
- Ruling: initial insertion uses AXSelectedText directly and never alters the pasteboard. Unsupported elements use explicit Copy. Terminal/shell autocomplete is not claimed until verified. Exact native undo semantics remain a real-app compatibility check.
- History row clicks select for preview; Enter or the labeled Paste button accepts. This keeps preview browsing non-destructive. Fallback history uses Enter/Copy to copy explicitly.

- Local release bundle was built and verified; bundle smoke check succeeded with setup visible and capture off. Inspected Setup, Practice and empty History using native UI tools; Escape dismissed History. No permissions were granted. App-targeted synthetic keypress did not demonstrate the global shortcut, so that remains explicitly unverified.
- Self-review: checked all acceptance criteria against code and evidence. App-specific insertion, undo, composition and multi-display behavior remain unverified pending permissions. No delegated reviewer was used, as requested.
- Final review fixed Unicode normalization outside a query: Swift's canonically equivalent string comparison can hide changed UTF-16 offsets. A regression check failed first; prefix/suffix/query and pre-write text comparisons now require exact code units. Suite: 12 tests, 0 failures.
- Added standard macOS Edit/Quit menu actions so the practice editor, history search and settings retain normal text shortcuts.

- Packaging and documentation complete: `scripts/build-app.sh`, Info.plist, README and verification checklist. Native permissions and real-app insertion remain explicitly unverified; this is the first local prototype, not a distributed release.

## Research-backed cursor completion iteration

Spec: `product.md`; evidence: `docs/research/2026-11-02-macos-oss-input-research.md`.
Execute inline, as requested by the user. Keep existing shortcut and explicit-history behavior.

- [x] Reproduce the writable-selection gate in `AppController.invoke` and `TextTarget.focused`.
- [x] Add failing query-buffer tests, implement bounded event tracking in `CompletionSession`, and preserve exact Unicode boundaries. No blind deletion in fallback.
- [x] Connect typed-event query tracking, tagged suffix injection, and caret text-marker/previous-glyph fallbacks. Only exact single-line prefix candidates are offered through this path.
- [x] Exercise the actual global shortcut in TextEdit using the existing opt-in native runner, including a forced event-query route. Verify appearance and actual text separately; record undo behavior rather than assume it.
- [x] Run automated checks and signed release build; update verification/PRD; commit and push. Do not infer Ghostty or WhatsApp support from another app. Existing computer-use denial for Ghostty remains a live test limitation; no alternate automation bypass.


## Pixel-matched placeholder masking prototype

Spec: user requested the existing placeholder visually disappear with the exact app background, without inserting content. macOS exposes the placeholder attribute as read-only.

- [x] Test flat-color detection, gradient/texture rejection, input-bounded geometry, and actual rendered RGBA/caret transparency at 1x/2x.
- [x] Add narrow-region ScreenCaptureKit sampling, excluded overlay windows, permission preflight, and stale-focus/generation checks. Captured pixels are never persisted by the product.
- [x] Add a separate non-activating mask that leaves the native caret visible, hides on typing/cancel, and falls back below the line when no exact sampled color is available.
- [ ] Verify live source-vs-mask pixels in dark/white/gray fixtures, removal on typing, and texture rejection with OS Screen Recording permission.
- [ ] Run native regression, record precise limitations, commit/push, and restart the app normally.

Limits: matching sampled border colors is evidence of a flat field, not proof of the hidden pixels beneath every glyph. Gradients/textures and wrapped placeholders cannot be promised seamless. The initial prototype targets a single placeholder line and requires macOS 14+ plus Screen Recording for capture. Full cross-app verification remains open.
