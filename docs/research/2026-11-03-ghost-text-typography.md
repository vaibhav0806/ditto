# Exact ghost-text typography: focused OSS research

Research date: 2026-11-03. This follows the broader [macOS input survey](2026-11-02-macos-oss-input-research.md) and the user's report that Ditto still floats above TextEdit text. This is a source review and proposed direction, not a verified rendering fix.

Implementation checkpoint: the independent renderer and native/actual TextEdit glyph comparisons now pass. T3 empty/filled sizing is consistent, but exact host font evidence remains unavailable there. See [current verification](../verification.md#core-text-renderer-and-actual-glyph-validation--2026-11-03). The source review below preserves the pre-implementation findings.

## Decision

Replace label-box alignment with an explicit glyph renderer driven by the focused field's typography and measured baseline. Keep the normal app and `⌥⌘V` session. Do not introduce a table of application-specific pixel offsets.

The user's acceptance criterion is visual continuation of the host text: same face, size, weight, glyph advances, baseline, line pitch and available line width; gray until acceptance. A matching caret rectangle is insufficient evidence.

## What the pre-implementation build actually established

- `TextTarget.font` can read a nearby attributed character, but falls back to a 14 pt system font when it cannot. An empty field provides no character to probe. That fallback is not proof of the current typing font.
- `OverlayController` paints the suggestion in an `NSTextField` sized to the caret box. Matching that box does not give the host's typesetter baseline or paragraph metrics.
- The populated native fixture uses one monospaced 16 pt font. Its baseline assertion uses a view baseline property. The external TextEdit assertion checks the center of the caret/label rectangles, with a 4 pt tolerance. Neither compares the ghost's actual ink with TextEdit's rendering of the accepted words.
- Apple's [`firstBaselineOffsetFromTop`](https://developer.apple.com/documentation/appkit/nsview/firstbaselineoffsetfromtop) describes the view's **alignment rectangle**. It is not an independent screen-pixel measurement. Apple's [`defaultBaselineOffset(for:)`](https://developer.apple.com/documentation/appkit/nslayoutmanager/defaultbaselineoffset(for:)) instead returns a typesetter's baseline for a font, and explicitly notes that typesetter behavior can affect it.

These explain why the earlier green geometry checks did not settle the user's visual report. The remaining TextEdit displacement still needs a rendered reference comparison; it should not be assigned a guessed numeric correction.

## Sources inspected

Read 22 pinned upstream files across four projects, including renderer, font resolver, calibration, layout, and test sources. Files were downloaded into ignored `.build/typography-research/`; no upstream app, build script, or test was executed. Upstream comments and assertions describe their implementation and intended coverage, not our observed compatibility results.

| Project and revision | Relevant implementation | Finding |
| --- | --- | --- |
| Cotabby, AGPL-3.0, `8cdbea2d2619b0f89a73d46eb0bb856504d07343` | [GhostTextPanelView](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Services/Presentation/GhostTextPanelView.swift), [GhostBaselinePolicy](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Presentation/Geometry/GhostBaselinePolicy.swift) | Draws Core Text lines at explicit screen baselines, preserving fractional positions. Uses typesetter metrics for TextKit and different metrics for web engines. This is materially stronger than centering a label. |
| KeyType, MIT, `21df2cc1f5271d3712d567e3c2491ac09174caf3` | [FieldFontResolver](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/KeyType/Logic/Completion/FieldFontResolver.swift), [ScreenshotOverlayCalibrator](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/MacContextCapture/Sources/MacContextCapture/Screen/ScreenshotOverlayCalibrator.swift) | Carries font, paragraph style, baseline offset and line height together. Its calibration compares candidate sizes/positions with captured text and reports confidence. Some paths still use approximate layout/fallbacks; it is not universal exactness proof. |
| Inkling, MIT, `5f5763e703967b169c17aaac0cef0767c4c866da` | [OverlayWindow](https://github.com/dafuct/Inkling-macOS/blob/5f5763e703967b169c17aaac0cef0767c4c866da/Sources/Inkling/OverlayWindow.swift) | Uses an NSTextField and vertical centering, with caret-height-derived font sizing when AX gives no font. Close to our existing approach; not a sufficient solution to the exact typography requirement. |
| CopilotForXcode, MIT, `b59c57aa8c1d777d6c5d7057e9a5fc97ed5b8aab` | [TextCursorTracker](https://github.com/intitni/CopilotForXcode/blob/b59c57aa8c1d777d6c5d7057e9a5fc97ed5b8aab/Core/Sources/SuggestionWidget/TextCursorTracker.swift), [WidgetPositionStrategy](https://github.com/intitni/CopilotForXcode/blob/b59c57aa8c1d777d6c5d7057e9a5fc97ed5b8aab/Core/Sources/SuggestionWidget/WidgetPositionStrategy.swift) | Relies on Xcode editor inspection and positioning. Useful as an editor integration example; not a generic cross-app renderer to adopt. |

## The strongest reusable ideas

### Explicit baseline, not label centering

Cotabby's renderer uses `CTLine` at a supplied baseline. Its layout handles line width and line pitch separately from font size. This avoids a label or SwiftUI text view silently choosing its own padding and line box. Apple's [Core Text line API](https://developer.apple.com/documentation/coretext/ctline) supplies glyph runs, advances, line drawing, truncation and typographic measurement.

Cotabby's policy is not completely app-agnostic: it distinguishes text-engine families, and other parts contain host-specific compatibility/font policies. We should adopt the separation of measurement and rendering, not copy a browser/app identity table or invent a TextEdit adjustment.

### Typography as measured field state

Cotabby's [GhostFontResolver](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Presentation/Style/GhostFontResolver.swift) records where a font came from and checks agreement with the host's measured text width. Its [CaretAdvanceSampler](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Focus/CaretAdvanceSampler.swift) observes caret movement during ordinary typing rather than inserting probe text. This can reveal actual rendered scale when reported font size differs from the display.

Font identity, point size and baseline are separate facts. Matching one sample's width does not uniquely identify a typeface; scaling the wrong face is not exact matching. Paragraph spacing, kerning, ligatures, zoom, variable-font axes and fallback glyphs must also be considered where relevant.

### Bounded pixel calibration when metadata is incomplete

Cotabby's [HostBaselineCalibrator](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Services/Presentation/HostBaselineCalibrator.swift) captures a narrow nearby text strip, caches measurements by field/line, and rejects implausible corrections. Its [TypefaceMatcher](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Support/Presentation/Style/TypefaceMatcher.swift) compares candidate font faces and sizes against actual rendered glyphs. This is an evidence-based alternative to application offsets, but still has confidence limits and requires Screen Recording.

For Ditto, any such sampling should remain narrow, local and in memory, with no saved user screenshots or uploads. Cache by focused field and style evidence; invalidate on font/scale/geometry changes. An empty field has no glyph sample: reported typing attributes, adjacent text or valid cached style are needed. A caret height alone cannot uniquely establish its font.

Cotabby also registers some privately bundled fonts using host trust policies. That is an additional compatibility subsystem, not something to silently import into a minimal renderer. Its AGPL source is a research reference; direct code reuse requires a separate licensing decision. An independent implementation of the general rendering and measurement approach is the proposed path.

### Validate ink against the host, not our own geometry

Cotabby's [GhostTextPixelAlignmentTests](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/CotabbyTests/Support/Presentation/Geometry/GhostTextPixelAlignmentTests.swift) compare a native text view containing the complete text with a prefix-only view plus ghost rendering. They compare ink bounds/centroids across multiple proportional, serif, system and monospace fonts, rather than checking a view rectangle. These tests were inspected, not run here.

Ditto should add that independent reference comparison, then capture the actual target's ghost and accepted rendering of the same generated words. Color can be normalized for geometry comparison. Font/advance agreement, baseline, clipping and wrapping must all be measured. An upstream test suite or our offscreen fixture cannot substitute for TextEdit/browser/chat checks.

## Why host-owned rendering is not an automatic replacement

InputMethodKit/text-input clients can let an input method participate in native composition. However, Apple's [`setMarkedText`](https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:)) changes text storage/selection as composition, and [`IMKInputController`](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller) belongs to an input-method session. This is not a general remote ghost-text API for an ordinary menu-bar app. Composition behavior and terminal/client compatibility would need a separate experiment, as the earlier survey found. Input Sources setup is not a prerequisite established by this research.

## Recommended next experiment

1. Build an independent Core Text ghost view accepting explicit style, pen position and baseline. Keep matching, clipboard capture, insertion and `⌥⌘V` unchanged.
2. Use reported typography and native typesetter metrics first. Represent missing font/baseline evidence explicitly instead of treating a default font as an exact match.
3. Add measured field-level calibration only where the actual rendered comparison demonstrates it is needed. Do not seed it with per-application pixel offsets.
4. Compare against native reference glyphs in Helvetica 12/16, a serif, system text and monospace; include empty/new lines, filled lines, paragraph spacing, wraps, zoom and Unicode. Then compare actual TextEdit ghost/accepted screenshots before calling the floating issue fixed.

Exact appearance in every possible field is not established: some hosts expose insufficient style data or use unavailable fonts/custom rendering. The recommendation is the strongest source-supported route toward the user's requirement, not a promise that Core Text alone makes every host identical.
