# macOS clipboard autocomplete: OSS implementation research

Research date: 2026-11-02. Scope: Ditto's agreed shortcut → ghost suggestion at the cursor → type to filter clipboard history → accept flow, including browsers, editors, chat apps, and terminals.

## Findings that change our direction

**Yes, the building blocks have already been implemented in public projects.** There are multiple recent macOS autocomplete apps, mature text expansion engines, and native clipboard managers to learn from. A normal menu-bar app with an event tap, a non-activating overlay, and keyboard/paste insertion is the best-supported starting architecture. The research does not establish a requirement to install Ditto as an input source or modify shell startup files.

Our earlier conclusion about Ghostty was too broad. An unsuccessful selected-range/read-write probe establishes a limitation of that adapter, not the impossibility of system-wide completion. Clipboard matching can use the text entered during an explicitly invoked session; it does not inherently require reading or modifying the destination's entire document through Accessibility.

This does **not** establish that any surveyed project delivers the full Ditto experience in every app. Source code, README claims, unmerged experiments, and observed compatibility are different evidence. Several close alternatives explicitly exclude shell prompts or terminals. The remaining engineering problem is compatibility and exact caret placement, not inventing a new macOS input platform.

## Scope and evidence

- Screened **38 distinct public projects**, emphasizing projects created or active during November 2024–November 2026. Older foundational projects were included deliberately: Espanso, Maccy, Hammerspoon, CopyQ, Clipy, Karabiner, and Ghostty.
- Collected more than 340 upstream source, documentation, and license files into a temporary read-only research workspace. Collection is not equivalent to reviewing every line. The implementation findings below identify the particular files examined.
- Used GitHub repository metadata, pinned source snapshots, official project documentation, and relevant issue/PR patches. The appendix records immutable revisions and the scope of each inspection. This is a substantial targeted survey, not an exhaustive audit of every GitHub macOS repository.
- Did not install or execute upstream apps, change shell configuration, open Chrome tabs, or run foreground E2E tests during this research. Upstream test counts and compatibility statements are attributed to their maintainers, not represented as our results.
- Licenses in the inventory are GitHub-reported classifications unless noted as manually checked. A public repository is not automatically open source or suitable for copying into Ditto.

## The user's actual Ghostty suggestion provider

A read-only check of the local zsh configuration found `zsh-autosuggestions` and `zsh-syntax-highlighting` enabled through Oh My Zsh. The autosuggestions plugin is installed in the Oh My Zsh custom plugin directory. Its local source uses zsh's `POSTDISPLAY` to show the suggested suffix after `BUFFER`, highlights that suffix, and accepts it by extending the line buffer. Its history strategy searches shell command history.

