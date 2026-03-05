# Review Notes 02: Owner Decisions on Open Questions

> **Date**: 2026-03-05
> **Source**: Owner (project lead)
> **Status**: Decided — apply in v0.6
> **Affects**: IME Interface Contract Section 10

---

## Decision 1: Hanja Key in Korean (Section 10, Q1)

**Decision: Ignore. Do not support Hanja conversion in Korean IME mode.**

The Korean IME engine handles Hangul composition only. Hanja (Chinese character) conversion is out of scope — not deferred, but explicitly excluded. The candidate callback mechanism (Section 7) remains available for future non-Korean engines (e.g., Chinese candidate selection), but will not be used for Korean Hanja.

**Rationale**: Hanja conversion is rare in modern Korean usage. Supporting it would add complexity to what should be a simple, focused Korean composition engine.

**Impact**: Section 10 Q1 can be removed. Section 7 (candidate callback) remains as-is for future Chinese/Japanese use.

---

## Decision 2: Dead Keys for European Languages (Section 10, Q2)

**Decision: Separate engine. Do NOT add dead key composition to the direct mode engine.**

European dead key sequences (e.g., `'` + `e` = `é`) must be implemented as a separate engine (e.g., `"european_deadkey"`) rather than adding composition logic to `direct` mode. The direct mode engine must remain the simplest possible passthrough (HID → ASCII, zero composition).

**Rationale**: Keeping `direct` mode clean and simple is a design principle. Mixing composition logic into the passthrough engine adds unnecessary complexity and coupling.

**Impact**: Section 10 Q2 can be replaced with a settled decision. `direct` mode stays pure passthrough. A future `"european_deadkey"` engine would follow the same ImeEngine vtable interface.

---

## Decision 3: Per-Pane vs Global Mode (Section 10, Q3)

**Decision: Global singleton engine instance per tab (session). Not per-pane.**

Instead of each pane having its own independent engine instance, use a single shared engine instance per tab (session). All panes within a tab share the same input method state.

**Rationale**: A global mode indicator per tab is more natural for users — switching to Korean mode in one pane should affect all panes in the same tab. This matches typical terminal multiplexer UX expectations.

**Impact**: This is an architectural change from the current per-pane design. The v0.6 revision must:
- Update the engine ownership model (one engine per tab/session, not per pane)
- Update session persistence (one `input_method` per tab, not per pane)
- Clarify preedit exclusivity (still one active preedit per pane, but the engine is shared)
- Update the protocol docs accordingly (per-pane `input_method` fields → per-tab)

---

## Decision 4: macOS Client OS IME Suppression (Section 10, Q4)

**Decision: Write a PoC macOS app to verify feasibility immediately.**

A proof-of-concept macOS app should be built to validate that:
1. Raw keycode capture (bypassing `interpretKeyEvents`) works correctly
2. `performKeyEquivalent` still handles system shortcuts (Cmd+Q, Cmd+H)
3. `NSTextInputClient` methods work for clipboard/services/accessibility without interfering with keyboard input
4. The pattern is viable for the production macOS client

**Status**: PoC in progress — delegated to IME specialist.
