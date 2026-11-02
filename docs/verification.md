# Native prototype verification

## Populated-field autocomplete positioning — 2026-11-03

A live TextEdit regression reproduced the user's populated-field bug: invoking with `External ` already present rendered the suggestion 20 pt below the caret line. The empty Ditto query had incorrectly taken the empty-host placeholder fallback. An acknowledged nonblank host value now permits immediate inline completion without masking. A second native screenshot and glyph-baseline assertion reproduced the floating text: the label added 4.84375 pt above the host baseline because its height exceeded the caret line height. The label now uses the actual caret height, and the helper footer beneath it is removed. Long suggestions truncate at the field/display edge while keeping their origin at the caret, rather than shifting left over existing text. Empty or unreadable host values retain conservative placeholder protection.

Native populated-field fixtures cover a single-line draft, a later line in a multiline draft, a line with following document lines, and a caret near the field's right edge. They check glyph-baseline equality, caret x, field containment, unchanged draft before acceptance, no placeholder mask, Escape, and actual insertion preserving the existing prefix/suffix. This does not establish exact font matching in every third-party app or resolve presentation in the middle of visible text on the same line. Final signed-build runs: `prefilled` passed 25 results including the runner, with 0.0 pt glyph-baseline and line-center offsets in all four fixtures; `history-textedit` passed 16 including real capture, global invocation, populated-field geometry, completion, history Escape/paste and undo; `mask` passed all 27 results. The current 30 core tests and strict signature verification pass. These supersede the earlier focus-interrupted run for these focused scenarios; the older broad multi-copy driver failure remains separately documented.

## Search-panel refresh — 2026-11-03

The expanded history panel now uses native AppKit controls and the reviewed 680 × 440 pt layout. Matching, capture, inline masking, and insertion routes retain their existing contracts. The following results belong to this UI revision; older entries below remain historical.

| Check | Observed result | Scope |
| --- | --- | --- |
| `swift run DittoTests` | 30 passed, zero failures | Core behavior, placement, Unicode-safe bounded presentation, history selection bounds |
| `swift run DittoUITests --output-directory .build/history-ui` | 31 passed, zero failures | Actual AppKit controls: focus, search, selection, Actions, preview, no-result Return, hidden-view isolation; controlled cached-view screenshots |
| `./scripts/run-native-e2e.sh history-ui` | 11 passing results including runner | Real OS keys in the signed app; live compositor captures over generated workspace content in dark, light, and per-window high-contrast appearances |
| `./scripts/run-native-e2e.sh history-textedit` | 15 passing results including runner | Real copy/capture/global invocation, inline acceptance/undo, history filtering, empty-result Return, Escape restoring original host query, real history paste and one-step undo in TextEdit |
| `./scripts/build-app.sh`, strict codesign verification | Passed | Signed local release bundle; no distribution/notarization claim |

The live history UI fixture uses sample data and acceptance callbacks, not the user's history or external paste. The separate TextEdit run reads back actual destination text after system-key acceptance. Cached-view screenshots establish control rendering, not desktop blur. Live PNGs and JSON stay in ignored `.build/`. Initial high-contrast screenshots used an `accessibilityHighContrastDarkAqua` appearance override. The subsequent real system-setting checks below supersede that appearance-only coverage. VoiceOver speech remains untested.

PixelDesign reviewed the concept and native captures by email. The implementation addresses the native review's three must-fixes: readable flattened multiline excerpts (display only), primary footer hierarchy, and clean no-results with no-op Return. Whitespace markers are off, source icons resolve from bundle IDs, preview wrapping uses hanging indents, and the selectable original text remains unchanged. A subsequent live review caught wrapping in the list excerpt. Rows now enforce a single line with explicit attributed tail truncation; the preview uses fixed 16 pt code lines, and the pin/time columns have fixed slots. Regression checks failed before these changes and pass afterward. PixelDesign subsequently cleared the revised layout visually, and after reviewing the real system-setting captures explicitly cleared the accessibility appearance blocker too. Spoken VoiceOver verification remains open and is not counted as complete. The preview now removes NSTextView's extra line-fragment padding to align its text with the metadata at the same 16 pt inset. Native NSBox separators and the 12 pt clipping mask remain in use; backdrop marks in rectangular screenshot corners are outside the rounded panel.

