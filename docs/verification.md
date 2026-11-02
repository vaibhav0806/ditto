# Native prototype verification

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
