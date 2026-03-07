# Cross-Document Consistency Review: Protocol v0.4 x IME Interface Contract v0.3

> **Status**: FEASIBLE — no blocking issues found
> **Date**: 2026-03-04
> **Review type**: Cross-document consistency review (parallel 3-reviewer)
> **Verdict**: The IME Interface Contract v0.3 is compatible with Protocol v0.4. All five end-to-end scenarios pass without gaps. Ten issues identified (1 critical, 3 moderate, 3 low, 3 informational) — all are documentation gaps or minor interface mismatches, none require architectural changes.

---

## Documents Reviewed

### Protocol v0.4 (6 documents)

| Doc | Title | Path |
|-----|-------|------|
| 01 | Protocol Overview | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/01-protocol-overview.md` |
| 02 | Handshake & Capability Negotiation | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/02-handshake-capability-negotiation.md` |
| 03 | Session & Pane Management | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/03-session-pane-management.md` |
| 04 | Input & RenderState | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/04-input-and-renderstate.md` |
| 05 | CJK Preedit Protocol | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/05-cjk-preedit-protocol.md` |
| 06 | Flow Control & Auxiliary | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/06-flow-control-and-auxiliary.md` |

### IME Interface Contract v0.3

| Doc | Title | Path |
|-----|-------|------|
| 01 | Interface Contract | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.3/01-interface-contract.md` |

---

## Participants

| Reviewer | Scope |
|----------|-------|
| input-preedit-reviewer | Protocol input/preedit messages (docs 04, 05) vs IME KeyEvent/ImeResult types |
| session-flow-reviewer | Handshake, session management, flow control (docs 02, 03, 06) vs IME lifecycle |
| e2e-feasibility-reviewer | Five end-to-end scenario traces through both document sets |

---

## Executive Summary

The IME Interface Contract v0.3 and Protocol v0.4 are **architecturally compatible**. The two-phase server pipeline (Phase 1: IME engine processing, Phase 2: ghostty surface calls + protocol message construction) is coherent across both document sets. All five end-to-end scenarios — Korean composition, modifier interruption, language toggle, pane switch, and preedit display pipeline — trace cleanly from client KeyEvent through ImeResult to protocol messages without structural gaps.

**Issue summary by severity:**

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 1 | Type width mismatch (`hid_keycode` u8 vs wire `keycode` u16) |
| MODERATE | 3 | Undocumented server responsibilities (shift extraction, composition_state derivation, cancel-on-language-switch) |
| LOW | 3 | Missing documentation for implicit behaviors (CapsLock drop, display_width derivation, Escape preedit reason) |
| INFO | 3 | Naming inconsistencies and redundancies (no action required unless addressed in a cleanup pass) |
| **Total** | **10** | |

No architectural changes are required. All issues are resolvable through documentation additions, minor interface extensions, or explicit cross-references.

---

## End-to-End Scenario Verification

All five scenarios were traced from client input through server IME processing to protocol wire messages and client rendering. Each scenario covers the full pipeline: KeyEvent (doc 04) -> ImeEngine.processKey() (contract S3) -> ImeResult -> ghostty surface calls -> protocol messages (docs 04/05) -> client rendering.

| # | Scenario | Verdict | Trace Summary |
|---|----------|---------|---------------|
| 1 | Korean composition "han-geul" | **PASS** | KeyEvent -> Phase 0 passthrough -> Phase 1 processKey() -> ImeResult with preedit_text -> Phase 2 ghostty_surface_preedit -> FrameUpdate (binary CellData + JSON preedit) + PreeditStart/Update (0x0401) -> client overlay rendering |
| 2 | Ctrl+C during active preedit | **PASS** | Phase 1 detects modifier -> flush() -> ImeResult{committed_text, forward_key=Ctrl+C} -> Phase 2: ghostty_surface_key(committed) + preedit clear + ghostty_surface_key(ETX) -> PreeditEnd(reason="committed") |
| 3 | Language toggle during composition | **PASS** | Two paths verified (client InputMethodSwitch 0x0404 and server Phase 0 hotkey). Both: setActiveLanguage() atomically flushes -> committed text via ghostty -> PreeditEnd + InputMethodAck. Toggle key consumed by Phase 0, forward_key always null |
| 4 | Pane switch during composition | **PASS** | FocusPaneRequest -> server calls deactivate() on old pane -> ImeResult with flush -> Phase 2 ghostty calls -> PreeditEnd(reason="focus_changed") -> activate() on new pane (language preserved) -> FocusPaneResponse + LayoutChanged |
| 5 | Preedit display pipeline (Tier 0) | **PASS** | ImeResult{preedit_text} -> ghostty_surface_preedit -> FrameUpdate construction (binary CellData + JSON preedit metadata). Dual-channel: FrameUpdate for rendering + PreeditUpdate(0x0401) for state tracking. Tier 0 immediate flush (0ms coalescing). Bypasses PausePane, power throttling, WAN coalescing |

---

## Issues Found

### CRITICAL

#### Issue 1: `hid_keycode` type mismatch — u16 (wire) vs u8 (IME)

**Documents**: Protocol doc 04 Section 2.1 (`keycode: u16`) vs IME contract Section 3.1 (`hid_keycode: u8`)

**Description**: The wire protocol defines the key event `keycode` field as `u16` (2 bytes), while the IME Interface Contract defines `hid_keycode` as `u8` (1 byte). USB HID Usage Table page 0x07 (Keyboard/Keypad) defines keycodes 0x00-0xE7 which fits in `u8`, so the IME type is functionally sufficient for standard keyboard input. However, the narrowing conversion from u16 to u8 at the server boundary is completely undocumented. If the wire ever carries a keycode above 0xFF (e.g., from a non-standard HID page or future extension), the server would silently truncate it.

**Recommendation**: Either:
- (a) Widen the IME `hid_keycode` field to `u16` to match the wire type exactly, or
- (b) Document explicitly in both docs that the server validates `keycode <= 0xFF` before passing to the IME engine, and that keycodes above 0xFF are rejected / handled by a non-IME path

Option (a) is preferred — it eliminates the mismatch entirely with no behavioral change, since Zig `u16` costs nothing extra in the struct and avoids a narrowing cast.

---

### MODERATE

#### Issue 2: Shift extraction from wire modifiers is undocumented

**Documents**: Protocol doc 04 Section 2.1 (`modifiers: u8`, bit 0 = Shift) vs IME contract Section 3.1 (`shift: bool` as separate field, `Modifiers{ctrl, alt, super_key}` without shift)

**Description**: The wire protocol packs all modifiers into a single `u8` bitmask with Shift at bit 0. The IME contract intentionally separates `shift` from the `Modifiers` struct because Shift directly affects Hangul composition (selecting uppercase letters, influencing jamo selection), while Ctrl/Alt/Super are modifier-flush triggers. This is a sound design decision. However, the server's responsibility to extract bit 0 from the wire `modifiers` bitmask and map it to the separate `shift: bool` field (while packing bits 1-3 into `Modifiers`) is not documented in either document.

**Recommendation**: Add a "Wire-to-IME KeyEvent mapping" note in the IME contract (Section 3.1 or a new subsection) or in Protocol doc 04, documenting the field mapping:
```
wire modifiers bit 0 (Shift)  -> KeyEvent.shift
wire modifiers bits 1-3       -> KeyEvent.modifiers{ctrl, alt, super_key}
wire modifiers bits 4-5       -> dropped (see Issue 3)
```

#### Issue 5: `composition_state` in protocol has no IME counterpart

**Documents**: Protocol doc 05 Section 2 (PreeditStart/PreeditUpdate include `composition_state` enum: `leading_jamo`, `syllable_with_tail`, etc.) vs IME contract ImeResult (no `composition_state` field)

**Description**: The CJK preedit protocol messages include a `composition_state` field that describes the Hangul syllable assembly stage. The IME ImeResult struct does not produce this field. The server must therefore derive composition_state from `preedit_text` via Unicode decomposition (NFC syllable -> decompose to check which jamo are present). While this derivation is deterministic, it is an undocumented server responsibility that requires non-trivial Unicode knowledge to implement correctly.

**Recommendation**: One of:
- (a) **Preferred**: Add `composition_state: CompositionState` to `ImeResult` and add a `getCompositionState()` method to `ImeEngine`. The engine already knows the internal state — exposing it avoids redundant Unicode decomposition.
- (b) Add a `getCompositionState()` query method to `ImeEngine` that the server calls after `processKey()`.
- (c) Document the server derivation algorithm explicitly, including the NFC decomposition rules for determining leading_jamo / vowel_only / syllable / syllable_with_tail.

#### Issue 8: InputMethodSwitch `commit_current=false` has no clean IME counterpart

**Documents**: Protocol doc 04 Section (InputMethodSwitch 0x0404, `commit_current: bool` field) vs IME contract Section 3.4 (`setActiveLanguage()` always flushes)

**Description**: The protocol allows the client to specify `commit_current=false` on InputMethodSwitch, meaning "cancel the current composition and switch language" rather than "commit and switch." However, the IME contract's `setActiveLanguage()` always performs a flush (commit), and `reset()` (which discards) followed by `setActiveLanguage()` would violate the atomicity requirement documented in contract Section 3.6 (reset + setActiveLanguage must not be interrupted). There is no single atomic "cancel and switch" operation.

**Recommendation**: One of:
- (a) Add a `cancelAndSwitch(language: LanguageId): ImeResult` method that atomically resets and switches.
- (b) Add a `commit: bool` parameter to `setActiveLanguage()`: `setActiveLanguage(lang, commit)`.
- (c) Document that `reset()` + `setActiveLanguage()` is the intended sequence, with a note that the server must hold the engine lock across both calls to satisfy atomicity.

---

### LOW

#### Issue 3: CapsLock/NumLock bits (wire bits 4-5) are silently dropped

**Documents**: Protocol doc 04 Section 2.1 (`modifiers` bits 4-5: CapsLock, NumLock) vs IME contract Section 3.1 (`Modifiers` has no CapsLock/NumLock fields)

**Description**: The wire protocol carries CapsLock and NumLock state in the modifiers bitmask, but the IME engine does not consume them. This is correct behavior — Hangul composition is not affected by lock keys, and the OS-level key event already reflects the lock state in the character value. However, the intentional omission should be documented to prevent future implementers from treating it as a bug.

**Recommendation**: Add a note in the IME contract Section 3.1: "CapsLock and NumLock (wire modifier bits 4-5) are intentionally not consumed by the IME engine. Lock key state is reflected in the key's character value before it reaches the IME."

#### Issue 6: `display_width` derivation is undocumented

**Documents**: Protocol doc 05 (PreeditUpdate includes `display_width: u8`) vs IME contract ImeResult (no `display_width` field)

**Description**: PreeditUpdate messages include a `display_width` field for terminal column width of the preedit text. The IME engine does not produce this value. The server must compute it: Hangul syllable (U+AC00-U+D7A3) = 2 columns, standalone jamo (U+1100-U+11FF, U+3131-U+318E) = variable (typically 2 for compatibility jamo, 1 for conjoining jamo). The derivation rules are not documented.

**Recommendation**: Document the display_width computation rules in the protocol doc 05 or add a `getDisplayWidth()` utility to the IME contract. Since this is a well-known Unicode East Asian Width property, a cross-reference to UAX #11 may suffice.

#### Issue 9: Escape preedit behavior — flush vs cancel contradiction

**Documents**: IME contract Section 3.3 (Escape -> flush / commit preedit) vs Protocol doc 05 Section 2.3 (PreeditEnd reason "cancelled" listed with "User pressed Escape" as example)

**Description**: The IME contract specifies that Escape causes a flush (commit the current preedit text), consistent with the v0.2 -> v0.3 review resolution (Resolution 4: modifier flush policy). However, Protocol doc 05 lists "User pressed Escape" as an example of the "cancelled" reason for PreeditEnd. These are contradictory: if Escape flushes (commits), the PreeditEnd reason should be "committed", not "cancelled".

**Recommendation**: Update Protocol doc 05 Section 2.3: change the Escape example from reason "cancelled" to reason "committed". Reserve "cancelled" for cases where preedit is discarded without committing (e.g., backspace-to-empty, explicit reset).

---

### INFO

These items are inconsistencies or redundancies that do not affect correctness but may be worth addressing in a documentation cleanup pass.

#### Issue 4: `keycode` (wire) vs `hid_keycode` (IME) naming inconsistency

**Documents**: Protocol doc 04 (`keycode`) vs IME contract Section 3.1 (`hid_keycode`)

**Description**: The wire field is named `keycode` while the IME struct field is named `hid_keycode`. Both refer to the same USB HID Usage ID. The IME name is more precise (explicitly noting the HID origin), but the difference may cause confusion when cross-referencing. No action required unless a naming unification pass is undertaken.

#### Issue 7: `committed_text` + `forward_key` ordering is verified correct

**Documents**: IME contract ImeResult field ordering, Protocol doc 04 key processing pipeline

**Description**: The ImeResult struct returns both `committed_text` and `forward_key`. The server must process `committed_text` first (feed to ghostty as composed text) then process `forward_key` (feed as a raw key event). This ordering is implicit in the struct but was verified correct by scenario traces. The committed text must reach the terminal before the forwarded key effect. No action needed — noted for completeness.

#### Issue 10: Language identifier representation mismatch

**Documents**: IME contract (`LanguageId` enum: `direct=0`, `korean=1`) vs Protocol docs (string identifiers: `"direct"`, `"korean_2set"`, `"korean_3set_390"`)

**Description**: The IME uses a simple two-value enum while the protocol uses strings that encode both language and keyboard layout. The protocol's `"korean_2set"` maps to IME `LanguageId.korean` + a separate `layout_id` concept. This two-level mapping (protocol string -> LanguageId + layout variant) is not documented in either document set. Since the server performs this mapping and both sides are internally consistent, this is not a functional issue, but a cross-reference note would aid implementers.

> **Owner directive (2026-03-05)**: `layout_id` values MUST use a language prefix for language-specific layouts to avoid ambiguity. For example, `"2"` alone is meaningless — use `"ko_2"` (Korean 2-set/두벌식), `"ko_3_390"` (Korean 3-set 390), etc. The language prefix makes the layout self-describing without requiring a separate `LanguageId` for disambiguation.
>
> For `direct` mode, `layout_id` currently defaults to the standard QWERTY layout, but future extensions may introduce layout variants such as `"azerty"` (French), `"qwertz"` (German), etc. The `layout_id` field should be designed to accommodate these without requiring `LanguageId` enum expansion — `direct` remains a single `LanguageId` value, with the physical layout expressed entirely through `layout_id`.
>
> This naming convention applies to both the IME contract's `layout_id: []const u8` and the protocol's string identifiers. The v0.4 spec should adopt the prefixed format (e.g., `"ko_2set"` instead of `"korean_2set"`) or at minimum ensure all layout strings are unambiguous without external context.

---

## Recommended Actions

### Immediate (before v0.4 finalization)

| Priority | Issue | Action |
|----------|-------|--------|
| P0 | Issue 1 (CRITICAL) | Widen IME `hid_keycode` to `u16`, or document server-side validation and truncation |
| P1 | Issue 5 (MODERATE) | Add `composition_state` to ImeResult or document server derivation algorithm |
| P1 | Issue 8 (MODERATE) | Define cancel-on-language-switch behavior — add method, parameter, or document reset+switch sequence with locking |
| P1 | Issue 9 (LOW) | Fix Escape preedit reason in Protocol doc 05 from "cancelled" to "committed" |

### Documentation (before implementation begins)

| Priority | Issue | Action |
|----------|-------|--------|
| P2 | Issue 2 (MODERATE) | Document wire-to-IME KeyEvent field mapping (shift extraction, modifier packing) |
| P2 | Issue 3 (LOW) | Document intentional CapsLock/NumLock omission in IME contract |
| P2 | Issue 6 (LOW) | Document display_width computation rules or add utility function |
| P2 | Issue 10 (INFO) | Add cross-reference note for protocol string to LanguageId+layout mapping |
| P3 | Issue 4 (INFO) | Consider naming unification (keycode vs hid_keycode) in a future cleanup pass |

---

## Appendix: Reviewer Reports

### input-preedit-reviewer

**Scope**: Consistency between Protocol doc 04 (Input & RenderState) and doc 05 (CJK Preedit) wire message definitions and the IME Interface Contract's KeyEvent input types and ImeResult output types.

**Focus areas**: Field types and widths, modifier mapping, composition state fields, preedit lifecycle events, language switch semantics.

**Issues found**: 10 (1 critical, 3 moderate, 3 low, 3 informational)

### session-flow-reviewer

**Scope**: Consistency between Protocol docs 02 (Handshake), 03 (Session & Pane Management), 06 (Flow Control & Auxiliary) and the IME Interface Contract's lifecycle methods (activate, deactivate, flush, reset), session persistence, and capability negotiation.

**Focus areas**: CJK capability negotiation, pane focus transitions, session restore sequence, preedit bypass in flow control, message type allocation.

**Key findings**:
- Handshake CJK capabilities: fully covered, no issues
- Session/pane management: sound, with minor observation on language string mapping (see Issue 10)
- Flow control preedit bypass: excellent — Tier 0 immediate, PausePane exception, WAN bypass all correct
- Session persistence gap: RestoreSessionResponse does not reference IME engine initialization (medium severity, captured as part of Issue 10 context)
- Snapshot schema: IME contract defines save fields (language + layout_id) but protocol does not define the persistence schema (low severity)

### e2e-feasibility-reviewer

**Scope**: Five end-to-end scenario traces exercising the full pipeline from client KeyEvent through server IME processing to protocol wire messages and client rendering.

**Scenarios verified**: Korean composition, Ctrl+C interruption, language toggle (client-side and server-side paths), pane switch during composition, preedit display pipeline with Tier 0 bypass.

**Verdict**: All five scenarios pass. No structural gaps between the two document sets. Minor observations:
- KeyEvent `input_method` field is redundant (engine tracks active language internally) — acceptable for debugging
- ghostty_surface_preedit() to FrameUpdate JSON intermediate step is implementation detail — correctly abstracted
- PreeditEnd reason for modifier-flush could be more specific ("flushed_by_modifier") but "committed" is acceptable