With explicit user authorization, both real display settings were exercised through System Settings. Original values were Increase Contrast off and Reduce Transparency off. Turning on Increase Contrast automatically enabled and locked Reduce Transparency; AppKit reported both flags true. The signed live panel run passed all 11 results, with visibly stronger separators, brighter secondary text, and opaque backgrounds. Turning contrast off restored both flags off. Reduce Transparency was then enabled alone; AppKit reported false/true and another 11-result live run passed. Dark and light captures show solid appearance-appropriate backgrounds. Finally both preferences were restored off and confirmed in System Settings and through NSWorkspace. No global settings remain changed. Controlled reports/captures are under ignored `.build/history-accessibility/`; no user clipboard/document content is included. These visual/keyboard checks do not establish VoiceOver speech behavior.

The broader `textedit` regression run did **not** finish: after successful capture, invocation, acceptance, undo and immediate Tab, its later synthetic Cmd-A left an empty selection in the acknowledged fixture. The runner stops on that assertion. This is not counted as a full pass or a verified application regression; the cause of that driver/host selection failure remains unresolved. The focused history runner passes independently without that multi-copy preparation sequence. Ghostty, WhatsApp and browser compatibility are not established by this UI revision.

Latest iteration: 2026-11-02. This is an experimental build, not a completed any-app handoff.

## Automated checks

- macOS 15.7.2, Apple Silicon, Swift 6.2.1, Command Line Tools.
- `swift run DittoTests`: 19 tests, zero failures. Coverage includes event-query Unicode/bounds, exact-prefix suffix planning, stale/range rejection, matching, SQLite persistence/retention, real named-pasteboard capture, default capture policy, and clipboard ownership/rich-type preservation.
- Signed release app build and `codesign --verify --strict` succeeded using the existing cached local signing identity. This does not establish distribution notarization.

## Native system-event checks

The opt-in `DittoE2E` runner posts actual WindowServer keys, including the registered global shortcut. It creates disposable TextEdit documents, copies unique fixtures through Cmd-C, and reads the destination back through AX. It aborts if the destination loses foreground focus. It does not call the completion handler to simulate success.

Commands: `./scripts/run-native-e2e.sh textedit` and `./scripts/run-native-e2e.sh textedit-events`. The second forces event-query tracking in a real TextEdit field; it is not a real app with missing AX state. Both runs exercise the user's actual permissions and installed app bundle.

Final runs passed on the signed build:

| Mode | Result | Coverage |
| --- | --- | --- |
| `textedit` | 16 assertions passed; runner passed | Actual range selection + paste |
| `textedit-events` | 17 assertions passed; runner passed | Forced event-query tracking; suffix paste without AX selection writing |

Both runs verified fresh clipboard capture, real shortcut activation, a compact non-activating ghost with rendered pixels, accepted destination text, one-step undo, clipboard restoration, immediate Tab after typing, candidate cycling, explicit history, Esc preserving typing, and app-switch cancellation. Normal history acceptance pastes; event-query history acceptance copies without replacing the destination. Font observed in this TextEdit fixture was Helvetica 12; this does not establish browser font matching. The ghost bitmap checks visibility and content, not pixel-perfect baseline alignment against the host.

The successful final results are `.build/e2e-textedit.json` and `.build/e2e-textedit-events.json` with `.ghost.png` companions (ignored local artifacts). Earlier foreground-interrupted or failed runs are not counted as passes. The harness now explicitly activates the target and waits for actual foreground acknowledgement before starting. Build and unit tests are not substituted for native results.

## Bugs found during this iteration

