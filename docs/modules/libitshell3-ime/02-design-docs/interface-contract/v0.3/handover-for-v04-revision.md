# Handover: IME Contract v0.3 Cross-Review → v0.4 Revision

**From**: Cross-review session (2026-03-05)
**To**: Next session (v0.4 revision)

---

## What was done

A cross-document consistency review between **Protocol v0.4** (6 docs) and **IME Interface Contract v0.3** was completed. Three reviewers (protocol-architect, ime-expert, cjk-specialist) reached consensus on 11 issues + 1 gap.

### Review artifacts (all committed)

| File | Location | Commit |
|------|----------|--------|
| Initial review report | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-report.md` | `cf0a0fe` |
| IME-side cross-review notes | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md` | `7ed134c` |
| Protocol-side cross-review notes | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md` | `7ed134c` |
| User's own protocol review notes | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-01-protocol-overview.md` | `99ff5b9` |

---

## What needs to be done: Apply review decisions to design documents

The cross-review produced **review notes only** — no design documents were modified. The next session must apply the agreed decisions to the actual design documents.

### IME Contract changes (apply to `01-interface-contract.md`)

| Section | Change | Source Issue |
|---------|--------|-------------|
| 3.1 (KeyEvent) | Add `pub const HID_KEYCODE_MAX: u8 = 0xE7;` constant | Issue 1 |
| 3.1 (KeyEvent) | Add server validation note: keycodes > HID_KEYCODE_MAX bypass IME | Issue 1 |
| 3.1 (KeyEvent) | Add cross-reference to protocol doc 04 Section 2.1 for wire-to-KeyEvent mapping | Issue 2 |
| 3.1 (KeyEvent) | Add note: CapsLock/NumLock (bits 4-5) intentionally not consumed | Issue 3 |
| 3.2 (ImeResult) | Add `composition_state: ?[]const u8 = null` field with doc comment | Issue 5 |
| 3.2 (ImeResult) | Update scenario matrix to include composition_state column | Issue 5 |
| 3.4 (LanguageId) | Add cross-reference to protocol string identifiers | Issue 10 |
| 3.6 (setActiveLanguage) | Add note: `reset()` + `setActiveLanguage()` safe for discard-and-switch under per-pane lock | Issue 8 |
| 3.7 (HangulImeEngine) | Add `CompositionStates` string constants with `ko_` prefix | Issue 5 |
| 3.7 (HangulImeEngine) | Add session persistence fields note (`active_language`, `layout_id`) | RestoreSession |

### Protocol changes (apply to v0.4 docs)

| Document | Section | Change | Source Issue |
|----------|---------|--------|-------------|
| Doc 04 | Section 2.1 | Add IME routing validation note (keycode <= 0xE7) | Issue 1 |
| Doc 04 | Section 2.1 | Add wire-to-IME KeyEvent mapping table (Shift separated, CapsLock/NumLock dropped) | Issue 2 |
| Doc 05 | Section 2.2 | Document display_width computation (UAX #11, Korean preedit always 2 cells) | Issue 6 |
| Doc 05 | Section 2.3 | Fix Escape PreeditEnd reason: `"cancelled"` → `"committed"` | Issue 9 |
| Doc 05 | Section 4.1 | Add SHOULD recommendation for `commit_current=true` | Issue 8 |
| Doc 05 | Section 4.1 | Add server implementation note for `commit_current=false` (reset+setActiveLanguage with lock) | Issue 8 |
| Doc 05 | Section 4.1/4.3 | Add language identifier mapping cross-reference table | Issue 10 |
| Doc 03 | RestoreSession | Add IME engine initialization sequence (create engine, set language, no preedit restore) | RestoreSession |

### No-action items (already correct, no changes needed)

| Issue | Reason |
|-------|--------|
| Issue 4 | `keycode` vs `hid_keycode` naming — cosmetic difference, both correct |
| Issue 7 | `committed_text` + `forward_key` ordering — verified correct |
| Issue 11 | macOS Cmd key — already mapped to Super (bit 3), Option to Alt (bit 2) |

---

## User's own review notes (NOT from cross-review)

The user has their own review notes for protocol doc 01 at:
`docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-01-protocol-overview.md`

This file contains 2 issues the user raised independently:

1. **Multi-tab requires multi-connection model** (High severity) — Protocol's single-session-per-connection rule is correct, but the spec never documents how a client with multiple tabs maintains simultaneous sessions. One connection per session (tab) is the canonical pattern. SSH tunnel multiplexing for remote clients also undocumented.

2. **Remove `ERR_DECOMPRESSION_FAILED`** (Minor) — Dead error code for a feature that doesn't exist (compression removed in v0.3). Should use `ERR_PROTOCOL_ERROR` instead.

These are separate from the cross-review and should be addressed in the protocol v0.4 revision.

---

## Key decisions to remember

1. **`composition_state` is `?[]const u8` (string), NOT enum** — Design Principle #1 ("single interface for all languages"). Korean constants use `ko_` prefix for collision avoidance.

2. **No `commit: bool` on `setActiveLanguage()`** — YAGNI for v1. Server orchestrates cancel externally via `reset()` + `setActiveLanguage()` under per-pane lock.

3. **Escape causes flush (commit), NOT cancel** — Deliberate correction from v0.2. Both ibus-hangul and fcitx5-hangul commit on Escape.

4. **macOS modifier mapping**: Option = Alt (bit 2), Command = Super (bit 3). Confirmed via ghostty source.

---

## Team composition for revision

See `MEMORY.md` for full team composition. For v0.4 revision, the same 3 core roles are needed:

- **Protocol Architect**: Applies changes to protocol docs 03, 04, 05
- **IME Expert**: Applies changes to IME contract `01-interface-contract.md`
- **CJK Specialist**: Verifies cross-document consistency after revision

### Workflow lesson from this session

- **Review phase and revision phase MUST be strictly separated.** This session had multiple false starts because agents were instructed to modify design documents during the review phase.
- **Do NOT pre-assign issues to reviewers.** Let all reviewers see all issues and discuss freely.
- **Do NOT intervene in team discussions.** Let teammates DM each other directly and reach consensus autonomously.
- **Always verify both review notes files for consistency** before committing — agents may write contradictory decisions across files.