**The gray completion shown in the user's screenshot comes from zsh-autosuggestions, rather than Ghostty generating it.** Syntax highlighting is a separate enabled plugin responsible for coloring. No command history contents were read to establish this. The checked upstream implementation is [widgets.zsh](https://github.com/zsh-users/zsh-autosuggestions/blob/85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5/src/widgets.zsh), [highlight.zsh](https://github.com/zsh-users/zsh-autosuggestions/blob/85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5/src/highlight.zsh), and [history.zsh](https://github.com/zsh-users/zsh-autosuggestions/blob/85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5/src/strategies/history.zsh); [Ghostty's shell-integration documentation](https://ghostty.org/docs/features/shell-integration) describes its separate prompt, cursor, directory, and navigation features.

This gives us the precise interaction reference. Its rendering technique is specific to zsh's own line editor, so it is useful for behavior and matching rather than a drop-in way to render inside WhatsApp or a browser.

## Closest implementations and what they actually show

### 1. KeyType — broad native autocomplete with explicit app policies

MIT. Created May 2026. Its Swift packages separate context capture, caret geometry, completion UI, app compatibility, and text insertion. Its insertion planner selects clipboard paste, paste-and-match-style, or chunked Unicode injection according to the app policy; it can request an exact selection replacement or delete a bounded correction tail.

The important counterweight to its broad positioning is the actual defaults: Ghostty and several terminal emulators receive a terminal policy with Tab shortcuts disabled and a text-mirror overlay. Apple's Terminal is explicitly disabled. This is a useful architecture reference, not proof that Tab ghost completion works in every terminal. Its timed clipboard restore also should not be copied as proof that a target has consumed a paste.

Read: [TextInsertion.swift](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/TextInsertion/Sources/TextInsertion/TextInsertion.swift), [DefaultOverrides.swift](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/AppCompatibility/Sources/AppCompatibility/DefaultOverrides.swift), [AXCaretGeometryResolver.swift](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/MacContextCapture/Sources/MacContextCapture/CaretGeometry/AXCaretGeometryResolver.swift), [GhostTextOverlayWindow.swift](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/CompletionUI/Sources/CompletionUI/GhostTextOverlayWindow.swift).

**Ditto lesson:** retain one native app and separate insertion/geometry policies. We need the input and overlay mechanics, not its AI model machinery. Evaluate terminal behavior independently of the README's system-wide description.

### 2. Inkling — small, understandable event-tap/overlay/insertion implementation

MIT. Created June 2026; described as work in progress. Its event tap recognizes acceptance/dismissal, its context provider reads focused input through Accessibility, and its overlay draws suggestions without embedding into the host app. The geometry resolver tries character bounds, text-marker geometry, measured text, related elements, and restricted field-frame anchoring. An Electron helper enables accessibility for a process.

Insertion posts tagged Unicode keyboard events. The source's universal-insertion comment is a claim, not a measured compatibility matrix. In particular, its low-level text loop handles individual UTF-16 units; that is something to review for emoji and combining sequences rather than copy unquestioningly.

Read: [EventTapController.swift](https://github.com/dafuct/Inkling-macOS/blob/5f5763e703967b169c17aaac0cef0767c4c866da/Sources/Inkling/EventTapController.swift), [FocusContextProvider.swift](https://github.com/dafuct/Inkling-macOS/blob/5f5763e703967b169c17aaac0cef0767c4c866da/Sources/Inkling/FocusContextProvider.swift), [TextInserter.swift](https://github.com/dafuct/Inkling-macOS/blob/5f5763e703967b169c17aaac0cef0767c4c866da/Sources/Inkling/TextInserter.swift).

**Ditto lesson:** this is a close minimal reference for the missing user experience. Caret geometry needs several routes; inability to set an AX text selection should not automatically prevent trying a normal insertion route.

### 3. Cotabby — substantial compatibility work, with exact Ghostty/WhatsApp leads

AGPL-3.0. Created April 2026. Its main branch separates insertion strategy selection, insertion eligibility, session reconciliation, and presentation. Its pixel-based caret locator uses ScreenCaptureKit when host geometry is insufficient. That is a real alternative, but it carries a Screen Recording permission and much more complexity; it should not become Ditto's default simply because it exists.

Read: [InsertionStrategySelector.swift](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Suggestion/Acceptance/InsertionStrategySelector.swift), [InsertionSafetyGate.swift](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Suggestion/Acceptance/InsertionSafetyGate.swift), [TerminalAppDetector.swift](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Focus/Applications/TerminalAppDetector.swift), [PixelCaretLocator.swift](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Services/Presentation/PixelCaretLocator.swift).

Two open, **unmerged** PRs are unusually relevant:

- [PR #855: terminal screen fields and Ghostty](https://github.com/FuJacob/cotabby/pull/855). Its patch removes Ghostty from the blocked terminal list and compares the caret's line instead of the entire screen. The rationale is that status/output redraws otherwise retire suggestions. It also filters whitespace from the after-caret comparison. That last behavior is too broad to accept uncritically: it could conceal meaningful whitespace edits. This is a concrete experimental lead, not shipped or personally verified terminal support. Inspected head: `36d59dee4490bbb969f0ccd269ede1f18a1ba589`.
- [PR #853: empty WhatsApp fields](https://github.com/FuJacob/cotabby/pull/853). It handles zero-length reads as empty strings when WhatsApp returns no value, accepts zero-width caret rectangles with positive height, and positions an indicator using the field's own frame. These address exactly the sort of empty-composer failures Ditto must test. Still unmerged at inspection. Inspected head: `8ce0a70c5afa999529bcb2f0320bc82f4979e45f`.

**Ditto lesson:** use these as targeted experiments and regression cases. Do not label the app unsupported after one generic AX failure. Do not import AGPL code into a differently licensed product without first deciding the licensing direction.

### 4. Pretype and TabType — practical injection, qualified terminal support

Both MIT, created June/July 2026. Pretype's injector posts tagged Unicode event chunks, avoids cutting a surrogate pair between chunks, clears inherited modifiers, and distinguishes terminal deletion counting from AppKit deletion. This is more concrete than simply calling a generic typing helper.

Its README qualifies terminal support to AI-agent prompts rather than ordinary shell commands. TabType likewise says it offers suggestions in agent prompts and not at the shell. Those are product/support restrictions; they do not prove a clipboard-only, explicitly invoked tool cannot support shell input.

Read: [TextInjector.swift](https://github.com/nikiomori/Pretype/blob/92f9c3ad52975a6c42a50ef6023140eec92c2dad/Sources/Pretype/TextInjector.swift), [KeyTap.swift](https://github.com/nikiomori/Pretype/blob/92f9c3ad52975a6c42a50ef6023140eec92c2dad/Sources/Pretype/KeyTap.swift), [README](https://github.com/nikiomori/Pretype/blob/92f9c3ad52975a6c42a50ef6023140eec92c2dad/README.md), [README](https://github.com/nilava/TabType/blob/b75ea0e22bc565e57b133b2625a49d7e8a24c789/README.md).

**Ditto lesson:** study event construction and Unicode handling, while keeping Ditto's explicit shortcut and clipboard-only matching. Do not confuse AI prose-completion exclusions with a technical impossibility of clipboard insertion.

### 5. AutoComp — a keystroke buffer when AX context is missing

Apache-2.0. Created May 2026. `KeystrokeBufferFallback` keeps bounded recent typing, labels derived context as low trust, has a TTL, associates it with the target, and resets on pointer/navigation/shortcut events or unsupported input-method state. It uses a keyboard-layout translator, not simply a US key-code table.

Read: [KeystrokeBufferFallback.swift](https://github.com/ThalesMMS/AutoComp/blob/a425cca162c745fff2ca5d582ae9f1261549d83f/Sources/AutoCompApp/Services/KeystrokeBufferFallback.swift), [CapturedInputEvent.swift](https://github.com/ThalesMMS/AutoComp/blob/a425cca162c745fff2ca5d582ae9f1261549d83f/Sources/AutoCompApp/Services/CapturedInputEvent.swift).

**Ditto lesson:** an explicit Ditto session can track its own query. Destination text is useful for verification and richer compatibility, but should not be a universal dependency of the search engine. Captured keystrokes still are not guaranteed to equal committed document text: composition, autocorrection, dead keys, modal editors, and app shortcuts must be handled or cause the session to end.

### 6. Veloop — the closest clipboard-at-caret product lead, with a caveat

MIT. Created August 2026. It has dedicated clipboard capture/policy/snapshot/restoration components, an event-tap subsystem, paste injection, and a caret locator. Its caret locator first queries an external named CFMessagePort service and then falls back to focused Accessibility geometry, with explicit confidence/failure states.

Read: [CaretLocator.swift](https://github.com/talentdedcat/Veloop/blob/dda9f1f17583fff8396af38ee477b9824e10934e/Sources/Core/Overlay/CaretLocator.swift), [FocusedAccessibilityCaretClient.swift](https://github.com/talentdedcat/Veloop/blob/dda9f1f17583fff8396af38ee477b9824e10934e/Sources/Core/Overlay/FocusedAccessibilityCaretClient.swift), [PasteboardCapturer.swift](https://github.com/talentdedcat/Veloop/blob/dda9f1f17583fff8396af38ee477b9824e10934e/Sources/Core/Clipboard/PasteboardCapturer.swift), [PasteEventInjector.swift](https://github.com/talentdedcat/Veloop/blob/dda9f1f17583fff8396af38ee477b9824e10934e/Sources/Core/Input/PasteEventInjector.swift).

**Ditto lesson:** highly relevant clipboard and caret decomposition. But the external caret service is a dependency to understand; the presence of an IPC client does not prove Veloop alone can locate every app's caret. This small project was source-inspected, not installed or validated.

## Mature foundations worth learning from

### Espanso: text replacement already works without becoming a keyboard input source

GPL-3.0. Its macOS detector uses an event tap; its matcher handles typed trigger sequences; its injector posts Unicode or key events. The official documentation describes an automatic choice between key injection for short text and clipboard insertion for longer text, plus per-app backend configuration.

Read: [native.mm](https://github.com/espanso/espanso/blob/80d9e353e3c0a58c77feb72671cec4a61958366f/espanso-detect/src/mac/native.mm), [native.mm](https://github.com/espanso/espanso/blob/80d9e353e3c0a58c77feb72671cec4a61958366f/espanso-inject/src/mac/native.mm), [matcher.rs](https://github.com/espanso/espanso/blob/80d9e353e3c0a58c77feb72671cec4a61958366f/espanso-match/src/rolling/matcher.rs), and [official backend documentation](https://espanso.org/docs/matches/basics/).

**Ditto lesson:** keep more than one insertion backend. Trigger/query tracking and replacement are established work. Espanso's trigger expander does not supply Ditto's ghost rendering, and its deletion/injection behavior is not automatically safe for every Unicode sequence or destination.

### Maccy and Clipy: reliable history capture is a separate, ordinary job

Both MIT. Maccy's `Clipboard.swift` polls the pasteboard change count, captures supported data types, filters transient/concealed/generated types, and tags its own clipboard writes. Its paste path resolves the shortcut for keyboard layout and posts normal paste events. The source credits Clipy's paste implementation.

Read: [Clipboard.swift](https://github.com/p0deje/Maccy/blob/f0b571e32e4031d7b91ba811f50d0f33e8e5548b/Maccy/Clipboard.swift), [README](https://github.com/Clipy/Clipy/blob/8d23bbc5669f10be4618dc2988c253ba82acbd68/README.md).

**Ditto lesson:** fixing history capture does not depend on solving ghost text or installing an input source. Copy → detect → persist → retrieve needs its own tests. Ditto should distinguish paused capture, an empty store, an excluded item, and failed capture instead of presenting the same empty window for all of them.

### Handy: a stronger clipboard-restore idea than a fixed delay

MIT. Its macOS paste transaction publishes promised clipboard data. An NSPasteboard owner callback records when a consumer requests text, and the transaction waits for read activity to settle before guarded restoration. Change-count checks prevent overwriting a newer copy, and concealment markers discourage eager clipboard managers from reading the payload.

Read: [macos.rs](https://github.com/cjpais/Handy/blob/4ec61f05d50d0d4a70e4469d206bbe15fe77d518/src-tauri/src/paste_tx/macos.rs) and [input.rs](https://github.com/cjpais/Handy/blob/4ec61f05d50d0d4a70e4469d206bbe15fe77d518/src-tauri/src/input.rs).

**Ditto lesson:** investigate receipt-aware clipboard preservation for destinations where AX readback is unavailable. A receipt proves a consumer requested data, not that the intended editor inserted the right text; another reader can trigger it. It improves timing evidence but does not replace an end-to-end assertion. Any auto-submit behavior in a dictation app is irrelevant to Ditto and must remain absent.

### Hammerspoon, RuSwitcher, keyboop, swift-system-input

Hammerspoon's native event-tap implementation posts Unicode text and exposes active event interception without an input-method installation. RuSwitcher uses event taps, event tags, and typing-buffer logic for layout correction. Keyboop's source keeps a bounded typing session and resets it when navigation invalidates the cursor assumption. The small swift-system-input package illustrates selected-text retrieval and a change-count-guarded temporary clipboard paste.

Read: [libeventtap.m](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/libeventtap.m), [KeyboardMonitor.swift](https://github.com/rashn/RuSwitcher/blob/665421e20e5a100f9689aefbd122c2428b0da8cb/macos/Sources/RuSwitcher/KeyboardMonitor.swift), [KeystrokeBuffer.swift](https://github.com/iffuno/keyboop/blob/fb9bdde4eb8f13a486974cf102a8bec9d607e5d2/Sources/Keyboop/KeystrokeBuffer.swift), [SystemInput+Injection.swift](https://github.com/arraypress/swift-system-input/blob/04067cfb2b2f73184ff1adc3fe3878e18bb54e46/Sources/SystemInput/SystemInput%2BInjection.swift).

**Ditto lesson:** own a small, explicit session and ignore our own synthetic events. Reset when its assumptions become invalid. These are references, not dependencies we need to ship. Correcting a recently typed word and reliably replacing an arbitrary clipboard search query are related but not identical problems.

## Why InputMethodKit is not a justified default requirement

VietTelex is an especially useful counterexample. It is a real input method, yet its terminal support deliberately bypasses IMKit: its source explains that marked text can hold partial input away from the shell and interfere with shell autocomplete. A CGEventTap passes ordinary terminal keys through and synthesizes edits when needed.

Read: [TerminalTap.swift](https://github.com/ptrinh/viettelex/blob/10af22de363181ee419127417ff579dfe4a8e000/App/Sources/TerminalTap.swift), [MACOS_IME_NOTES.md](https://github.com/ptrinh/viettelex/blob/10af22de363181ee419127417ff579dfe4a8e000/docs/MACOS_IME_NOTES.md).

This does not make InputMethodKit useless. It can expose composition and candidate positioning through cooperating text clients, and may deserve a later experiment. It does mean that “install Ditto as an input source and terminals will work universally” was not a supported conclusion. It adds setup and still needs compatibility work. We should first test the simpler event-tap/overlay approach used by the closer projects.

## What Ghostty's own source clarifies

At the pinned upstream revision, `SurfaceView_AppKit.swift` implements `NSTextInputClient` and Accessibility. Its accessibility value is cached screen content; its selected text range calls a terminal selection API. Its `firstRect(forCharacterRange:)` uses Ghostty's IME-point API for positioning. These represent different things: selected terminal screen text is not necessarily the shell's insertion cursor or editable command range.

Read: [SurfaceView_AppKit.swift](https://github.com/ghostty-org/ghostty/blob/042b16b6146ada29877dfeeea9f286889e4adeb1/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift).

That makes our earlier range-based adapter a poor universal assumption. It also gives a useful geometry research lead. **An in-process `NSTextInputClient` method is not automatically callable by an unrelated app**, so this source does not establish that Ditto can obtain that IME rectangle through AX. The upstream revision is not a measurement of the user's installed Ghostty version.

## Terminal-only and desktop-utility alternatives

- **sill / Figxit / easy-complete:** valuable terminal completion references. sill and Figxit explicitly use shell adapters that know the command buffer and cursor. Figxit documents terminal-reported cursor-cell geometry outside tmux and pane geometry in tmux. Their clean geometry is enabled by shell cooperation; it is not evidence for an equivalent hook-free, any-app API. Read [README](https://github.com/domus-apps/sill/blob/98bc989f4323d2fe56560a57142f2f560d45a9da/README.md), [README](https://github.com/en3sis/figxit/blob/ce573cdff9a4717452b4a3bbf718bbfd8c5c60b7/README.md), [README](https://github.com/chen86860/easy-complete/blob/5d47890019c11a4f2f06179662c26063448257c2/README.md).
- **boring.notch / Ice / SuperCmd / tinycast:** useful menu-bar, floating UI, hotkey, and macOS utility references. The survey does not establish that notch animation or menu-bar management solves host text insertion/caret discovery. They are adjacent projects, not the primary stack to copy.
- **Karabiner-Elements:** valuable keyboard-event infrastructure, but a remapping/driver stack is disproportionate for the current clipboard-completion requirement. Nothing found establishes that Ditto needs a virtual keyboard driver.
- **CopyQ / Copy / Buffer / PasteBar:** clipboard organization and persistence references. PasteBar's actual license is CC BY-NC with a limited commercial exception, so it is source available with restrictions, despite its README's open-source wording. tinycast's actual LICENSE is AGPL-3.0-or-later although GitHub metadata reports NOASSERTION. `laststance/complete` had no detected license; no permission to reuse its implementation is assumed.

## Recommended Ditto architecture, based on this evidence

Keep the product simple for the user: one menu-bar app, one shortcut, clipboard history, and a suggestion at the cursor. No model download, shell plugin, or Input Sources setup in the baseline proposal.

1. **Clipboard history:** keep it independent of completion. Poll change counts, retain allowed text locally, distinguish own writes, and preserve explicit pause/exclusions. Use Maccy's design as the main reference.
2. **An explicit session:** `⌥⌘V` captures destination identity and starts a bounded in-memory query. Ordinary typing continues into the destination. Use committed text where reliable; use event-derived text conservatively when it is not. Do not require a writable AX range merely to start matching.
3. **A caret resolver:** try actual AX range bounds, accept valid zero-width rectangles, then text-marker/related-element routes where implemented. Enable Chromium/Electron accessibility once when appropriate. Validate multi-monitor coordinate conversion. Treat measured geometry and guessed geometry differently.
4. **A non-activating overlay:** show ghost text without stealing focus. Font, baseline, clipping, and visibility are acceptance criteria. A large history window must remain explicit. Screen-pixel analysis is an optional experiment only if simpler methods demonstrably cannot meet the caret requirement.
5. **An insertion router:** use the least invasive working route for that field: append a suffix for an exact prefix where appropriate; guarded range replacement where AX is reliable; normal paste or Unicode/key insertion where AX writing is absent. Terminal support must not depend on AX selection being writable. Reset on an app/field switch, pointer navigation, composition we cannot track, or loss of session confidence.
6. **Readback and ownership:** verify actual text when the host exposes it. Where it does not, obtain the strongest available evidence and label the route unverified until real-app tests establish it. Never retry an uncertain insertion automatically. Preserve clipboard ownership so a newer user copy wins.

This is an architecture recommendation, **not a claim of an implemented fix**. It does not silently relax `product.md`'s requirement against blind deletion. An exact prefix can often be completed without deleting the query. Case-insensitive or substring matches require replacing the session's typed text; that path must be proven for the destination rather than justified by a key count alone. An event-derived query may differ from committed text. If a terminal or modal editor does not expose enough confirmation, the experiment must establish a bounded replacement rule before supporting it.

There are two UX details to settle during the prototype, without adding setup burden: how to preview a substring match that is not a literal continuation, and how to present a temporary lack of reliable caret geometry without recreating the rejected popup. Neither should be hidden behind a claim of universal support.

## Verification required before handing Ditto back

These are planned acceptance checks, not results from this research.

| Target | Required checks |
| --- | --- |
| Native editor (TextEdit) | Empty and populated field; cursor mid-document; copy → capture → invoke → type → cycle → Tab; Esc; history; undo. |
| Chrome and Safari | Input, textarea, contenteditable; empty field; zoom and wrapping; focus change; password field exclusion. |
| Electron editor | Ordinary editor and embedded terminal separately; lazy AX tree; editor's own completion; no key leakage. |
| WhatsApp | Empty and populated composer; valid zero-width caret; multiline clip; acceptance does not send a message. |
| Ghostty | zsh prompt and the user's existing autosuggestions enabled; blank and populated prompt; redraw; wrapped command; Tab belongs to Ditto only during its active session; no command execution. |
| Terminal and iTerm2 | Verify independently rather than infer from Ghostty; shell mode versus agent prompt; multiline content and paste behavior. |
| Cross-app failures | Switch app/window/field immediately before acceptance; click elsewhere; clipboard changes during insertion; delayed paste consumer; revoked permission; no duplicate paste. |
| Text and layout | Emoji and ZWJ; combining accents; Hindi; non-US layout; held shortcut modifiers; IME/dead keys; multiple displays and scale factors. |
| Presentation | Suggestion is actually visible, correctly placed, and sized; no focus-stealing window; screenshot evidence in addition to text assertions. |

Report build/unit results, internal-fixture results, upstream claims, and actual cross-app E2E separately. A route stays incomplete until it has been exercised in the intended app. Normal password/secure-input exclusions are expected; they should not be used to justify excluding ordinary WhatsApp or terminal input.

## Prioritized reuse plan

- First: **Maccy** for capture; **Inkling / KeyType** for the overlay/context separation; **AutoComp** for conservative query tracking; **Espanso / Pretype** for insertion backends and Unicode/event handling.
- Targeted experiments: **Cotabby #855/#853** for terminal redraw and WhatsApp, **Ghostty's source** for the range/cursor distinction, **Handy** for clipboard read receipts, **Veloop** for clipboard-at-caret design.
- Keep InputMethodKit, screen capture, shell adapters, and keyboard drivers as separately justified alternatives, not installation requirements chosen before testing the ordinary approach.
- No upstream implementation code was copied into Ditto in this research. If code is reused later, preserve required notices and resolve its license before inclusion. Prefer permissively licensed implementation references where they meet the requirement; GPL/AGPL sources remain useful evidence without copying their code.

## Inventory and reproducible revisions

“Code” means the specific relevant implementation files were inspected; it does not mean the whole project was audited. “Docs” means repository/product documentation and metadata were screened, without validating the claimed behavior. Dates below are GitHub repository creation dates, not the date the feature shipped. Revisions are immutable snapshot links. Existing projects were included alongside recent ones because they contain mature implementations.

| Project | Created | License classification | Inspection / relevance | Pinned revision |
| --- | --- | --- | --- | --- |
| [espanso/espanso](https://github.com/espanso/espanso) | 2019-08-30 | GPL-3.0 | Code: macOS detection, matching, Unicode injection | [`80d9e353e3`](https://github.com/espanso/espanso/tree/80d9e353e3c0a58c77feb72671cec4a61958366f) |
| [p0deje/Maccy](https://github.com/p0deje/Maccy) | 2018-01-31 | MIT | Code: capture, type filtering, paste shortcut | [`f0b571e32e`](https://github.com/p0deje/Maccy/tree/f0b571e32e4031d7b91ba811f50d0f33e8e5548b) |
| [hluk/CopyQ](https://github.com/hluk/CopyQ) | 2009-10-21 | GPL-3.0 | Docs: cross-platform history foundation | [`37fa0c801e`](https://github.com/hluk/CopyQ/tree/37fa0c801e9cbab730a4e3f87afca0385e1bec97) |
| [Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon) | 2014-10-08 | MIT | Code: event taps and Unicode posting | [`23e387e280`](https://github.com/Hammerspoon/hammerspoon/tree/23e387e2805a9890066366e0ac96c71b27f0cfd5) |
| [johnbean393/KeyType](https://github.com/johnbean393/KeyType) | 2026-05-31 | MIT | Code: insertion, app overrides, caret/overlay | [`21df2cc1f5`](https://github.com/johnbean393/KeyType/tree/21df2cc1f5271d3712d567e3c2491ac09174caf3) |
| [dafuct/Inkling-macOS](https://github.com/dafuct/Inkling-macOS) | 2026-06-29 | MIT | Code: event tap, caret ladder, text injection | [`5f5763e703`](https://github.com/dafuct/Inkling-macOS/tree/5f5763e703967b169c17aaac0cef0767c4c866da) |
| [FuJacob/cotabby](https://github.com/FuJacob/cotabby) | 2026-04-04 | AGPL-3.0 | Code + PR patches: compatibility and geometry | [`8cdbea2d26`](https://github.com/FuJacob/cotabby/tree/8cdbea2d2619b0f89a73d46eb0bb856504d07343) |
| [nilava/TabType](https://github.com/nilava/TabType) | 2026-07-15 | MIT | Docs + selected sources; shell exclusions | [`b75ea0e22b`](https://github.com/nilava/TabType/tree/b75ea0e22bc565e57b133b2625a49d7e8a24c789) |
| [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | 2026-06-27 | MIT | Code: Unicode injection and key tap | [`92f9c3ad52`](https://github.com/nikiomori/Pretype/tree/92f9c3ad52975a6c42a50ef6023140eec92c2dad) |
| [uttrflow/uttrflow-swift](https://github.com/uttrflow/uttrflow-swift) | 2026-08-29 | MIT | Code + docs: input routes and compatibility limits | [`4d6bfcad63`](https://github.com/uttrflow/uttrflow-swift/tree/4d6bfcad637a3429c6f88479924084786ba625aa) |
| [ventsislav-georgiev/prosper](https://github.com/ventsislav-georgiev/prosper) | 2026-06-13 | GPL-3.0 | Code: AX caret and app-aware presentation | [`dd5f468696`](https://github.com/ventsislav-georgiev/prosper/tree/dd5f468696b4c375da2a8d6c5f78a4b3142fefa6) |
| [talentdedcat/Veloop](https://github.com/talentdedcat/Veloop) | 2026-08-09 | MIT | Code: clipboard and caret IPC/fallback | [`dda9f1f175`](https://github.com/talentdedcat/Veloop/tree/dda9f1f17583fff8396af38ee477b9824e10934e) |
| [arraypress/swift-system-input](https://github.com/arraypress/swift-system-input) | 2025-10-07 | MIT | Code: selected text and temporary clipboard paste | [`04067cfb2b`](https://github.com/arraypress/swift-system-input/tree/04067cfb2b2f73184ff1adc3fe3878e18bb54e46) |
| [ptrinh/viettelex](https://github.com/ptrinh/viettelex) | 2026-07-18 | MIT | Code + notes: IME with terminal event-tap path | [`10af22de36`](https://github.com/ptrinh/viettelex/tree/10af22de363181ee419127417ff579dfe4a8e000) |
| [cjpais/Handy](https://github.com/cjpais/Handy) | 2025-02-13 | MIT | Code: key mapping and receipt-aware paste | [`4ec61f05d5`](https://github.com/cjpais/Handy/tree/4ec61f05d50d0d4a70e4469d206bbe15fe77d518) |
| [Clipy/Clipy](https://github.com/Clipy/Clipy) | 2015-06-20 | MIT | Docs: clipboard manager / Maccy source lineage | [`8d23bbc566`](https://github.com/Clipy/Clipy/tree/8d23bbc5669f10be4618dc2988c253ba82acbd68) |
| [SuperCmdLabs/SuperCmd](https://github.com/SuperCmdLabs/SuperCmd) | 2026-02-13 | MIT | Docs: adjacent launcher / utilities | [`2da7b9e5de`](https://github.com/SuperCmdLabs/SuperCmd/tree/2da7b9e5dec0199a972a59cece402c85f729d5d7) |
| [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) | 2026-06-29 | AGPL-3.0-or-later (actual file) | Docs + actual LICENSE: adjacent launcher | [`cc96c2dcca`](https://github.com/abue-ammar/tinycast/tree/cc96c2dccaaaa78aafd642e33c840f1710af0032) |
| [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | 2024-08-02 | GPL-3.0 | Docs: adjacent floating desktop UI | [`b7611bbf32`](https://github.com/TheBoredTeam/boring.notch/tree/b7611bbf32c627a3427408fc142486900d71a23f) |
| [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | 2023-08-04 | GPL-3.0 | Docs: adjacent menu-bar management | [`11edd39115`](https://github.com/jordanbaird/Ice/tree/11edd39115f3f43a83ae114b5348df6a0e1741cf) |
| [pqrs-org/Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) | 2016-07-11 | Unlicense | Docs: keyboard remapping/driver alternative | [`670d017a53`](https://github.com/pqrs-org/Karabiner-Elements/tree/670d017a53f73d4d34e5948ce5c796e33a37a3cc) |
| [ThalesMMS/AutoComp](https://github.com/ThalesMMS/AutoComp) | 2026-05-19 | Apache-2.0 | Code: low-trust typing buffer | [`a425cca162`](https://github.com/ThalesMMS/AutoComp/tree/a425cca162c745fff2ca5d582ae9f1261549d83f) |
| [dario-valles/shadowtype](https://github.com/dario-valles/shadowtype) | 2026-06-09 | MIT | Docs + selected source collection: autocomplete lead | [`559f251691`](https://github.com/dario-valles/shadowtype/tree/559f251691b5d7bb84c5cdfafaf9b641a8790b1e) |
| [chen86860/easy-complete](https://github.com/chen86860/easy-complete) | 2026-05-08 | MIT | Docs: terminal completion alternative | [`5d47890019`](https://github.com/chen86860/easy-complete/tree/5d47890019c11a4f2f06179662c26063448257c2) |
| [domus-apps/sill](https://github.com/domus-apps/sill) | 2026-09-02 | MIT | Docs + selected source collection: zsh integration | [`98bc989f43`](https://github.com/domus-apps/sill/tree/98bc989f4323d2fe56560a57142f2f560d45a9da) |
| [en3sis/figxit](https://github.com/en3sis/figxit) | 2026-10-05 | MIT | Docs + selected source collection: shell/cursor bridge | [`ce573cdff9`](https://github.com/en3sis/figxit/tree/ce573cdff9a4717452b4a3bbf718bbfd8c5c60b7) |
| [StanMarek/ghost-complete](https://github.com/StanMarek/ghost-complete) | 2026-03-01 | MIT | Docs: autocomplete lead | [`af8c4b9bc9`](https://github.com/StanMarek/ghost-complete/tree/af8c4b9bc91b5aee47f796745cc481582693f6c0) |
| [frgmt0/typer](https://github.com/frgmt0/typer) | 2026-05-29 | MIT | Docs: autocomplete lead | [`f6db9b4e1b`](https://github.com/frgmt0/typer/tree/f6db9b4e1b33a2df820645f0d87fe273a54096ee) |
| [thousandflowers/Wren](https://github.com/thousandflowers/Wren) | 2026-05-29 | MIT | Docs: limited snapshot; no universal support conclusion | [`0c1846ae62`](https://github.com/thousandflowers/Wren/tree/0c1846ae628a3050f26a784eaf78ba648adcda03) |
| [laststance/complete](https://github.com/laststance/complete) | 2025-11-08 | Not detected | Docs: completion lead; license not detected | [`9dc15ae052`](https://github.com/laststance/complete/tree/9dc15ae05290aa8570c36722524ca08f6b5b79db) |
| [tarikbc/Copy](https://github.com/tarikbc/Copy) | 2026-07-29 | GPL-3.0 | Docs: clipboard UX/storage | [`98ab232c3d`](https://github.com/tarikbc/Copy/tree/98ab232c3de5a646cfc4654c22d839f3dd455e28) |
| [samirpatil2000/Buffer](https://github.com/samirpatil2000/Buffer) | 2026-02-02 | MIT | Docs: clipboard UX/history | [`a1e3a1762f`](https://github.com/samirpatil2000/Buffer/tree/a1e3a1762fe8308a252c8959e3eaafd94f7cc056) |
| [rashn/RuSwitcher](https://github.com/rashn/RuSwitcher) | 2026-04-06 | MIT | Code: event tap and keyboard correction | [`665421e20e`](https://github.com/rashn/RuSwitcher/tree/665421e20e5a100f9689aefbd122c2428b0da8cb) |
| [iffuno/keyboop](https://github.com/iffuno/keyboop) | 2026-06-16 | MIT | Code: bounded typing session buffer | [`fb9bdde4eb`](https://github.com/iffuno/keyboop/tree/fb9bdde4eb8f13a486974cf102a8bec9d607e5d2) |
| [SamGu-NRX/Caret](https://github.com/SamGu-NRX/Caret) | 2026-09-19 | MIT | Code: range/geometry fallback and guarded AX insertion | [`2eef48293f`](https://github.com/SamGu-NRX/Caret/tree/2eef48293fa3cee5b87ea82b39d219c1c30324bb) |
| [PasteBar/PasteBarApp](https://github.com/PasteBar/PasteBarApp) | 2024-04-10 | CC BY-NC + exception (actual file) | Docs + actual license: clipboard UI; restricted reuse | [`bcad6a9dde`](https://github.com/PasteBar/PasteBarApp/tree/bcad6a9dde0681c4e93bf2f2e38a6394a88d7760) |
| [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) | 2022-03-29 | MIT | Code: NSTextInputClient vs terminal selection | [`042b16b614`](https://github.com/ghostty-org/ghostty/tree/042b16b6146ada29877dfeeea9f286889e4adeb1) |
| [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | 2013-10-26 | MIT | Code + local config: actual screenshot provider | [`85919cd1ff`](https://github.com/zsh-users/zsh-autosuggestions/tree/85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5) |

Additional source findings that should not be lost: Caret explicitly distinguishes actual caret geometry from a nearby fallback and verifies AX writes by reading back the expected value; its source also states that app-family lists were not measured in that pass. Uttrflow documents multiple insertion routes and distinguishes code behavior from measured compatibility; its compatibility page still leaves terminals largely unmeasured. These are good reporting disciplines for Ditto, not independent proof of universal completion.

Primary source links: [InlineCaretGeometry.swift](https://github.com/SamGu-NRX/Caret/blob/2eef48293fa3cee5b87ea82b39d219c1c30324bb/apps/mac/Sources/Caret/InlineCaretGeometry.swift), [InlineFieldAccess.swift](https://github.com/SamGu-NRX/Caret/blob/2eef48293fa3cee5b87ea82b39d219c1c30324bb/apps/mac/Sources/Caret/InlineFieldAccess.swift), [TypedTextInsertionEngine.swift](https://github.com/uttrflow/uttrflow-swift/blob/4d6bfcad637a3429c6f88479924084786ba625aa/Sources/UttrflowInput/TypedTextInsertionEngine.swift), [compatibility.md](https://github.com/uttrflow/uttrflow-swift/blob/4d6bfcad637a3429c6f88479924084786ba625aa/Docs/compatibility.md), [PasteboardTextInsertionEngine.swift](https://github.com/uttrflow/uttrflow-swift/blob/4d6bfcad637a3429c6f88479924084786ba625aa/Sources/UttrflowInput/PasteboardTextInsertionEngine.swift).

The initially attempted `PasteBar/PasteBar` path was incorrect; the valid repository is `PasteBar/PasteBarApp` above. The incorrect lookup is excluded from the 38-project count. Repository descriptions and broad “works everywhere” wording were not used as test results.
