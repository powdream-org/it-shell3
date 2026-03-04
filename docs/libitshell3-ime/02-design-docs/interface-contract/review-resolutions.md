# Interface Contract v0.1 Review Resolutions

> **Date**: 2026-03-04
> **Reviewers**: principal-architect, ime-expert, ghostty-expert
> **Input document**: [v0.1/01-interface-contract.md](v0.1/01-interface-contract.md)
> **Output document**: [v0.2/01-interface-contract.md](v0.2/01-interface-contract.md)

---

## Resolution 1: Vtable Simplification — Remove Language Enumeration Methods

**Issue**: The v0.1 vtable contains 10 methods, including three language management methods (`getSupportedLanguages`, `setEnabledLanguages`, `setActiveLanguage`) and a `LanguageDescriptor` struct. For a statically linked engine with two known languages (direct + korean), the enumeration and enable/disable methods are unnecessary complexity.

**Resolution**: Remove `getSupportedLanguages()`, `setEnabledLanguages()`, and `LanguageDescriptor` from the vtable. Keep only `getActiveLanguage()` and `setActiveLanguage()`.

- libitshell3 creates the engine and knows its capabilities. No discovery needed.
- Language rotation list (for toggle key) is libitshell3's concern, not the engine's.
- Matches fcitx5/ibus pattern: the framework manages language lists, engines just process keys.

**Final vtable (8 methods)**:
- `processKey` — core key processing
- `flush` — commit pending composition
- `reset` — discard pending composition
- `isEmpty` — query composition state
- `activate` — pane gained focus
- `deactivate` — pane lost focus
- `getActiveLanguage` — query current language
- `setActiveLanguage` — switch language (flushes internally)

**Affected sections in 01-interface-contract.md**:
- Section 3.3 — Remove `LanguageDescriptor` struct
- Section 3.4 — Remove `getSupportedLanguages`, `setEnabledLanguages` from VTable; remove corresponding convenience wrappers
- Section 3.5 — Remove `enabled_languages` and `enabled_count` fields from `HangulImeEngine`; remove `getSupportedLanguagesImpl`, `setEnabledLanguagesImpl`; remove `supported_languages` constant
- Section 4 (Responsibility Matrix) — Remove "Reporting supported languages" row; update "Language list configuration" to note libitshell3 manages this internally

---

## Resolution 2: libhangul Cleanup on Language Switch

**Issue**: What cleanup does `setActiveLanguage()` need to perform when switching away from Korean? Is `hangul_ic_flush()` + field assignment sufficient, or does libhangul require additional cleanup?

**Resolution**: `hangul_ic_flush()` + `active_language = new_lang` is sufficient. No `hangul_ic_reset()` needed.

**Evidence**: Verified in libhangul source (`hangulinputcontext.c`):
- `hangul_ic_flush()` (line 1205) clears `preedit_string`, `commit_string`, `flushed_string`, saves buffer to `flushed_string`, calls `hangul_buffer_clear()`.
- `hangul_buffer_clear()` (line 292) zeroes `choseong`, `jungseong`, `jongseong`, resets index and stack.
- After flush, `hangul_ic_is_empty()` returns true. Context is ready for new input.
- Both ibus-hangul and fcitx5-hangul use `flush()` on mode switch. `reset()` is reserved for error recovery / session teardown.

**Affected sections in 01-interface-contract.md**:
- Section 3.5 — Add implementation note to `setActiveLanguageImpl` documenting the flush + assign pattern

---

## Resolution 3: Same-Language setActiveLanguage Is a No-Op

**Issue**: What should `setActiveLanguage(.korean)` do when the active language is already `.korean`? Should it flush composition?

**Resolution**: No-op. Return empty `ImeResult{}`. No flush, no state change.

