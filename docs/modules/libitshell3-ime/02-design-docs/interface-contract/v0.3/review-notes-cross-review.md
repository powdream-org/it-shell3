# Cross-Review Notes: IME Interface Contract v0.3

> **Status**: Consensus reached
> **Date**: 2026-03-05
> **Review type**: Cross-document consistency review (IME contract v0.3 x Protocol v0.4)
> **Participants**: protocol-architect, ime-expert, cjk-specialist
> **Companion file**: `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md`

---

## Summary

Ten inconsistencies between the IME Interface Contract v0.3 and Protocol v0.4 were identified in the review report. All ten have been discussed and resolved through three-way consensus. Additionally, one gap (RestoreSession IME initialization) was identified by the session-flow-reviewer and resolved. A subsequent review (Issue 11) confirmed that the macOS Cmd key modifier mapping is already correctly handled — no action needed.

Of the ten issues, two required substantive IME contract changes (Issues 1, 5), five require documentation additions to the IME contract (Issues 2, 3, 8, 10, RestoreSession), and the remainder are protocol-side fixes or no-action items. Issue 11 confirmed existing correctness.

---

## Consensus Decisions

### Issue 1 (CRITICAL): `hid_keycode` type — Keep u8, add boundary constant

**Decision**: Keep `hid_keycode: u8` in KeyEvent. Add `pub const HID_KEYCODE_MAX: u8 = 0xE7;` constant. Document server validation requirement.

**Rationale**: The IME engine processes only USB HID page 0x07 (Keyboard/Keypad) keycodes, which range 0x00-0xE7 — bounded within u8. Type narrowing at the boundary is correct practice when the domain is bounded and documented. The wire protocol's u16 accommodates future HID pages (Consumer, Telephony), but those are never text input and bypass the IME entirely.

Evidence:
- libhangul's `hangul_ic_process()` accepts an `int` for ASCII character, even narrower than u8
- IME's `isPrintablePosition()` checks 0x04-0x38, well within u8
- All special keys the IME handles (Backspace 0x2A, Enter 0x28, Escape 0x29, arrows 0x4F-0x52, Space 0x2C) are within u8
- ghostty's `keycodes.zig:37` uses `usb: u32` for full HID usage codes, but the wire protocol already narrows to u16 — narrowing further to u8 at the IME boundary is the same pattern

**Changes required in IME contract**:
- Add `pub const HID_KEYCODE_MAX: u8 = 0xE7;` to Section 3.1
- Add note: "The server MUST NOT pass keycodes above HID_KEYCODE_MAX to processKey(). Keycodes above this value bypass the IME engine entirely and are routed directly to ghostty."

**Changes required in protocol doc 04**:
- Add server validation note in Section 2.1: keycodes > 0xFF bypass IME; keycodes 0xE8-0xFF are undefined on HID page 0x07 and also bypass IME

---

### Issue 2 (MODERATE): Shift extraction from wire modifiers — Document mapping

**Decision**: Add wire-to-IME KeyEvent field mapping documentation. Primary note in protocol doc 04 Section 2.1, cross-reference from IME contract Section 3.1.

**Rationale**: The IME contract correctly separates `shift: bool` from `Modifiers{ctrl, alt, super_key}` because Shift participates in Korean jamo selection (not flush). This mirrors ibus-hangul's pattern where `IBUS_SHIFT_MASK` is handled differently from `IBUS_CONTROL_MASK | IBUS_MOD1_MASK`. The server's responsibility to decompose the wire u8 bitmask must be documented.

**Changes required in IME contract**:
- Add cross-reference in Section 3.1: "See protocol doc 04 Section 2.1 for the wire-to-KeyEvent field mapping."

**Mapping (documented in protocol doc 04)**:
```
wire modifiers bit 0 (Shift)    -> KeyEvent.shift
wire modifiers bits 1-3         -> KeyEvent.modifiers{ctrl, alt, super_key}
wire modifiers bits 4-5         -> dropped (see Issue 3)
wire modifiers bits 6-7         -> reserved
```

---

### Issue 3 (LOW): CapsLock/NumLock intentionally omitted — Document

**Decision**: Add documentation note in IME contract Section 3.1 explaining the intentional omission.

**Rationale**: CapsLock and NumLock do not affect Korean Hangul composition. The HID keycode represents physical key position; Shift alone determines jamo variants (e.g., 'r' -> ㄱ vs 'R' -> ㄲ). CapsLock as a language toggle is a Phase 0 concern (libitshell3 global shortcut), not an IME concern. This matches ibus-hangul and fcitx5-hangul, neither of which consumes CapsLock/NumLock state.

