# Ditto

Copy once. There when you need it.

A native macOS menu bar prototype that filters your clipboard history while you type. The product decisions and scope live in [product.md](product.md).

## Build and run

Requires macOS 13+ and Swift 5.9+ (`xcode-select --install` provides the command-line tools). No third-party dependencies or Xcode project are required.

```sh
./scripts/build-app.sh
open build/Ditto.app
```

The script reuses a locally cached signing identity, or uses `DITTO_SIGN_IDENTITY` when supplied; otherwise it makes an ad-hoc-signed development bundle. This is not a notarized release. Keep the bundle at the same path while testing. Changing its signing identity can require refreshing its Accessibility permission.

Use the menu bar clipboard icon to reopen Setup, History, Practice, or Settings. Clipboard capture defaults **on**; an explicitly paused preference stays paused. In Setup, grant Accessibility and enable capture if it is paused. If session keyboard controls are unavailable, check Input Monitoring too. On macOS versions that restrict background clipboard access, choose Always Allow for Ditto. Permissions are granted by you through macOS, not by the build script. Restart Ditto if macOS asks you to do so after a permission change.

If ⌥⌘V cannot register, another app may own it; release that shortcut in the other app for this prototype. Custom shortcuts are deferred.

## Interaction

1. Copy some text while capture is on.
2. Put an insertion cursor in a supported text field and press **⌥⌘V**.
3. Type in the destination to filter suggestions. **↑ / ↓** cycles, **Tab** replaces only your session query, **Esc** dismisses while keeping your typing.
4. **⌘L** expands history. Its search field filters inside Ditto. Arrow keys select; **Enter / Paste** accepts. Clicking a row selects it for preview. **Esc** returns to compact mode when a valid session exists.
5. In unsupported fields, history offers **Copy / Enter**, then you paste manually using **⌘V**. The UI explicitly labels this fallback.

Fields with reliable selection support can replace the query with the whole copied item, including line breaks. The event-tracked fallback currently offers exact, single-line prefixes only (up to 4,096 UTF-16 units), appending the remaining suffix without deleting text. Its expanded history offers Copy rather than replacement. Other fields may still have no usable caret geometry. Enter in compact mode is passed through to the destination and does not accept a suggestion. Ditto never adds a Return keystroke to an acceptance.

## Empty-field background matching (prototype)

With Screen Recording permission enabled in Ditto → Setup, the prototype samples a narrow strip of the focused empty input. It excludes Ditto overlays and uses an observed sampled color only when the surrounding pixels pass a bounded capture-noise check. A temporary visual mask covers the placeholder line while preserving the native caret. Typing, dismissal, focus/region changes, and pointer/scroll activity remove the mask; the destination text is not changed by masking.

Without permission, reliable geometry, or a uniform sample, suggestions appear below the placeholder line. This first-line prototype does not establish seamless behavior for gradients, textures, animated backgrounds, wrapped placeholders, all display profiles, or every host app. Product samples remain in memory; only controlled developer fixtures may be saved by the test runner.

## What works in the code

- Native menu bar app, transparent caret suggestion, and a 680 × 440 history panel with source-app icons, native table selection, independent text preview and Actions (⌘K).
- Local SQLite persistence, duplicate promotion, seven-day retention by default, pin/delete/clear.
- Prefix-before-substring matching with recency tie breaking.
- Guarded AX range selection followed by ordinary paste; event-tracked suffix completion when selection writing is unavailable. Native paste is preferred when readable cursor state permits acknowledgement. Otherwise tagged Unicode events append a single-line suffix. No blind backspacing.
- Default-on text capture; pause, app exclusions, retention and launch-at-login settings.
- Setup/permission states and a built-in practice editor.

Images/files, customizable shortcuts and distribution are deferred. Actual global-shortcut tests pass in TextEdit for both automatic and forced event-query tracking. Actual T3 completion, placeholder masking, Escape and undo have passed. Slack masking and acceptance have passed; its native Undo clears both the typed query and accepted paste. Ghostty, WhatsApp, and the current browser builds remain **unverified**; neither a build nor TextEdit proves those apps work. Pure Unicode insertion can have different undo grouping from paste.

## Verify

