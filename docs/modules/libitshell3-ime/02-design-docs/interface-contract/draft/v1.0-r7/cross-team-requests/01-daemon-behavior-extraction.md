# Extract Daemon Behavior from IME Contract Docs

**Date**: 2026-03-10
**Source team**: daemon
**Source version**: daemon v0.2
**Source resolution**: daemon v0.2 review note 04 (daemon-behavior-migration-from-protocol-and-ime)
**Target docs**: 01-overview, 02-types, 03-engine-interface, 04-ghostty-integration, 05-extensibility-and-deployment, design-resolutions-per-tab-engine
**Status**: open

---

## Context

The daemon design documents now exist (v0.2). Content describing daemon-side integration behavior (key routing architecture, ghostty API usage, per-session engine lifecycle, session persistence) was placed in IME contract docs when there was no daemon doc to hold it. The daemon team is absorbing this content into daemon v0.3. The IME contract docs should be reduced to the ImeEngine vtable API, type definitions, composition rules, and engine-internal behavior only.

This does NOT mean deleting content — it means replacing daemon behavioral descriptions with references to daemon docs where appropriate, and ensuring IME contract docs focus on "what the engine API is and how the engine behaves" rather than "what the daemon does with the engine."

**Coordination requirement**: The changes requested here MUST be applied simultaneously and consistently with the corresponding content being added to `libitshell3/02-design-docs/daemon/draft/v1.0-r3` documents. Removing behavioral descriptions from IME contract docs without the daemon docs being ready to receive them would create a gap in the design documentation.

## Required Changes

### 1. 01-overview §53-104 — Remove 3-phase key pipeline

- **Current**: Describes Phase 0 (global shortcuts, CapsLock toggle), Phase 1 (IME processKey), Phase 2 (ghostty integration: PTY write, key encode, preedit overlay)
- **After**: Keep only Phase 1 description (IME engine's role). Replace Phase 0 and Phase 2 with: "The daemon routes keys through a 3-phase pipeline. Phase 1 (IME processing) is defined by this contract; Phases 0 and 2 are defined in daemon design docs."
- **Rationale**: Phase 0 (shortcut interception) and Phase 2 (ghostty/PTY) are daemon responsibilities, not IME engine behavior

### 2. 01-overview §106-114 — Remove IME-before-keybindings rationale

- **Current**: Explains why daemon calls IME before ghostty keybinding check
- **After**: Remove. This is a daemon architectural decision about call ordering
- **Rationale**: IME contract defines the engine API; daemon decides when to call it

### 3. 01-overview §142-178 — Reduce responsibility matrix to IME-side only

- **Current**: Matrix includes both IME engine responsibilities and daemon responsibilities (input method switching, ghostty API calls, PTY writes, FrameUpdate, preedit delivery, per-session lifecycle, pane focus handling, language indicator)
- **After**: Keep IME engine rows (HID→ASCII mapping, jamo composition, composition state, ImeResult production). Remove daemon rows or replace with: "Daemon-side responsibilities (routing, PTY writes, ghostty integration, lifecycle management) are defined in daemon design docs."
- **Rationale**: Contract should define what the engine does, not what the daemon does

### 4. 04-ghostty-integration — Remove entire section or convert to reference

- **Current**: 300+ lines covering ImeResult→ghostty API mapping, `handleKeyEvent()` pseudocode, preedit clearing rules, `ghostty_surface_text()` prohibition, key encoder integration, HID→platform keycode mapping, focus change handling, input method switch ghostty integration, macOS/iOS IME suppression
- **After**: Replace with a brief reference section: "ghostty integration (how ImeResult is consumed by the daemon to drive ghostty APIs) is defined in daemon design docs. The IME engine has no direct interaction with ghostty." Keep only any content that describes engine-observable behavior (e.g., "the engine does not need to know about ghostty")
- **Rationale**: This entire section describes daemon↔ghostty integration, not IME engine behavior. The IME engine produces ImeResult; what happens after that is daemon's concern

### 5. 02-types §69-71 — Remove wire-to-KeyEvent decomposition detail

- **Current**: Notes that server decomposes protocol wire modifier bitmask into KeyEvent fields, CapsLock omitted because Phase 0 handles it
- **After**: Keep KeyEvent type definition. Remove wire decomposition detail and Phase 0 reference
- **Rationale**: How KeyEvent is populated from wire messages is daemon responsibility; IME contract only defines the KeyEvent type

### 6. 03-engine-interface §24-48 — Reduce activate/deactivate/flush to API contract only

- **Current**: Describes when daemon calls activate (session focus), deactivate (session unfocus), flush (pane focus change), with daemon-level lifecycle rationale
- **After**: Keep: vtable method signatures and their behavioral contracts (what the engine does when called). Remove: when/why the daemon calls them (session focus, pane focus, etc.)
- **Rationale**: IME contract defines what each method does; daemon docs define when to call them

### 7. 05-extensibility §125-160 — Remove session persistence procedure

- **Current**: Describes when to save/restore `input_method` and `keyboard_layout`, preedit flush-on-save, engine reconstruction from canonical string
- **After**: Keep: engine constructor accepts canonical input_method string. Remove: save/restore timing, flush-on-save policy, daemon persistence schema
- **Rationale**: Engine constructor API is IME contract; persistence lifecycle is daemon

### 8. 05-extensibility §72-122 — Remove C API boundary discussion

- **Current**: Discusses libitshell3-ime having no public C API, only `libitshell3.h` is public, client receives preedit via protocol
- **After**: Keep: "libitshell3-ime exports a Zig API only; it has no public C header." Remove discussion of libitshell3.h and client-side access patterns
- **Rationale**: The daemon's public API surface is daemon architecture, not IME contract

### 9. design-resolutions-per-tab-engine — Reduce to engine-side resolutions only

- **Current**: 16 resolutions covering both daemon architecture (R1: session owns engine, R2: flush on focus, R3: activate/deactivate scope, R4: deactivate must flush, R5: shared memory, R6: engine pane-agnostic, R7: new pane inheritance, R8: persistence schema) and protocol messages (R9-R16)
- **After**: Keep resolutions that define engine behavior (R4: deactivate flushes, R5: buffer ownership, R6: pane-agnostic). Annotate daemon-side resolutions (R1-R3, R7-R8) with: "Daemon-side implementation of this resolution is defined in daemon design docs." Keep protocol resolutions (R9-R16) as cross-references
- **Rationale**: Engine behavioral contracts stay; daemon lifecycle decisions move

## Summary Table

| Target Doc | Section | Change Type | Daemon Review Note Ref |
|-----------|---------|-------------|----------------------|
| 01-overview | §53-104 (3-phase pipeline) | Keep Phase 1 only | I1 |
| 01-overview | §106-114 (IME-before-keybindings) | Remove | I2 |
| 01-overview | §142-178 (responsibility matrix) | Keep IME rows only | I3 |
| 04-ghostty-integration | Entire section (§7-313) | Replace with reference | I4 |
| 02-types | §69-71 (wire decomposition) | Remove, keep type def | I9 |
| 03-engine-interface | §24-48 (lifecycle) | Keep API contract, remove "when" | I5 |
| 05-extensibility | §125-160 (persistence) | Remove procedure, keep constructor | I7 |
| 05-extensibility | §72-122 (C API boundary) | Reduce to one-liner | I8 |
| design-resolutions | R1-R8 (per-session engine) | Annotate daemon-side | I5 |