- The old invocation gate required a writable selected range. The experimental suffix route can now start without it, provided a focused text target and caret geometry are available.
- An overly broad control-character filter rejected the joiner in compound emoji. Tests now preserve grapheme boundaries and allow those sequences while refusing control/newline input.
- Direct Unicode suffix typing inserted the correct text in TextEdit but coalesced the user's query into the same undo group. The router now prefers ordinary paste when readable cursor state permits acknowledgement. Pure Unicode insertion into a field without readback still has unverified undo grouping.
- Immediate Tab after typing exposed stale AX text in the original range route. Acceptance now waits for destination query acknowledgement before selecting/pasting, with a bounded deadline and no replay.
- App switches to Ditto's own unrelated windows must also cancel completion. The history-specific exception is now limited to actual history browsing.

## Remaining compatibility gaps

- Ghostty, WhatsApp, the user's editor, Safari, and the current Chrome build have not passed this iteration's real-app E2E matrix. Prior partial checks are not carried forward as passes. Browser font matching remains to be measured in the current build.
- An earlier computer-use approval review rejected Ghostty interaction with `Computer Use is not allowed to use the app 'com.mitchellh.ghostty' for safety reasons.` No alternate automation path was used to bypass that rejection. Ghostty needs an allowed test route or a user-driven trial; the code is not claimed verified there.
- The event-tracked path offers exact single-line prefixes only, with a 512-UTF-16-unit query and a 4,096-unit candidate limit. Expanded history offers Copy. Arbitrary substring/case-changing replacement and multiline insertion remain on the validated range path.
- If a field exposes no usable caret bounds (including text-marker and preceding-glyph probes), invocation shows a brief notice rather than guessing a ghost location or opening history automatically.
- Unicode key injection is a dispatched-input route, not destination acknowledgement. The project does not promise one-step undo or correct rendering in opaque hosts based on a successful dispatch.
- IME/dead-key composition, non-US layouts, secure fields, mixed monitor scale/full-screen positioning, delayed consumers, and revoked permissions still need the product's full cross-app matrix.

## Clipboard and fixture scope

Core tests use named pasteboards and temporary databases. Native E2E deliberately uses the actual clipboard and live Ditto capture with generated fixture text; these fixture rows can appear in history. No personal clipboard payloads or document snapshots are included in logs or source control. Paste transactions restore the previous clipboard only after destination readback and only while they still own it; they never replay an uncertain insertion.


## Placeholder mask checkpoint — 2026-11-02

Current automated checks: **26 tests passed**. These cover exact controlled RGB colors at 1x/2x, caret transparency, input-bounded geometry, capture dithering, visually blank rich-text paragraphs, and the rule that an initial suggestion cannot draw inline without a mask. A signed release build and strict signature verification succeeded.

Screen Recording is enabled. The first capture triggered a system notification that the user handled after the automation tool rejected access to UserNotificationCenter. No bypass was attempted.