```sh
swift run DittoTests
swift run DittoUITests --output-directory .build/history-ui
swift run DittoUITests --glyph-only --output-directory .build/history-ui
swift build -c release --product Ditto
./scripts/build-app.sh
build/Ditto.app/Contents/MacOS/Ditto --smoke-test
```

`DittoTests` is a dependency-free test executable. The installed Command Line Tools did not contain XCTest or Swift Testing, so `swift test` is not the test command. The tests use temporary databases and fixtures, never your clipboard. Smoke mode uses a temporary database and does not register the hotkey, start capture, request permissions, or modify your normal preferences; it opens setup and exits automatically.

The native UI checks compare native and ghost glyph pixels, then open a controlled sample history panel and exercise its actual AppKit controls. `--glyph-only` runs without showing a panel. They do not write the clipboard or test insertion into another app. Cached-view PNGs do not reproduce live desktop blur.

The opt-in native runner uses real system-wide keys and the real clipboard in a disposable TextEdit document. Leave keyboard/focus alone while it runs:

```sh
./scripts/run-native-e2e.sh textedit
./scripts/run-native-e2e.sh textedit-events
./scripts/run-native-e2e.sh history-textedit
./scripts/run-native-e2e.sh prefilled
./scripts/run-native-e2e.sh typography
./scripts/run-native-e2e.sh t3-typography
```

`prefilled` uses generated native text fields to check baseline, line-end position, Escape and insertion with an existing draft. The second command forces event-query tracking in TextEdit; it does not establish behavior in an app without readable AX state. `history-textedit` focuses on the redesigned panel: filter without editing the host, no-result Return, Escape back to the original query, real history paste, and undo.

`typography` captures generated suggestions in actual TextEdit, accepts them, and compares their letter positions and dimensions with the host-rendered result. After the `mask` fixture seeds the clipboard, `t3-typography` does the same for an already empty, focused T3 message composer and cleans up without sending. It requires Screen Recording. Production baseline calibration samples only a narrow focused-field text strip locally in memory; it never saves those samples or uploads them. Fields that do not expose font information may still require inferred typography; compatibility is not inferred from a successful build.

With Screen Recording enabled, `./scripts/run-native-e2e.sh history-ui` captures the real panel over generated sample content in dark/light/high-contrast appearances and checks OS keyboard navigation, filtering and Actions. It never reads clipboard history or pastes into another app. High contrast is a per-window appearance override, not a change to the system setting. Its acceptance assertion checks callback dispatch; external insertion is covered separately by `history-textedit`.

With Screen Recording enabled, `./scripts/run-native-e2e.sh mask` checks live dark/white/gray placeholder masking and textured-background rejection. The `t3` and `slack` modes require an already-focused empty message composer and the generated clipboard token from the mask run. They refuse other clipboard content, stop on app/field focus changes, and never press Return or send a message. Slack tests should use a self conversation. Test reports and cropped fixtures stay in ignored `.build/`. Restart the app normally after developer tests; test flags belong only to verification sessions.

See [docs/verification.md](docs/verification.md) for observed results and the remaining real-app checklist. A green build is not proof of successful cross-app insertion.

## Local data and privacy

History: `~/Library/Application Support/Ditto/history.sqlite` (directory mode 0700, database mode 0600). Preferences use the app's user defaults. Stored history is plaintext SQLite protected by local filesystem permissions, **not encrypted by Ditto**.

Capture skips recognized concealed, transient, and autogenerated pasteboard markers, secure input where detected, and excluded source apps. Source-app metadata is best effort, based on the frontmost app when a change is observed. These checks cannot identify every secret; use pause/exclusions when copying sensitive data. Clipboard polling can miss intermediate copies made between samples.

Session document snapshots and bounded typed queries exist temporarily in memory; they are not saved or logged. Matching is local. No accounts, analytics, AI calls, or network service are part of the app.

Paste-based insertion temporarily writes the selected text or suffix to the clipboard, then restores the original clipboard only after the destination readback acknowledges insertion and ownership is unchanged. It never restores over a newer copy. If acknowledgement times out, it leaves the chosen text on the clipboard and does not replay. Unicode suffix insertion does not touch the clipboard. Undo behavior remains a per-app compatibility check. Selecting a history item and pressing **Copy** intentionally changes the clipboard.

Quit stops capture. Clear History removes saved/pinned rows; it does not overwrite the system clipboard or promise forensic erasure of SQLite pages, filesystem snapshots, or backups.
