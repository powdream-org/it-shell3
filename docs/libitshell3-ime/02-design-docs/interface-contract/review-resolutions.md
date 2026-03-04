# Interface Contract Review Resolutions

> **Date**: 2026-03-04
> **Reviewers**: principal-architect, ime-expert, ghostty-expert
> **Input documents**: [v0.1/01-interface-contract.md](v0.1/01-interface-contract.md), [v0.2/01-interface-contract.md](v0.2/01-interface-contract.md)
> **Output document**: [v0.3/01-interface-contract.md](v0.3/01-interface-contract.md)
>
> Resolutions 1–11: v0.1 → v0.2 review (spec-level review).
> Resolutions 12–17: v0.2 → v0.3 review (PoC validation against real ghostty — `poc/ime-ghostty-real/poc-ghostty-real.m`).

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

## Resolution 12: Space Key Handling — Flush + Forward with Text

**Issue**: The v0.2 scenario matrix (Section 3.2) and modifier flush policy table (Section 3.3) do not include Space. Space during Korean composition is handled specially in the PoC (`poc-ghostty-real.m` lines 263–274): flush composition, then forward Space. Space is the most frequently typed non-jamo key during Korean input (word separator), and its ghostty integration has a unique requirement not shared by other forwarded keys.

**Resolution**: Add Space to both the scenario matrix and the modifier flush policy table. Document the ghostty-specific requirement for Space forwarding.

**Scenario matrix additions:**

| Situation | committed | preedit | forward_key | preedit_changed |
|-----------|-----------|---------|-------------|-----------------|
| Space during composition | `"한"` (flush) | null | Space key | true |
| Space with empty composition | null | null | Space key | false |

**Modifier flush policy table addition:**

| Key Type | Preedit Action | Rationale |
|---|---|---|
| Space | **Flush** (commit preedit) | Word separator — commit syllable, then insert space |

**ghostty integration note**: When forwarding Space via `ghostty_surface_key()`, the key event MUST include `.text = " "` and `.unshifted_codepoint = ' '` (U+0020). This is because Space is a printable key — ghostty's key encoder needs the text field to produce the space character. Other forwarded special keys (Enter, Escape, arrows) work with `.text = null` because they have dedicated escape sequence encoding paths via `pcStyleFunctionKey()`. Space does not — it is treated as a character-producing key.

**Evidence**: PoC `apply_ime_result()` (lines 631–637) handles Space as a special case: `fwd_text = " "; fwd_codepoint = ' ';`. Without this, ghostty's key encoder produces no output for the forwarded Space. Verified by PoC Test 7 ("한" + Space + "글") which produces correct terminal output.

**Affected sections in 01-interface-contract.md**:
- Section 3.2 — Add Space rows to scenario matrix
- Section 3.3 — Add Space row to modifier flush policy table
- Section 5 — Add note that forwarded Space requires `.text = " "` and `.unshifted_codepoint = ' '` in `ghostty_input_key_s`; update `handleKeyEvent` pseudocode for the forward_key path

---

## Resolution 13: Press+Release Pairs Required for ghostty_surface_key

**Issue**: The v0.2 Section 5 `handleKeyEvent` pseudocode shows only a single `ghostty_surface_key()` call per committed text and per forwarded key. The PoC (`poc-ghostty-real.m` lines 600–608, 651–656) sends both press and release events for every `ghostty_surface_key()` call. The spec is incomplete by omission.

**Resolution**: Every `ghostty_surface_key()` press event MUST be followed by a corresponding release event. The release event has `action = GHOSTTY_ACTION_RELEASE` and `text = NULL` (no text on release — re-sending text would double-commit).

**Rationale**:
- **Internal state tracking**: ghostty tracks key state internally. Sending press without release may leave ghostty's key state machine in an incorrect state, believing the key is still held.
- **Kitty keyboard protocol (future)**: Kitty protocol mode requires release events for correct reporting. Legacy mode ignores releases (`key_encode.zig` line 322: `if (event.action != .press and event.action != .repeat) return;`), so releases are a no-op in legacy mode — but sending them is harmless and forward-compatible.
- **PoC validation**: All 24 PoC test scenarios send press+release pairs and pass.

