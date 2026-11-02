# Ditto

Copy once. There when you need it.

## Product intent

Ditto is a native macOS menu bar utility combining clipboard history with the feel of terminal autocomplete. It helps you reuse copied content without leaving the text field you are working in. This document is the source of truth for implementation and future product decisions.

## Agreed decisions

- Name: Ditto, used as the working product name. Name availability has not been checked.
- Platform: macOS. Build natively in Swift, with AppKit for system interaction and floating windows, and SwiftUI where useful for settings and history.
- Invoke explicitly with Option–Command–V. Suggestions do not appear during ordinary typing outside a Ditto session.
- Initially suggest the newest copied text item. A clipboard item means the entire copied text, not an individual word extracted from it.
- Typing performs the search. Do not reserve `s` for search.
- Typed query characters go into the destination app immediately. Suggested content remains uninserted until accepted.
- Tab accepts a suggestion. Up/Down cycles candidates. Escape dismisses without deleting what the user typed.
- Provide an expanded clipboard history list.
- All capture, storage, and matching are local. No account, cloud service, or AI is needed for the initial product.

## Proposed defaults carried into the first implementation

These are implementation choices from the UX proposal, rather than separately confirmed preferences. Change them here when feedback warrants it.

- Use Command–L to expand history while a session is active. The original request used bare `l`; this conflicts with typing words beginning with l. Literal letters must remain query input.
- Rank case-insensitive prefix matches before substring matches, then by recency. Empty query uses recency.
- Option–Command–V must show transparent autocomplete text at the insertion cursor, without taking focus. It must never automatically expand history when completion is unavailable. History opens only through an explicit Command–L or menu action. Missing permissions get a small temporary hint, not a full history window.
- Enter in compact mode keeps its normal destination-app behavior and ends the session. It never accepts a clipboard candidate.
- History takes keyboard focus: typing filters inside Ditto, arrows select, Enter accepts, Escape returns to compact mode. Escape again exits. Clicking a row selects it for preview; the labeled Paste button or Enter accepts. Unsupported-field history labels Enter as Copy.
- Seven-day retention, with pinned items retained until explicitly removed. Duplicate copies move an existing item to the top.
- Plain-text insertion by default. Text-only completion and history ship before images, files, and rich formatting. Image capture remains deferred and must be clearly identified as unsupported, rather than presented as a broken text-history feature.

## Core flow

1. Clipboard history is enabled by default when no prior preference exists, following the user’s explicit request to fix capture. Preserve an explicit pause. Copy text normally; capture permitted items silently, recording time and the source app when available.
2. Put an insertion cursor in a destination and press Option–Command–V.
3. Record the destination app, focused editable element, available cursor state, and the clipboard history snapshot for the session. A writable AX selection is not required for the experimental suffix path. Do not insert anything.
4. Show the newest candidate with keyboard hints. Let normal characters pass through to the destination. Prefer actual destination text/ranges; otherwise track bounded event Unicode during the explicit session, cancelling on unsupported input or navigation. Do not assume US key codes equal characters.
5. Update candidates as the user types or backspaces. No match leaves a clear, unobtrusive empty state; it does not block normal typing.
6. On Tab, revalidate the focused element and session range where available, replace only the session query with the whole candidate, then close. The experimental event-tracked path instead appends an exact single-line suffix without deleting text; arbitrary replacement there remains incomplete. Never send a Return key as part of insertion.
7. On Command–L, expand history and carry over the query. Its filter can change without modifying the destination. Acceptance still replaces the original session query after revalidating it.
8. Escape from compact mode preserves the typed query. Changing apps, moving outside the session range, clicking elsewhere, or beginning an unsupported input composition ends the session.

## Safety and compatibility contract

- Never delete text using a blind sequence of Backspace events.
- Cancel insertion if focus, selected range, or original query no longer matches the recorded destination.
- Detect unsupported editable elements and show a brief completion-unavailable hint. History/copy is available only on explicit request. Do not claim universal inline completion.
- A preexisting selection is not an implicit replacement target in the first version; ask the user to place an insertion cursor.
- Disable completion in secure text fields and during secure input where detectable. Respect clipboard exclusion/confidential markers and provide app exclusions and pause capture. Automatic secret detection is not guaranteed.
- Read the focused field temporarily to validate the session (first adapter bounds fields to 100,000 UTF-16 units). Do not persist typed queries, destination contents, or key events.
- Event callbacks must remain short. Query reads, matching, and drawing happen outside the event callback. Ignore synthetic events generated by Ditto itself.
- Accessibility, event access, and clipboard permissions are explicit onboarding states. A denied permission must not cause silent insertion failures.
- Acceptance uses the destination app’s native undo behavior. TextEdit and T3 have restored the typed query with one Undo; Slack groups the query and accepted paste and clears both. Clipboard preservation, undo behavior, and caret positioning are verified per app rather than assumed from a successful build.
- If pasteboard-based insertion is needed, never restore an old clipboard over a newer user copy. Do not claim that a fixed delay proves a destination consumed a paste.

## First usable release

- Menu bar app: open history, pause capture, settings, quit.
- Text clipboard history stored locally in SQLite with deduplication, retention, pin, delete, and clear actions.
- Native compact suggestion panel and expanded searchable history.
- Option–Command–V invocation; session keyboard handling; focus and range validation before insertion.
- Onboarding for required permissions and a built-in practice text field.
- Capture controls, source-app exclusions, retention, and launch-at-login controls where supported.
- Buildable and runnable using the installed Swift command-line toolchain; a script produces a local Ditto.app bundle.

## Delivery order