**Rationale**:
- A same-language call is an idempotent state assertion, not user intent to finalize composition.
- Flushing would be a surprising side effect — user double-toggles and loses in-progress syllable.
- Matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`) behavior: same-engine set is a no-op.
- Caller can explicitly call `flush()` if commit-before-reassignment is needed.

**Affected sections in 01-interface-contract.md**:
- Section 3.4 — Add doc comment to `setActiveLanguage` specifying no-op on same language
- Section 3.5 — Add guard `if (lang == self.active_language) return ImeResult{};`

---

## Resolution 4: Modifier Flush Policy — FLUSH, Not RESET

**Issue**: Two conflicting positions existed in the documentation:
- `interface-design.md` Section 1.4: RESET (discard preedit) for Ctrl/Alt/Super/Escape
- `v0.1/01-interface-contract.md` scenario matrix + PoC: FLUSH (commit preedit) for all modifiers

**Resolution**: FLUSH (commit) for all non-printable/modifier keys. Uniform policy, no per-modifier table. The `interface-design.md` position was incorrect.

**Evidence**:
- **ibus-hangul**: `ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` (not `hangul_ic_reset()`) on `IBUS_CONTROL_MASK | IBUS_MOD1_MASK`. Flushed text committed via `ibus_engine_commit_text()`.
- **fcitx5-hangul**: `HangulState::keyEvent()` calls `flush()` (wrapping `hangul_ic_flush()`) on Control/Alt/Super.
- **ghostty sequential calls**: ghostty's key encoder processes each `ghostty_surface_key()` call independently. Committed text with `composing=false` is written to PTY as plain text. A subsequent Ctrl+C call goes through keybinding check independently. No state interaction between consecutive calls.
- **PoC validation**: All 10 test scenarios pass with FLUSH behavior (poc.c lines 127-148).
- **User expectation**: Discarding "하" on Ctrl+C is silent data loss. The user typed those characters intentionally. Commit first, then interrupt.

**Affected sections in 01-interface-contract.md**:
- Section 2 (Processing Pipeline) — Already correct (shows flush for Ctrl+C)
- Scenario matrix in Section 3.2 — Already correct (shows committed text for modifier cases)

**Affected sections in interface-design.md** (separate update):
- Section 1.4 (Modifier Flush Policy) — Change RESET to FLUSH for Ctrl/Alt/Super/Escape
- Section 3 (Responsibility Matrix) row #3 — Change "Resets (discards)" to "Flushes (commits)"
- Remove rationale about ghostty `composing` flag interaction (incorrect concern)

---

## Resolution 5: is_composing Derivation Without LanguageDescriptor

**Issue**: With `LanguageDescriptor` removed, how does libitshell3 determine whether the current language supports composition?

**Resolution**: Two separate questions, two separate answers:
- **"Can this language compose?"** (static) — libitshell3 hardcodes: `direct = no`, `korean = yes`. libitshell3 creates the engine, so it knows.
- **"Is there preedit right now?"** (runtime) — Use `engine.isEmpty()`. Returns false when jamo are in the buffer.

No `LanguageDescriptor.is_composing` field needed.

**Future note**: Japanese/Chinese engines may have non-composing sub-modes within a "composing" language. `isEmpty()` already answers the runtime question correctly for those cases too. No interface change needed.

**Affected sections in 01-interface-contract.md**:
- Section 3.3 — Remove `LanguageDescriptor` entirely (covered by Resolution 1)
- Add a note in Section 4 that libitshell3 derives composing capability from LanguageId

---

## Resolution 6: Language Switch Committed Text Uses Same ghostty Path

**Issue**: Does committed text from `setActiveLanguage()` flush require any special handling in the ghostty integration layer?

**Resolution**: No. Same `ghostty_surface_key(composing=false, text=...)` call as any other ImeResult with committed text.

**Evidence**: ghostty's key encoder (`src/input/key_encode.zig`) does not distinguish the source of committed text. It checks `composing`, `utf8`, `key`, `mods`. With `composing=false`, text present, and no modifiers, text is written directly to PTY.

**Implementation note**: For the language-switch flush event, set `key = .unidentified` and `mods = empty`.

**Affected sections in 01-interface-contract.md**:
- Section 5 (ghostty Integration) — No change needed; existing code already handles this uniformly

---

## Resolution 7: FrameUpdate Language Indicator Is Purely Metadata

**Issue**: Does ghostty's RenderState or Surface need to be aware of the current IME language?

**Resolution**: No. ghostty has zero language-related state. The language indicator is a `u8` metadata field in the FrameUpdate protocol, rendered by the client in its status bar.

**Evidence**: ghostty-expert searched all 6300+ lines of `Surface.zig` and all renderer code. No `language`, `locale`, `ime`, or `input_method` fields exist. `renderer_state.preedit` contains only codepoints — no language metadata.

**Affected sections in 01-interface-contract.md**:
- No change needed (Section 5 does not mention language indicator)
- Relevant to future FrameUpdate protocol document (outside scope of interface contract)

---

## Resolution 8: deactivate/activate Preserves Language, ghostty Is Stateless

**Issue**: When a pane is deactivated and reactivated, should the language mode be preserved? Does ghostty Surface need to be informed?

**Resolution**: Language is preserved in the engine's `active_language` field across deactivate/activate. ghostty Surface has no language state and does not need to be informed.

- `deactivate()`: flushes composition (committed text sent via `ghostty_surface_key()`), clears preedit overlay (`ghostty_surface_preedit(null, 0)`), does NOT change `active_language`.
- `activate()`: no-op for Korean (state is in HangulInputContext). Engine is already in the correct language mode.
- Client receives current language via `getActiveLanguage()` in FrameUpdate metadata.

**Affected sections in 01-interface-contract.md**:
- Section 3.4 — Add doc comment to `activate`/`deactivate` noting language preservation
- Section 4 (Responsibility Matrix) — "Per-pane ImeEngine lifecycle" row already covers this

---

## Resolution 9: forward_key from setActiveLanguage Is Always Null

**Issue**: Can `setActiveLanguage()` ever return a non-null `forward_key`?

**Resolution**: No. Always null. The toggle key is consumed by Phase 0 before the engine is called.

**Rationale**:
- Phase 0 detects the toggle key, calls `engine.setActiveLanguage(next_lang)`, and marks the key as consumed.
- `setActiveLanguage()` is not processing a key — it's responding to an already-consumed shortcut.
- If a forward_key leaked through, ghostty would produce garbage (Right Alt -> ESC prefix in legacy mode) or silently ignore it (CapsLock).

**Affected sections in 01-interface-contract.md**:
- Section 3.4 — Add doc comment to `setActiveLanguage` noting `forward_key` is always null in the returned ImeResult
- Scenario matrix in Section 3.2 — Already has "Mode toggle (Korean->direct)" row showing `forward_key = null`

---

## Resolution 10: ghostty_input_key_s.keycode Expects Platform-Native Keycodes

**Issue**: The v0.1 contract's ghostty integration code (Section 5) shows `mapHidToGhosttyKey(key.hid_keycode)` but does not specify what the output keycode space is.

**Resolution**: The `keycode` field in `ghostty_input_key_s` is a `uint32_t` expecting **platform-native keycodes**, not USB HID usage codes:
- **macOS**: Carbon virtual key codes (e.g., `kVK_ANSI_A = 0x00`, `kVK_Return = 0x24`)
- **Linux**: XKB keycodes
- **Windows**: Win32 keycodes

The mapping can be derived from ghostty's own `keycodes.zig` `raw_entries` table, which contains `{ USB_HID, evdev, xkb, win, mac, W3C_code }` tuples. At compile time, the correct platform column is selected.

**Affected sections in 01-interface-contract.md**:
- Section 5 (ghostty Integration) — Document that `mapHidToGhosttyKey()` produces platform-native keycodes
- Section 5 (Two HID Mapping Tables) — Clarify output keycode space for the HID-to-ghostty table

---

## Resolution 11: Explicit Preedit Clearing Required

**Issue**: Does ghostty automatically clear the preedit overlay when committed text is sent, or must libitshell3 clear it explicitly?

**Resolution**: ghostty will NOT auto-clear preedit. From Surface.zig: "The core surface will NOT reset the preedit state on charCallback or keyCallback and we rely completely on the apprt implementation to track the preedit state correctly."

libitshell3's Phase 2 handler MUST call `ghostty_surface_preedit(NULL, 0)` whenever `preedit_changed=true` and `preedit_text=null`. The v0.1 contract's example code in Section 5 already handles this correctly, but it should be documented as a mandatory requirement, not just shown in example code.

**Affected sections in 01-interface-contract.md**:
- Section 5 (ghostty Integration) — Add explicit requirement note that preedit must be manually cleared

---

## Summary of All Revisions

| # | Resolution | Sections Affected |
|---|-----------|-------------------|
| 1 | Remove `getSupportedLanguages`, `setEnabledLanguages`, `LanguageDescriptor` | 3.3, 3.4, 3.5, 4 |
| 2 | `flush()` + field assign for language switch | 3.5 |
| 3 | Same-language = no-op | 3.4, 3.5 |
| 4 | FLUSH on modifiers, not RESET | (already correct), interface-design.md needs fix |
| 5 | Derive is_composing from LanguageId + isEmpty() | 3.3, 4 |
| 6 | Same ghostty path for switch committed text | (no change) |
| 7 | FrameUpdate indicator is metadata | (no change) |
| 8 | Language preserved across deactivate/activate | 3.4, 4 |
| 9 | forward_key from setActiveLanguage always null | 3.4 |
| 10 | ghostty keycode is platform-native, not HID | 5 |
| 11 | Explicit preedit clearing required | 5 |

**Additional required update**: `interface-design.md` Section 1.4 and responsibility matrix row #3 must be corrected from RESET to FLUSH for modifier keys.