**Changes required in IME contract**:
- Add note in Section 3.1: "CapsLock and NumLock (wire modifier bits 4-5) are intentionally not consumed by the IME engine. Lock key state does not affect Hangul composition — jamo selection depends solely on the Shift key. CapsLock as a language toggle key is detected in Phase 0 (libitshell3), not by the IME."

---

### Issue 4 (INFO): `keycode` vs `hid_keycode` naming — No action

**Decision**: No change. Both names are correct within their context.

**Rationale**: The wire protocol uses `keycode` for JSON brevity. The IME contract uses `hid_keycode` to explicitly denote the USB HID origin, which is important context for Korean input (physical key position matters, not character value). The naming difference is cosmetic and does not cause confusion when cross-referencing, because both docs clearly state the HID semantics.

---

### Issue 5 (MODERATE): `composition_state` — Add to ImeResult as optional string

**Decision**: Add `composition_state: ?[]const u8 = null` to ImeResult. Define Korean-specific string constants in HangulImeEngine. Server passes through to PreeditUpdate JSON without interpretation.

**Rationale**: The IME engine internally knows the Hangul composition stage (from libhangul's buffer state). Forcing the server to reverse-engineer this from NFC decomposition of the preedit string is redundant and error-prone.

An ImeResult field was chosen over a query method (getCompositionState) because:
1. Temporal atomicity: the composition state is captured at the moment processKey() produces its result, not queried after the fact where another event could intervene
2. After flush()/deactivate(), a query would return null (post-operation state), but PreeditEnd needs the state that WAS active — only ImeResult captures this
3. Precedent: `preedit_changed: bool` is already protocol metadata in ImeResult
4. No additional vtable method needed (keeps the 8-method interface)

The field is `?[]const u8` (nullable string) rather than a typed enum because:
1. Design Principle #1 ("Single interface for all languages") prohibits Korean-specific types in the generic interface
2. The protocol wire format uses strings for composition_state — matching types eliminates conversion
3. Future Japanese/Chinese engines have completely different composition states that cannot share a Korean enum
4. In Zig, static string literal pointers have zero allocation cost — same performance as an enum assignment

**Changes required in IME contract**:
- Add to ImeResult (Section 3.2):
  ```zig
  /// Composition state for protocol metadata (PreeditUpdate messages).
  /// Engine-specific string describing the current composition stage.
  /// null when no composition is active or when the engine does not
  /// track sub-states (e.g., direct mode).
  /// Memory: points to static string literals, valid indefinitely.
  composition_state: ?[]const u8 = null,
  ```
- Add to HangulImeEngine (Section 3.7):
  ```zig
  pub const CompositionStates = struct {
      pub const empty = "empty";
      pub const leading_jamo = "ko_leading_jamo";
      pub const vowel_only = "ko_vowel_only";
      pub const syllable_no_tail = "ko_syllable_no_tail";
      pub const syllable_with_tail = "ko_syllable_with_tail";
      pub const double_tail = "ko_double_tail";
  };
  ```
  > **Naming convention**: Language-specific composition state constants MUST use a
  > language prefix (`ko_`, `ja_`, `zh_`) to avoid collision across engines. For
  > example, a future Japanese engine might define `ja_romaji_input`,
  > `ja_kana_converting`, etc. The `empty` constant is the only language-agnostic
  > value (no composition active) and carries no prefix.
- Update scenario matrix in Section 3.2 to include composition_state column

---

### Issue 6 (LOW): `display_width` derivation — Server responsibility

**Decision**: Server computes display_width. Protocol doc 05 documents the derivation rules with UAX #11 reference. IME contract does not change.

**Rationale**: Terminal column width is a rendering concern, not a composition concern. The IME engine deals with Hangul composition; Unicode East Asian Width properties belong in the server/protocol layer. ghostty already has width computation (`renderer/State.zig`). For Korean preedit text specifically: Hangul syllables (U+AC00-U+D7A3) are always 2 cells, compatibility jamo (U+3131-U+318E) are always 2 cells. libhangul never outputs conjoining jamo (U+1100-U+11FF) as preedit.

**Changes required in protocol doc 05**:
- Document display_width computation in Section 2.2 with UAX #11 reference
- Note: Korean preedit is always 2 cells wide

---

### Issue 7 (INFO): committed_text + forward_key ordering — Verified correct

**Decision**: No change. Ordering is correct in both documents.

**Rationale**: The server must process committed_text first (feed to ghostty as composed text) then process forward_key (feed as raw key event). This ordering is explicit in the IME contract's handleKeyEvent() pseudocode (Section 5) and was verified correct by all five end-to-end scenario traces.

---

### Issue 8 (MODERATE): InputMethodSwitch `commit_current=false` — No IME change, document server implementation

**Decision**: Keep the protocol's `commit_current` field as-is. The IME contract does NOT add a new parameter. The server implements `commit_current=false` by calling `reset()` + `setActiveLanguage()` while holding the per-pane lock. Document this pattern in both docs.

**Rationale**: The `commit_current=false` case (cancel and switch) has no known use case for Korean v1. All real-world Korean IME frameworks (ibus-hangul, fcitx5-hangul) ALWAYS commit on language switch, never cancel. macOS and Windows system IMEs also commit on switch. Adding a `commit: bool` parameter to setActiveLanguage() would expand the interface surface for a non-existent v1 use case, violating YAGNI.

The server-side implementation via `reset()` + `setActiveLanguage()` is safe when the server holds the per-pane lock across both calls. The atomicity concern from Section 3.6 applies to unsynchronized callers — but the server already requires per-pane locking for concurrent KeyEvent + FocusPaneRequest handling, so the locking infrastructure exists. After `reset()`, the engine is empty, so `setActiveLanguage()` performs a no-flush switch.

When Japanese/Chinese are added in the future, the cancel-on-switch semantics may differ enough (cancelling candidate selection vs raw composition) that a simple boolean parameter would be insufficient. Better to design the API when the actual requirements are understood.

**Changes required in IME contract**:
- Add note in Section 3.6: "`reset()` followed by `setActiveLanguage()` is safe for discard-and-switch when the caller holds the per-pane lock. After `reset()`, the engine is empty and `setActiveLanguage()` performs a no-flush language switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch."

**Changes required in protocol doc 05**:
- Document server implementation for `commit_current=false`: "When `commit_current=false`, the server calls `ime.reset()` to discard the current composition, then `ime.setActiveLanguage(new_lang)` to switch. The server MUST hold the per-pane lock across both calls to ensure atomicity."
- Add normative note: "Clients SHOULD default to `commit_current=true` unless the user explicitly requests discard. The `commit_current=false` option is non-standard for Korean input and exists for future CJK languages."

---

### Issue 9 (LOW): Escape preedit reason — Protocol should fix

**Decision**: Protocol doc 05 Section 2.3 should change the Escape example from reason `"cancelled"` to reason `"committed"`.

**Rationale**: The IME contract specifies that Escape causes a flush (commit) — this was a deliberate correction from v0.2 (Section 3.3 note: "interface-design.md previously specified RESET for Ctrl/Alt/Super modifiers. That was incorrect"). Both ibus-hangul and fcitx5-hangul commit on Escape. The protocol doc incorrectly lists Escape as "cancelled."

The `"cancelled"` reason should be reserved for: backspace-to-empty (composition fully undone), explicit reset(), `commit_current=false` on InputMethodSwitch, pane close (PTY gone).

**IME contract**: No change needed. Already correct.

**Changes required in protocol doc 05**:
- Section 2.3: Change Escape example from `reason="cancelled"` to `reason="committed"`
- Clarify `"cancelled"` definition: "Composition discarded without committing. Examples: backspace-to-empty, explicit cancel, commit_current=false language switch."

---

### Issue 10 (INFO): Language identifier representation — Add cross-references

**Decision**: Add cross-reference notes in both documents documenting the server-side mapping between protocol string identifiers and IME LanguageId + layout_id.

**Rationale**: The IME uses `LanguageId` enum (direct=0, korean=1) because it only needs the composition mode. The protocol uses richer strings ("korean_2set", "korean_3set_390") encoding language + keyboard layout. The server maps between them: `"korean_2set"` -> `LanguageId.korean` + `layout_id="2"`. This is the correct separation of concerns — it just needs documentation.

**Changes required in IME contract**:
- Add note in Section 3.4 (LanguageId): "Protocol string identifiers encode both language and keyboard layout (e.g., `\"korean_2set\"`). The server maps these to `LanguageId` (language) + `layout_id` (keyboard variant). See protocol doc 04, Section 2.1 for the identifier table."

---

### RestoreSession IME Gap — Document initialization

**Decision**: Protocol doc 03 documents IME initialization in RestoreSessionResponse. IME contract adds a persistence note.

**Rationale**: When a session is restored, the server must re-initialize per-pane IME engines with the saved language and layout. The IME contract already defines the relevant save fields (`active_language` from Section 3.4, `layout_id` from Section 3.7). Composition state is NOT restored (it was flushed on deactivate/detach).

**Changes required in IME contract**:
- Add persistence note (new subsection or in Section 3.7): "Session persistence fields: `active_language` (LanguageId) and `layout_id` (string). On session restore, the server creates a new HangulImeEngine with the saved layout_id and calls `setActiveLanguage(saved_language_id)`. Composition state is never persisted — it is flushed on pane deactivation."

**Changes required in protocol doc 03**:
- Add IME initialization step in RestoreSessionResponse: "For each restored pane, the server initializes an ImeEngine with the pane's saved keyboard layout and active language. No preedit is restored (composition was flushed on session detach)."

---

### Issue 11 (INFO): macOS Cmd key modifier mapping — No action, already handled

**Decision**: No change. Cmd is already correctly mapped to Super (wire bit 3, IME `super_key`).

**macOS modifier key mapping:**

| macOS Key | Wire Protocol Bit | Modifier Name | IME Field |
|-----------|-------------------|---------------|-----------|
| Option    | Bit 2             | Alt           | modifiers.alt |
| Command   | Bit 3             | Super         | modifiers.super_key |

**Rationale**: The concern was whether the macOS Cmd (Command) key is missing from the wire protocol modifier bitmask. Investigation confirms it is already fully handled through the Super modifier, which is the standard cross-platform name for Cmd.

Evidence chain:
1. **Wire protocol** (doc 04, line 102): Bit 3 = "Super (Cmd on macOS)" — explicitly documented
2. **IME contract** (Section 3.1): `Modifiers.super_key: bool` — composition-breaking modifier
3. **`hasCompositionBreakingModifier()`** (Section 3.1): Includes `self.modifiers.super_key` — Cmd triggers flush
4. **IME contract prose** (lines 54, 137, 171, 265, 553): Consistently references "Ctrl/Alt/Cmd" as flush triggers
5. **ghostty source** (`key_mods.zig:9-10`): `"cmd"` and `"command"` are aliases for `.super`
6. **ghostty macOS layer** (`Ghostty.Input.swift:56-67`): `NSEvent.ModifierFlags.command` <-> `GHOSTTY_MODS_SUPER` bidirectional mapping
7. **Wire-to-IME mapping** (cross-review Issue 2): Wire bit 3 (Super) -> `KeyEvent.modifiers.super_key`

Framework precedents:
- **ibus-hangul**: `IBUS_SUPER_MASK` triggers composition flush (same category as Ctrl/Alt)
- **fcitx5-hangul**: `FcitxKeyState_Super` triggers composition flush

iOS/iPadOS is also covered: `UIKeyModifierCommand` maps to HID usage 0xE3/0xE7 (Left/Right GUI), which follows the same chain through wire bit 3 to IME `super_key`.

The naming convention "Super" for this key is standard across terminal emulators (Super = Cmd on macOS/iOS, Windows key on Linux/Windows). ghostty uses this convention with platform-specific aliases.

**Optional documentation improvement** (not required): The modifier bitflags table in doc 04 could be enhanced with cross-platform annotations: `3   Super (Cmd on macOS/iOS, Windows key on Windows/Linux)`. This is purely cosmetic — the current "(Cmd on macOS)" annotation is already sufficient.

**IME contract**: No change needed.
**Protocol docs**: No change needed (optional cosmetic improvement above).

---

## Change Summary by Document

### IME Contract v0.3 Changes

| Section | Change | Issue |
|---------|--------|-------|
| 3.1 (KeyEvent) | Add `HID_KEYCODE_MAX: u8 = 0xE7` constant + server validation note | Issue 1 |
| 3.1 (KeyEvent) | Add wire mapping cross-reference | Issue 2 |
| 3.1 (KeyEvent) | Add CapsLock/NumLock intentional omission note | Issue 3 |
| 3.2 (ImeResult) | Add `composition_state: ?[]const u8 = null` field | Issue 5 |
| 3.4 (LanguageId) | Add protocol string mapping cross-reference | Issue 10 |
| 3.6 (setActiveLanguage) | Add note: reset()+setActiveLanguage() is safe for discard-and-switch with per-pane lock | Issue 8 |
| 3.7 (HangulImeEngine) | Add `CompositionStates` string constants | Issue 5 |
| 3.7 (HangulImeEngine) | Add session persistence fields note | RestoreSession |

### Protocol Changes (for companion review notes)

| Document | Change | Issue |
|----------|--------|-------|
| Doc 04 Section 2.1 | Add wire-to-IME mapping + server validation for keycodes > 0xFF | Issues 1, 2 |
| Doc 05 Section 2.2 | Document display_width UAX #11 derivation | Issue 6 |
| Doc 05 Section 2.3 | Fix Escape PreeditEnd reason from "cancelled" to "committed" | Issue 9 |
| Doc 05 | Document server implementation of commit_current=false (reset+setActiveLanguage with lock) + SHOULD recommendation for commit_current=true | Issue 8 |
| Doc 03 | Add IME initialization in RestoreSessionResponse | RestoreSession |
