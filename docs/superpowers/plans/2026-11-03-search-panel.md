# Native search-panel refresh implementation plan

Execute inline using executing-plans. The user explicitly requested implementation after the email review; no subagents and no additional execution-approval round.

**Goal:** Ship the reviewed expanded search UI while preserving the two-query paste-session contract.

**Architecture:** Keep OverlayModel and AppController as the state/action owners. Replace the expanded SwiftUI button stack with an AppKit material panel containing a native search field, NSTableView, independently scrolling NSTextView preview, metadata, and Actions menu. Core presentation helpers handle placement and bounded text presentation.

**Tech Stack:** Existing SwiftPM, AppKit, Combine, DittoCore; macOS 13+; no dependencies.

**Spec:** product.md, Reviewed search-panel redesign (2026-11-03).

## Global constraints

- 680 × 440 pt; 52 pt header, 34 pt rows, 36 pt footer, 58/42 body split.
- Existing matching and separate history/host queries remain unchanged.
- Preserve compact autocomplete, capture, guarded insertion and clipboard transactions.
- Native colors/materials, accessibility, reduced motion/transparency; original selectable preview text.
- No pinned-first reordering, quick-paste digits, or delete-undo expansion.

## Review focus

- Carets at all screen edges and multiple display origins: panel stays visible and flips above where possible.
- History entry with leading blank lines, emoji or very long text: readable title, bounded preview, original clipboard text untouched.
- Filtering then Escape: original host query remains unchanged, including after an empty search result.
- Keyboard selection and mouse selection: search remains usable, selection scrolls into view, Enter/Copy destination is correctly labeled.
- Dark/light appearance, no matches, reduced transparency: stable layout and readable text.

## Tasks

### 1. Presentation boundaries

Files: add Sources/DittoCore/HistoryPresentation.swift and Tests/DittoCoreTests/HistoryPresentationTests.swift; register in Tests/DittoCoreTests/main.swift.

- [ ] Write failing checks for HistoryPresentation.frame(caret:screen:), rowTitle(_:), preview(_:), and selection movement at list boundaries. Test screen edges and nonzero origins, empty/whitespace leading lines, emoji and 5,000-character truncation. Verify failure before implementation.
- [ ] Implement these bounded helpers; run swift run DittoTests and verify the full suite.

### 2. Native search UI

Files: add Sources/Ditto/HistoryPanel.swift; replace old expanded UI in Sources/Ditto/Overlay.swift; wire destination labels and history-only boundary selection in Sources/Ditto/AppController.swift.

- [ ] Implement the native header, material, 34 pt accessible table rows, source icons, independently selectable preview, source/time/size metadata and explicit empty states.
- [ ] Implement native Actions/Command-K, Copy, Pin and Delete using existing callbacks. Keep all destructive actions explicit and preserve text-field Copy behavior.
- [ ] Apply helper placement, stable panel dimensions, and reduced-transparency material fallback. Build the executable to verify AppKit interfaces.

### 3. Verify and deliver

Files: existing native verification infrastructure, docs/verification.md and product.md as needed.

- [ ] Render controlled fixtures in the actual native panel in dark/light and long/empty/no-result states; inspect screenshots.
- [ ] Check query focus, selection, Actions, Escape and original host-query preservation with real native events where permissions permit. Do not count Secure Input or focus-interrupted checks as passes.
- [ ] Run full automated checks, signed release build and strict signature verification. Commit/push each completed increment, open/link the UI PR, launch normal app, and report actual verification separately from remaining limitations.

## Rulings

- Native NSTableView/NSTextView are used rather than a new web view or a new package; they supply selection/accessibility and preserve selectable original preview text.
- Opening/closing animations are optional polish; correctness, reduced-motion behavior and stable placement take priority over scale animation in the first native refresh.
