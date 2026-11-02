# Prototype verification

## Observed on this machine

- macOS 15.7.2, Apple Silicon, Swift 6.2.1, Command Line Tools selected (no full Xcode).
- `swift run DittoTests`: 12 tests passed, including prefix ranking, recency, UTF-16 ranges, invalid/stale session rejection, exact Unicode normalization guards, SQLite reopen, duplicate promotion, pins, expiration, deletion, capture bounds, keyboard policy, and confidential-marker filtering.
- Debug build succeeded.
- Release build and local app bundling succeeded; ad-hoc code signature verification succeeded.
- Initial native process smoke check launched the menu bar and visible setup window, with capture off and Accessibility unavailable.

## Required before claiming cross-app compatibility

Grant Ditto's permissions using its Setup screen, copy non-sensitive sample text, and test each target app. Start with the built-in Practice editor, then Ghostty, Chrome/Safari text fields, the user's editor and chat apps.

For each app record:

- Does the field expose readable text, cursor range and writable selected text? If not, does history clearly offer Copy?
- Invoke with an empty query; type a prefix; cycle; accept. Only the session query is replaced.
- Paste a substring match and multiline item. No appended Return or automatic submission.
- Use emoji/diacritics and non-US layouts. Input-method composition must cancel rather than corrupt text. Option-modified/dead-key input currently ends compact mode.
- Type then press Tab immediately; do not paste an earlier candidate before the most recent input.
- Backspace inside the query; move/click outside it; change apps; start a selection. No stale insertion.
- Escape keeps typed text. History filtering does not enter the destination; Escape restores compact mode; acceptance restores and revalidates the original field.
- Copy new content during a session, even while capture is paused; the old session closes.
- Press Enter in compact mode. It performs the destination action and does not accept a suggestion.
- Undo after acceptance. Check whether the destination groups the replacement into one undo operation; currently unverified.
- Check secure fields, exclusions, locked session, revoked permissions, event-tap disable, and hotkey conflict behavior.
- Verify multi-display placement and focus restoration, including full-screen apps.

## Limits

No verified cross-app insertion results yet. The native smoke check reports Accessibility unavailable. Do not infer Ghostty, browser, editor, or chat support from the automated core checks. The current conservative adapter deliberately falls back to Copy when selected-text replacement is unavailable.

## Native UI inspection

Opened the packaged app with capture off. Inspected Setup, opened the Practice editor, opened empty History from Setup, and dismissed History with Escape. Those views and dismissal behaved as expected. An app-targeted automated ⌥⌘V keypress did not demonstrate global shortcut activation; do not count it as a shortcut pass. No Accessibility/Input Monitoring permission was granted during this inspection, and clipboard capture was not enabled.