1. Establish the Swift package, app bundle workflow, and automated tests for matching and session validation.
2. Implement SQLite capture/history policies with temporary-database integration tests.
3. Build the native menu bar app, permission onboarding, shortcut/event handling, compact panel, and guarded insertion.
4. Add history browsing and capture settings, then package and smoke-test the app.
5. Verify real-app behavior in Ghostty, browser text fields, the user's editor, and chat apps. Record support and limitations explicitly.

## Acceptance criteria

- `swift run DittoTests` passes matching, Unicode-range, stale-session, history persistence, deduplication, retention, and pin/delete behavior checks.
- Command Line Tools on the development machine lack XCTest and Swift Testing; the test executable replaces `swift test` without adding dependencies.
- A release build produces a launchable Ditto.app without an Xcode project or third-party runtime dependency.
- Copy → invoke → type → cycle → accept works in supported apps, without modifying text preceding the session.
- Dismissal leaves typed content intact. App/focus changes never paste into the wrong destination.
- History acceptance restores the intended destination, validates its query, and inserts only on an explicit acceptance action.
- Permission denial, empty history, no matches, and unsupported fields have usable visible states.
- Native app smoke checks and cross-app verification are reported separately from automated unit tests and successful compilation.

## Deferred

Images/files, rich-text insertion, sync, AI rewriting, semantic retrieval, snippet templates, configurable shortcuts, distribution signing/notarization, and automatic updates. A local ad-hoc-signed development build is not a notarized distributable release.

## Engineering workflow

- Keep this PRD updated when a product decision changes.
- Work inline; no delegated agents unless explicitly requested.
- Commit and push incremental, reviewable changes to the provided repository.
- Keep the existing portfolio repository untouched.
- Never include credentials, private clipboard contents, or machine-specific permission databases in source control.

## OSS research direction (2026-11-02)

The [macOS OSS input research](docs/research/2026-11-02-macos-oss-input-research.md) surveys 38 public projects and records source-level references, terminal/chat limitations, and the user's actual zsh-autosuggestions setup. Its recommendation is to retain a normal menu bar app with an explicit query session, caret overlay, and multiple insertion routes. Installing an input source or changing shell startup files is not an established requirement. A failed generic Accessibility range adapter is not evidence that an app cannot support completion. This is a research recommendation, not an implemented compatibility fix; the agreed UX and real-app handoff gate still apply.

## Experimental event-tracked path (2026-11-02)

A native prototype now avoids requiring writable AX selection for exact-prefix completion. It tracks up to 512 UTF-16 units of query text, offers exact single-line prefix candidates up to 4,096 UTF-16 units, and appends only the suffix. It prefers ordinary paste when readable cursor state supports acknowledgement, otherwise uses tagged Unicode events. It cancels on pointer/navigation/unsupported composition and never synthesizes deletion. Full substring/case-changing replacement and multiline insertion are still restricted to the validated range path. Expanded history remains complete and offers Copy for an event-tracked destination. TextEdit end-to-end checks exercise automatic and forced event-query routes; Ghostty and WhatsApp remain unverified. This is a limited experimental implementation, not a revision of the intended any-app experience or satisfaction of the handoff gate.

## Placeholder masking prototype (2026-11-02)

The user requested hiding the host placeholder visually while retaining the inline suggestion and leaving the input empty. Prototype direction: capture only the focused empty input's first-line background region using ScreenCaptureKit, excluding Ditto overlays; retain the capture RGB profile and use an observed sampled color only when opaque surrounding samples stay within one RGB level of that color and pass the ambiguity check. A separate non-activating mask preserves a transparent caret slot and is removed on typing, pointer/scroll activity, dismissal, focus changes, or region changes. Screen Recording permission is explicitly requested through Setup. Product captures remain in memory and are not persisted. Late capture results are discarded after a session, query, focus, or region change.

A background whose surrounding samples disagree is not averaged. The prototype instead shows the suggestion below the placeholder line. The same fallback applies without permission or reliable empty-field/geometry evidence. This does not establish perfect matching for gradients, textures hidden beneath text, animated backgrounds, wrapped placeholders, every color profile, or every target app. Live pixel verification is required before claiming even the controlled fixtures pass.

## Handoff gate after initial prototype feedback

The initial prototype was rejected: its default large history popup was not the agreed autocomplete UX, capture had not been verified live, and compilation/unit checks were incorrectly treated as enough for a usable handoff. Before another usable-app handoff, record actual native end-to-end results for copy → capture → invoke → type → accept, candidate cycling, history, Escape, stale focus/app switches, and the intended destination apps. A failed or untested path remains explicitly incomplete; a smoke check does not satisfy this gate.

## Empty rich-text composers (2026-11-02)

T3 and Slack can report their empty rich-text paragraph as a single structural newline with no usable collapsed character bounds. The adapter normalizes that representation only at selection zero and with a visible matching placeholder or an inset empty-paragraph layout as evidence. It derives initial cursor geometry from that layout or the matching placeholder text, rather than using an entire editor rectangle as a cursor. Existing document text keeps strict byte/range validation. A below-line fallback moves above the input when the display has insufficient space underneath.

The initial mask state is cleared on typing without cancelling the completion session. The controlled dark/white/gray and texture suite has passed, and actual T3 completion, placeholder hiding, clipboard preservation, Escape, undo, and cleanup have passed. An uninterrupted Slack run confirmed that native Undo clears both the query and the accepted paste, with the same field still focused. Its placeholder hiding, completion, Escape, and clipboard preservation have passed. This is progress toward the existing handoff gate, not a claim of universal compatibility.