**Implementation pattern**:
```zig
// Press with text/key
ghostty_surface_key(surface, .{ .action = .press, .text = text, ... });
// Release — always text=NULL
ghostty_surface_key(surface, .{ .action = .release, .text = null, ... });
```

**Note for committed text in legacy mode**: The release event produces no PTY output in legacy mode. It is strictly a state management concern and a forward-compatibility measure for Kitty protocol.

**Affected sections in 01-interface-contract.md**:
- Section 5 — Update `handleKeyEvent` pseudocode to show press+release pairs for both committed text and forwarded key paths
- Section 5 — Add note that release events have `text = null`

---

## Resolution 14: Keycode Criticality — Platform-Native Confirmed, PoC Bug Documented

**Issue**: Resolution 10 stated that `ghostty_input_key_s.keycode` expects platform-native keycodes. The PoC (`poc-ghostty-real.m` lines 122–141) uses `ghostty_input_key_e` enum values (W3C UIEvents abstract key enum) instead. The PoC tests pass despite this discrepancy, creating confusion about which approach is correct.

**Resolution**: Resolution 10 was correct. The PoC's use of `ghostty_input_key_e` enum values as keycodes is a **bug that was masked** by two factors:

1. **Committed text path**: When `.text` is set and `.composing = false`, ghostty's key encoder writes the UTF-8 text directly to PTY. The keycode is not used for text encoding. Committed text works regardless of keycode value.

2. **Forwarded key test coverage gap**: The PoC tests verify committed text output (e.g., "간" appears on screen) but do not verify forwarded key effects (e.g., Ctrl+C producing `0x03` ETX, arrow keys producing escape sequences).

**Evidence of the bug** (traced through ghostty source):

1. `embedded.zig:101–103`: `for (input.keycodes.entries) |entry| { if (entry.native == self.keycode) break :keycode entry.key; } else .unidentified;` — On macOS, `entry.native` contains Carbon virtual keycodes (e.g., A=`0x0000`, C=`0x0008`, Enter=`0x0024`). The PoC's enum values (A=130, C=132, Enter=63) do not match any native keycode. All keys resolve to `.unidentified`.

2. `key_encode.zig` legacy encoder for forwarded Ctrl+C with `.key = .unidentified`, `.text = ""`, `.mods = {.ctrl}`:
   - `pcStyleFunctionKey(.unidentified, ...)` — no match.
   - `ctrlSeq(.unidentified, "", 0, {.ctrl})` — `utf8.len == 1` is false (len=0), `logical_key.codepoint()` on `.unidentified` returns null. Returns null.
   - **No output produced.** The forwarded Ctrl+C is silently dropped.

3. With correct platform-native keycode (C = `0x0008` on macOS):
   - `embedded.zig` maps `0x0008` → `.key_c`
   - `ctrlSeq(.key_c, "", 'c', {.ctrl})` → `.key_c.codepoint()` returns `'c'` → produces `0x03` (ETX). Correct.

**Keycode criticality by event type**:

| Event Type | `.text` field | Keycode impact |
|---|---|---|
| Committed text | Non-empty | **Non-critical** — ghostty uses `.text` for PTY output |
| Forwarded key (control/special) | null | **Critical** — ghostty uses keycode for escape sequence encoding |
| Language switch flush | Non-empty | **Non-critical** — use `.unidentified` (no originating key) |

**Conclusion**: `mapHidToGhosttyKey()` MUST produce platform-native keycodes (Carbon virtual keycodes on macOS, XKB on Linux). The HID-to-platform-keycode mapping table derived from ghostty's `keycodes.zig` `raw_entries` is mandatory. Resolution 10 stands; no section changes needed beyond adding the criticality-by-event-type note.

**Affected sections in 01-interface-contract.md**:
- Section 5 (Two HID Mapping Tables) — Add note on keycode criticality by event type
- Section 5 (`handleKeyEvent` pseudocode) — Comment that for committed text, keycode is non-critical; for forwarded keys, keycode must be correct

---

## Resolution 15: preedit_changed Optimization — Mandatory for Production, Unconditional Always Correct

