# Cross-Review Notes: Protocol v0.4 x IME Interface Contract v0.3

> **Status**: Consensus reached
> **Date**: 2026-03-05
> **Review type**: Cross-document consistency review — protocol-side notes
> **Participants**: protocol-architect, ime-expert, cjk-specialist
> **Companion file**: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md`

---

## Summary

Ten inconsistencies were identified between Protocol v0.4 and IME Interface Contract v0.3. After team discussion with evidence from reference codebases (ghostty, ibus-hangul, fcitx5-hangul, cmux), consensus was reached on all items. An eleventh issue (macOS Cmd key modifier mapping) was raised post-review and confirmed as a non-issue — Cmd is already correctly mapped to Super (bit 3). This file documents the protocol-side changes required.

---

## Consensus Decisions

### Issue 1 (CRITICAL): hid_keycode u8 (IME) vs u16 (wire)

**Resolution**: IME keeps u8. Protocol doc 04 documents server validation.

**Consensus rationale**: The IME engine operates exclusively on HID Keyboard/Keypad page (0x07), codes 0x00-0xE7, which fits in u8. The wire u16 exists for future HID page extensibility (consumer keys, media keys), but those keys are not composable text input and never reach the IME. Using u8 is the "tightest type for the domain" principle. The server validates at the wire-to-IME boundary.

**Protocol doc 04 change**: Add to Section 2.1 (KeyEvent), after the modifier bitflags table:

> **IME routing validation**: The server MUST validate that `keycode <= 0xE7` (HID Keyboard/Keypad page) before routing a KeyEvent to the IME engine via `processKey()`. Keycodes above 0xE7 are either modifier keys (0xE0-0xE7, which are represented in the `modifiers` bitmask) or non-keyboard HID usages (consumer page, etc.) that bypass IME processing entirely. The server forwards such keys directly to the terminal without IME involvement.

**Evidence**: ghostty uses `Key = enum(c_int)` (`ghostty/src/input/key.zig:107`) — a high-level semantic enum, not raw HID codes. The wire protocol's u16 maps to this broader key space. The IME's u8 maps to the keyboard subset only. libhangul's `hangul_ic_process()` takes an ASCII character — even narrower than u8 HID codes.

---

### Issue 2 (MODERATE): Shift extraction from wire modifiers undocumented

**Resolution**: Protocol doc 04 adds wire-to-IME mapping note. IME contract adds cross-reference.

**Protocol doc 04 change**: Add to Section 2.1 (KeyEvent), a new subsection "Wire-to-IME KeyEvent Mapping":

> **Wire-to-IME KeyEvent mapping**: The server decomposes the wire `modifiers` bitmask into the IME contract's separated fields:
>
> | Wire modifier bits | IME KeyEvent field | Notes |
> |---|---|---|
> | Bit 0 (Shift) | `shift: bool` | Separated because Shift participates in jamo selection (e.g., ㄱ vs ㄲ), not composition flush |
> | Bits 1-3 (Ctrl, Alt, Super) | `modifiers: Modifiers` | These trigger composition flush in the IME engine |
> | Bits 4-5 (CapsLock, NumLock) | Dropped | Intentionally not consumed by IME — see IME contract Section 3.1 |
> | Bits 6-7 | Reserved | Must be 0 |
>
> See IME Interface Contract v0.3, Section 3.1 for the rationale behind separating Shift from other modifiers.

---

### Issue 3 (LOW): CapsLock/NumLock bits silently dropped

**Resolution**: IME contract documents the intentional omission. Protocol is correct to carry them.

**Protocol doc change**: None. The protocol correctly carries CapsLock/NumLock in the wire modifiers bitmask (bits 4-5). Other server subsystems may need them. The Issue 2 mapping note (above) documents that bits 4-5 are dropped at the IME boundary.

---

### Issue 4 (INFO): keycode (wire) vs hid_keycode (IME) naming

**Resolution**: No action. Both names are correct within their context.

The wire field `keycode` is concise and appropriate for JSON brevity. The IME field `hid_keycode` is more precise, explicitly denoting the USB HID origin. The naming difference is cosmetic and does not affect correctness. May be unified in a future cleanup pass.

---

### Issue 5 (MODERATE): composition_state in protocol but not in IME

**Resolution**: IME contract adds `composition_state: ?[]const u8 = null` to ImeResult.

**Protocol doc change**: None. The protocol's composition_state field in PreeditStart/PreeditUpdate (doc 05, Sections 2.1-2.2) is correct. The server will pass through the IME engine's composition_state string directly to the protocol JSON without interpretation.

**Design notes**: The field uses a nullable string (`?[]const u8`) rather than a typed enum to preserve the "single interface for all languages" principle (IME contract Design Principle #1). Korean engine returns Korean-specific values ("empty", "ko_leading_jamo", "ko_vowel_only", "ko_syllable_no_tail", "ko_syllable_with_tail", "ko_double_tail"). Future Japanese/Chinese engines return their own language-prefixed values (e.g., "ja_romaji_input", "ja_kana_converting"). The "empty" constant is language-agnostic (no prefix) since it represents the absence of composition. Engines that do not track composition state return null, and the server derives it. Named constants in each engine module provide compile-time safety without leaking language-specific values into the shared interface.

---

### Issue 6 (LOW): display_width derivation undocumented

**Resolution**: Protocol doc 05 documents the computation rules.

**Protocol doc 05 change**: Add to Section 2.2 (PreeditUpdate), after the field table:

> **display_width computation**: The server computes `display_width` from the preedit text using the Unicode East Asian Width property (UAX #11). For Korean Hangul preedit text produced by libhangul, the value is always 2:
>
> - Precomposed Hangul syllables (U+AC00-U+D7A3): East Asian Width = W = 2 cells
> - Compatibility Jamo (U+3131-U+318E): East Asian Width = W = 2 cells
>
> libhangul always outputs precomposed or compatibility forms for preedit text, so conjoining Jamo edge cases (U+1100-U+11FF, where width varies) do not arise in practice. For future CJK languages, the server applies UAX #11 to the preedit text codepoints.

---

### Issue 7 (INFO): committed_text + forward_key ordering verified correct

**Resolution**: No action. Both documents are consistent.

The server processes ImeResult fields in order: committed_text first (feed to ghostty as composed text), then forward_key (feed as raw key event). This ensures committed text reaches the PTY before the forwarded key's effect (e.g., "하" is written before Ctrl+C sends SIGINT).

---

### Issue 8 (MODERATE): InputMethodSwitch commit_current=false has no IME counterpart

**Resolution**: Keep the protocol's `commit_current` field as-is. The IME contract does NOT add a new parameter for v1. The server implements `commit_current=false` by calling `reset()` + `setActiveLanguage()` while holding the per-pane lock. Protocol adds SHOULD recommendation.

**Consensus rationale**: The `commit_current=false` case (cancel and switch) has no known use case for Korean v1. All real-world Korean IME frameworks (ibus-hangul, fcitx5-hangul, macOS system IME, Windows IME) always commit on language switch, never cancel. Adding a `commit: bool` parameter to setActiveLanguage() would expand the interface surface for a non-existent v1 use case (YAGNI). When Japanese/Chinese are added, the cancel-on-switch semantics may differ enough (cancelling candidate selection vs raw composition) that a simple boolean parameter would be insufficient — better to design the API when actual requirements are understood.

The server-side implementation via `reset()` + `setActiveLanguage()` is safe when the server holds the per-pane lock across both calls. After `reset()`, the engine is empty, so `setActiveLanguage()` performs a no-flush switch.

**Protocol doc 05 change**: Add to Section 4.1 (InputMethodSwitch), after the server behavior list:

> **SHOULD recommendation**: Clients SHOULD default to `commit_current=true` for InputMethodSwitch. The `commit_current=false` option is non-standard — no widely-used Korean IME framework discards composition on language switch. This option exists for future CJK language support where cancel-on-switch may be appropriate.
>
> **Server implementation**:
> - `commit_current=true`: Server calls `setActiveLanguage(new_lang)`. The IME flushes (commits) pending composition and switches. This is the standard behavior.
> - `commit_current=false`: Server calls `reset()` to discard the current composition, then `setActiveLanguage(new_lang)` to switch. The server MUST hold the per-pane lock across both calls to ensure atomicity. The PreeditEnd reason is `"cancelled"`.

---

### Issue 9 (LOW): Escape preedit reason contradiction

**Resolution**: Protocol doc 05 changes Escape PreeditEnd reason from "cancelled" to "committed".

**Protocol doc 05 change**: In Section 2.3 (PreeditEnd), update the reason values:

> **Reason values**:
> - `"committed"`: Normal completion (Space, Enter, non-Jamo key, **Escape**, modifier flush)
> - `"cancelled"`: Composition discarded without committing (backspace-to-empty, explicit reset, `commit_current=false` on InputMethodSwitch)
> - _(remaining reasons unchanged)_

Remove any example that lists "User pressed Escape" under the "cancelled" reason. Escape causes the IME to flush (commit) the preedit text, then forwards the Escape key to the terminal. This matches ibus-hangul and fcitx5-hangul behavior, and was a deliberate correction in IME contract v0.3 (from v0.2's incorrect "reset on Escape" policy).

**Evidence**: cmux's CJKIMEInputTests.swift (line 403) describes Escape as "composition cancel" — but this follows the macOS NSTextInputClient convention. libitshell3 uses native IME (not OS IME), so the macOS convention does not apply.

---

### Issue 10 (INFO): Language identifier representation mismatch

**Resolution**: Both documents add cross-reference notes.

**Protocol doc 05 change**: Add to Section 4.1 (InputMethodSwitch) or Section 4.3 (Per-Pane Input Method State):

> **Language identifier mapping**: The protocol uses self-documenting string identifiers for input methods (e.g., `"direct"`, `"korean_2set"`, `"korean_3set_390"`). These encode both language and keyboard layout. The server maps protocol strings to IME contract types:
>
> | Protocol string | IME LanguageId | IME layout_id |
> |---|---|---|
> | `"direct"` | `LanguageId.direct` | N/A |
> | `"korean_2set"` | `LanguageId.korean` | `"2"` |
> | `"korean_3set_390"` | `LanguageId.korean` | `"3f"` |
>
> See IME Interface Contract v0.3, Section 3.4 (LanguageId) and Section 3.7 (HangulImeEngine.layout_id).

---

### RestoreSession IME Gap

**Resolution**: Protocol doc 03 documents IME initialization during session restore.

**Protocol doc 03 change**: Add to the RestoreSessionResponse section:

> **IME engine initialization**: When restoring a session, the server MUST re-initialize the IME engine for each restored pane:
>
> 1. Create a new `ImeEngine` instance with the saved `layout_id` from the session snapshot
> 2. Call `setActiveLanguage(saved_language_id)` to restore the pane's language mode
> 3. Composition state is NOT restored — any mid-composition state was flushed on the previous detach/shutdown. The engine starts in the `empty` composition state.
>
> The session snapshot must persist per-pane: `active_language` (LanguageId enum) and `layout_id` (string). See IME Interface Contract v0.3, Section 3.4 and Section 3.7.

---

### Issue 11 (INFO): macOS Cmd key mapping in modifier bitmask — No action

**Resolution**: No action. Cmd is already correctly mapped to Super (bit 3).

**macOS modifier key mapping:**

| macOS Key | Wire Protocol Bit | Modifier Name | IME Field |
|-----------|-------------------|---------------|-----------|
| Option    | Bit 2             | Alt           | modifiers.alt |
| Command   | Bit 3             | Super         | modifiers.super_key |

**Consensus rationale**: The wire protocol modifier bitmask (Section 2.1) already maps bit 3 to `Super (Cmd on macOS)`. The parenthetical annotation explicitly documents the platform mapping. This is consistent across all layers:

| Layer | Cmd representation | Evidence |
|---|---|---|
| Wire protocol (doc 04) | Bit 3 = Super (Cmd on macOS) | Section 2.1, Modifier Bitflags table |
| IME contract (v0.3) | `Modifiers.super_key: bool` | Section 3.1, KeyEvent.Modifiers packed struct |
| ghostty | `.super` modifier, aliased as `"cmd"` / `"command"` | `key_mods.zig:9-10` |
| macOS AppKit | `NSEvent.ModifierFlags.command` -> `GHOSTTY_MODS_SUPER` | `Ghostty.Input.swift:67` |
| macOS App Intents | `.command` -> `.super` | `InputIntent.swift:324` |
| HID | 0xE3 (left GUI / Mac Command) -> `"MetaLeft"` | `keycodes.zig:514` |

**IME composition behavior**: `hasCompositionBreakingModifier()` includes `self.modifiers.super_key`, so Cmd+key combinations correctly trigger composition flush. This matches ibus-hangul (`IBUS_SUPER_MASK` flushes) and fcitx5-hangul (`FcitxKeyState_Super` flushes).

**Wire-to-IME mapping** (documented in Issue 2): Wire bit 3 (Super) maps to `KeyEvent.modifiers.super_key`. No additional mapping step needed for Cmd.

**Protocol doc 04 change**: None. Already correct.

**IME contract change**: None. Already correct.

---

## Changes Summary

| Document | Section | Change |
|----------|---------|--------|
| Protocol doc 04 | Section 2.1 | Add IME routing validation note (keycode <= 0xE7) |
| Protocol doc 04 | Section 2.1 | Add wire-to-IME KeyEvent mapping table |
| Protocol doc 05 | Section 2.2 | Add display_width computation rules (UAX #11) |
| Protocol doc 05 | Section 2.3 | Fix Escape PreeditEnd reason: "cancelled" -> "committed" |
| Protocol doc 05 | Section 4.1 | Add SHOULD recommendation for commit_current=true |
| Protocol doc 05 | Section 4.1 | Add server implementation note for commit_current=false |
| Protocol doc 05 | Section 4.1/4.3 | Add language identifier mapping cross-reference |
| Protocol doc 03 | RestoreSession | Add IME engine initialization sequence |
| _(none)_ | _(none)_ | Issue 11: No action — Cmd already mapped to Super (bit 3) |