Latest live run: **failed overall** at the gray fixture (#222529), where no mask appeared. The preceding dark (#111111) and white fixtures passed: no draft mutation or focus theft, zero maximum channel error in the checked exposed background area, no remaining placeholder pixels there, mask removal on typing, Esc dismissal, Tab acceptance, and undo. The striped fixture was not reached in that final run. Earlier failed attempts are not counted as passes.

A live capture introduces one-level color variation even on a solid field. The sampler now selects an observed color within a tightly bounded noise range, retaining conservative ambiguity rejection. The measurement compares rendered before/after captures in the same converted color space; it does not equate internal RGB components with an independently color-converted pixel value. This still does not prove full-glyph, wrapped-placeholder, arbitrary-texture, or every-profile matching.

The native `mask` scenario uses a disposable custom NSTextView with placeholder text. It is not Slack/T3 compatibility proof. Those actual apps have not passed a live mask check. The stronger presentation guard now treats structural whitespace as visually blank and prevents any unmasked initial inline suggestion; a rejected or unavailable mask uses a below-line preview.

The prior TextEdit regression results above belong to the preceding revision; native completion regression has not been rerun for this checkpoint. The full live-mask and cross-app handoff gate remains open. Generated test reports and screenshots stay under ignored `.build/`; personal clipboard payloads and machine permission data are not committed.

## Live mask fixes — 2026-11-02

The subsequent mask suite passed all three solid backgrounds and the striped-background fallback. The capture and mask now preserve the sampled RGB color profile. A new Display P3 regression reproduces the previous incorrect conversion (40/80/120 became 22/81/123); the fixed sampler and renderer preserve components at both 1x and 2x. A replay of the actual ScreenCaptureKit gray distribution exposed a separate two-dominant-color heuristic; several significant adjacent quantization levels are now accepted while the existing two-color texture rejection remains. All sampled channels remain within the original two-level span and one level of the chosen observed color.

A stronger live assertion also found that the initial mask's stale-region guard cancelled completion after typing. Typing now clears mask state before validating the updated query. Fresh live checks confirm Tab still accepts after typing on every solid background. The measured exposed background area has maximum RGB error 0 for dark/white and 1 for gray, with no remaining placeholder pixels above that tolerance. Esc, empty-field acceptance, undo, and texture fallback passed. **28 automated tests passed.** These fixture results do not establish actual Slack/T3 compatibility; those checks are in progress.

## Actual rich-text composer checks — 2026-11-02

Actual T3 passed 13 assertions including the runner result: compact non-focus-stealing suggestion, fresh clipboard candidate, empty draft unchanged on invoke, visible placeholder mask, Escape, real typed query, Tab acceptance, clipboard preservation, one-step acceptance undo, and test-draft cleanup without sending. Initial range geometry was invalid (zero character bounds and an editor-sized text-marker rectangle); a matching accessible placeholder supplies the missing initial layout. The editor's initial synthetic newline disappears on first typing, so it is normalized only with evidence of the empty rich-text layout.

The capture also exposed the automation pointer's shadow crossing the sampled border. Moving that pointer below the strip let the strict mask check pass. A contaminated sample remains a below-line preview rather than an excuse to weaken color thresholds.

Actual Slack passed invocation, visible masking, Escape, query typing, Tab completion, and clipboard preservation. Its subsequent acceptance-undo assertion failed. The later UI observation showed a different Slack view, so the final run needs an uninterrupted idle window and records both undo state and focused-element identity before classifying that failure. It is not counted as a full-suite pass. The inset empty-paragraph layout supplies initial Slack cursor geometry. A fallback without space below a field now moves above it.

The latest 28 automated tests pass, and the signed app builds. The final TextEdit regression, full Slack undo/cleanup check, and a current T3 confirmation remain pending the requested idle window. Ghostty's earlier tool denial is still respected; WhatsApp and current browser versions remain unverified. No messages were sent by the composer tests.

## Final pre-merge checks — 2026-11-02

The current signed build passed the full live mask run (27 passing assertions including runner) and TextEdit automatic completion (17 passing assertions including runner). The forced-event TextEdit rerun stopped safely when the foreground switched to Chrome; its earlier full pass remains historical, not a current pass.

The uninterrupted Slack run established native undo grouping: after successful completion, Undo produced an empty readable field while the same AX element remained focused. It clears the query and paste together. This is now an explicit per-app behavior in the PRD and runner rather than a promise of identical undo grouping across editors. The updated Slack expectation/cleanup sequence has not yet completed another live run. T3’s full visible-mask, completion, undo, and cleanup pass is recorded above.

The user explicitly requested merging PR #1. Merge is a source-control action and does not satisfy the remaining product handoff gate. Ghostty testing is tool-blocked; WhatsApp and current browser builds remain unverified. No claim of universal completion or a fully finished product is made.

## Silent invocation diagnosis — 2026-11-02

The user reported no response in T3 after the normal build had been running for several hours. Live logs recorded each global invocation with Accessibility enabled but no destination check afterward. Carbon reported `IsSecureEventInputEnabled() == true`, and the OS session’s secure-input owner PID resolved to Google Chrome. The invocation returned before reading the target, as intended for Secure Input, but silently.

The blocked path now logs its specific reason and shows a brief non-activating notice asking the user to leave password entry and retry. It does not disable Secure Input, close Chrome, or capture session keystrokes while blocked. Runtime completion remains blocked until the owning app releases Secure Input. A successful build or a running process does not establish live completion readiness.