**Issue**: The v0.2 spec defines `preedit_changed: bool` in `ImeResult` (Section 3.2) for dirty tracking. The PoC does not implement this field — it unconditionally calls `ghostty_surface_preedit()` on every key event (lines 612–620). This raises the question of whether `preedit_changed` is necessary or premature optimization.

**Resolution**: `preedit_changed` is mandatory for the production implementation. Unconditional preedit calling is always correct but wasteful.

**Rationale**:
- `ghostty_surface_preedit()` triggers renderer state updates in ghostty. Calling it on every keystroke when preedit hasn't changed (e.g., Ctrl+C with no active composition, every English key in direct mode) causes unnecessary work.
- The dirty tracking is straightforward: compare current preedit content/length with previous preedit content/length. The `HangulImeEngine` struct already has `prev_preedit_len` for this purpose (v0.2 Section 3.7).
- Redundant `ghostty_surface_preedit(NULL, 0)` calls when no preedit is active are harmless (ghostty sets empty preedit on already-empty state — effectively a no-op). But redundant calls with unchanged non-null preedit text may trigger unnecessary renderer dirty marking.

**Implementation guidance**:
- The `HangulImeEngine.processKeyImpl()` MUST set `preedit_changed = true` whenever preedit text transitions: null→non-null, non-null→null, or non-null→different-non-null.
- The `HangulImeEngine.processKeyImpl()` MUST set `preedit_changed = false` when preedit is unchanged (e.g., key forwarded in direct mode, release event, modifier key with no active composition).
- Callers MAY ignore `preedit_changed` and call `ghostty_surface_preedit()` unconditionally as a safety fallback during debugging. This is always correct.

**Affected sections in 01-interface-contract.md**:
- Section 3.2 — Add note that `preedit_changed` is mandatory; unconditional calling is a correct fallback
- Section 5 — Add note that skipping preedit calls when `preedit_changed = false` is an optimization, not a correctness requirement

---

## Resolution 16: hangul_ic_process() Returns False — Key Rejection Edge Case

**Issue**: The v0.2 spec does not document what happens when `hangul_ic_process()` returns `false` (key not consumed by libhangul). The PoC handles this case at lines 312–322: check commit/preedit strings, flush if non-empty, forward the key. This edge case occurs with punctuation, certain number keys, and other characters that libhangul rejects.

**Resolution**: Document the `hangul_ic_process()` return-false edge case in the `processKey` pipeline.

**When does this happen?**
- Punctuation keys (period, comma, slash, etc.) in Korean mode — libhangul rejects them because they are not jamo.
- Number keys — behavior depends on the keyboard layout (dubeolsik: not consumed; some 3-set layouts may consume certain digits).
- Any key that libhangul's current keyboard layout does not recognize as a valid input character.

**Correct handling (from PoC lines 298–324)**:

1. Call `hangul_ic_process(hic, ascii)`.
2. **Regardless of return value**: Check `hangul_ic_get_commit_string()` and `hangul_ic_get_preedit_string()`. libhangul may update these even when returning false (e.g., a syllable break may produce committed text before the rejected character).
3. **If `hangul_ic_process()` returned false**:
   - If composition was non-empty, flush remaining composition via `hangul_ic_flush()`.
   - Forward the rejected key to the terminal.
4. Populate `ImeResult` with any committed text, updated preedit, and the forwarded key.

**Example**: User types "ㅎ" then ".":
- `hangul_ic_process(hic, '.')` returns false (period is not a jamo).
- `hangul_ic_get_commit_string()` returns empty (no syllable break triggered).
- `hangul_ic_get_preedit_string()` still returns "ㅎ" (still composing).
- Since not consumed: flush "ㅎ", forward ".".
- Result: `{ committed: "ㅎ", preedit: null, forward_key: '.', preedit_changed: true }`.

**Affected sections in 01-interface-contract.md**:
- Section 3.7 (HangulImeEngine) — Add implementation note documenting the `hangul_ic_process()` return-false handling
- Section 2 (Processing Pipeline) — Add note that Phase 1 must handle the "not consumed" case

---

## Resolution 17: Direct Mode Scenario Matrix Expansion

**Issue**: The v0.2 scenario matrix (Section 3.2) has only one row for direct mode: "English 'a' (direct mode)" with `committed = "a"`, `forward_key = null`. It does not document how direct mode handles non-printable keys (Enter, arrows, Tab), modified keys (Ctrl+C, Ctrl+D), or Space. The PoC (`poc-ghostty-real.m` lines 228–238) shows that direct mode forwards all non-printable and modified keys.

**Resolution**: Add the following rows to the scenario matrix for direct mode:

| Situation | committed | preedit | forward_key | preedit_changed |
|-----------|-----------|---------|-------------|-----------------|
| Direct mode 'a' | `"a"` | null | null | false |
| Direct mode Shift+'a' | `"A"` | null | null | false |
| Direct mode Enter | null | null | Enter key | false |
| Direct mode Space | null | null | Space key | false |
| Direct mode Ctrl+C | null | null | Ctrl+C key | false |
| Direct mode Arrow | null | null | Arrow key | false |
| Direct mode Escape | null | null | Escape key | false |

**Key behavior**: In direct mode, `processKey()` performs a simple branch:
- Printable key without modifiers → HID-to-ASCII lookup → `committed_text = ascii_char`, no forward.
- Everything else (non-printable, modified, unmapped) → `forward_key = original_key`, no committed text.

Direct mode never has preedit (no composition), so `preedit_changed` is always false.

**Note**: Direct mode printable keys bypass ghostty's key encoder entirely — the ASCII character is committed directly as text via `ghostty_surface_key(.text = "a", .composing = false)`. Only forwarded keys go through ghostty's keybinding check and key encoder.

**Affected sections in 01-interface-contract.md**:
- Section 3.2 — Add direct mode rows to scenario matrix

---

## Summary of All Revisions

| # | Resolution | Source | Sections Affected |
|---|-----------|--------|-------------------|
| 1 | Remove `getSupportedLanguages`, `setEnabledLanguages`, `LanguageDescriptor` | v0.1 review | 3.3, 3.4, 3.5, 4 |
| 2 | `flush()` + field assign for language switch | v0.1 review | 3.5 |
| 3 | Same-language = no-op | v0.1 review | 3.4, 3.5 |
| 4 | FLUSH on modifiers, not RESET | v0.1 review | (already correct), interface-design.md needs fix |
| 5 | Derive is_composing from LanguageId + isEmpty() | v0.1 review | 3.3, 4 |
| 6 | Same ghostty path for switch committed text | v0.1 review | (no change) |
| 7 | FrameUpdate indicator is metadata | v0.1 review | (no change) |
| 8 | Language preserved across deactivate/activate | v0.1 review | 3.4, 4 |
| 9 | forward_key from setActiveLanguage always null | v0.1 review | 3.4 |
| 10 | ghostty keycode is platform-native, not HID | v0.1 review | 5 |
| 11 | Explicit preedit clearing required | v0.1 review | 5 |
| 12 | Space key: flush + forward with `.text=" "` | PoC validation | 3.2, 3.3, 5 |
| 13 | Press+Release pairs required for `ghostty_surface_key` | PoC validation | 5 |
| 14 | Keycode criticality by event type (confirms Resolution 10; PoC had a bug) | PoC validation | 5 |
| 15 | `preedit_changed` mandatory for production, unconditional always correct | PoC validation | 3.2, 5 |
| 16 | `hangul_ic_process()` return-false edge case | PoC validation | 2, 3.7 |
| 17 | Direct mode scenario matrix expansion | PoC validation | 3.2 |

**Additional required update (from v0.1 review)**: `interface-design.md` Section 1.4 and responsibility matrix row #3 must be corrected from RESET to FLUSH for modifier keys.

**Informational notes (not formal resolutions — add to spec as footnotes or brief mentions)**:
- ghostty requires regular event loop processing via `ghostty_app_tick()` for I/O (Section 5 note, forward reference to daemon architecture)
- Left/Home arrow keys crash ghostty's VT parser in the headless/stream-backend build configuration; IME flush-on-cursor-move logic verified via Right arrow (Section 5 or appendix known limitation)
- The PoC's `ImeResult` uses `bool forward_key` + `KeyEvent original_key` (C simplification); the spec's `forward_key: ?KeyEvent` is the correct design for Zig (no spec change needed)
