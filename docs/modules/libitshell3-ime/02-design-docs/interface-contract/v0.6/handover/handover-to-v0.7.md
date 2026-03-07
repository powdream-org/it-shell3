# Handover: IME Interface Contract v0.6 to v0.7

**Date**: 2026-03-07
**Author**: owner

---

## Insights and New Perspectives

### Preedit rendering is ghostty's job, not the protocol's

The biggest lesson from this review cycle: we were over-engineering preedit delivery. The original model had FrameUpdate carrying a separate preedit JSON section (`cursor_x`, `cursor_y`, `text`, `display_width`) and the client interpreting it to draw a preedit overlay. A visual PoC (`poc/05-preedit-visual/preedit-visual.m`) proved this is unnecessary.

In our daemon-client architecture, the **server** calls `ghostty_surface_preedit()` on its own ghostty surface. ghostty internally renders the preedit as an overlay (block cursor for Korean, 2-cell wide, automatic positioning at terminal cursor). When the server serializes the frame, it injects preedit cells into the cell data. The **client** just renders cells — it has no concept of preedit. It never calls `ghostty_surface_preedit()`.

This insight cascaded into removing the dual-channel design, ring buffer bypass, `frame_type=0`, and all cursor/width fields from preedit messages.

### composition_state was a documentation exercise, not a feature

We spent multiple versions refining `composition_state` — 5 named states, state diagram, transition table, backspace trace, naming conventions. The libhangul PoC (`poc/04-libhangul-states/probe.c`, findings at `poc/04-libhangul-states/README.md`) showed that our documented states had factual errors (vowel_only reachability, double_tail distinguishability, missing 3-set state). More importantly, no component ever consumed these values. Rendering uses preedit text. Debugging uses preedit text. Session snapshots flush on save.

The entire `CompositionStates` struct in `HangulImeEngine` and `composition_state` field in `ImeResult` exist solely to populate a protocol field that nothing reads. The lesson: don't model what you don't consume.

### Source code reading is not a substitute for visual PoCs

We read ghostty's renderer source code (`addPreeditCell()`, cursor suppression path) and concluded preedit uses "foreground + underline, cursor suppressed." The visual PoC showed block cursor with blinking vertical bar — the opposite. The source reading was done on upstream ghostty (`2502ca29`), while the binary was from the it-shell v1 fork (`76b77047`). Different commits, different behavior. Trust the binary you're shipping, not the source you're reading.

---

## Design Philosophy

### The client is a dumb renderer

The daemon-client protocol should send cells, not semantics. The client doesn't need to know "this is preedit" or "this is a cursor" or "this cell has composition state X." It receives a grid of cells with attributes and renders them. All intelligence — IME composition, preedit injection, cursor styling — lives server-side.

### libhangul is the ground truth for Korean composition

We should not maintain a parallel state machine in our documents. libhangul's `hangul_ic_process()` output is authoritative. Our contract defines the interface boundary (`processKey()` → `ImeResult`) but does not duplicate libhangul's internal logic.

### Simplify aggressively, extend additively

v1 PreeditUpdate is 3 fields: `pane_id`, `preedit_session_id`, `text`. That's it. v2 can add `anchor` for candidate window positioning. v2+ can add `candidates` for Japanese/Chinese. Each addition is optional and backward-compatible. Don't design for v2 in v1's wire format.

---

## Owner Priorities

1. **Remove `composition_state` from `ImeResult`** — no exceptions, no "keep it for debugging." If someone needs composition state for debugging, they can query libhangul's boolean flags directly inside the engine. It does not belong in the public interface.

2. **Remove `CompositionStates` struct entirely** — and the naming convention note. These were solely for the removed field.

3. **Remove `composition_state` column from scenario matrix** — the matrix is the contract's most useful artifact. Keep it accurate to what `ImeResult` actually contains.

4. **Remove memory model note for `composition_state`** — Section 6 should only document fields that exist.

5. **Update `setActiveInputMethod` examples** — remove `.composition_state = null` from all `ImeResult` examples in Section 3.6.

All of these are tracked in `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.6/cross-team-requests/01-protocol-composition-state-removal.md`.

---

## New Conventions and Procedures

None introduced in this session.

---

## Pre-Discussion Research Tasks

### 1. Preedit cell injection into FrameUpdate

Before writing v0.7, research how the server should inject preedit cells into the frame cell data:
- How does ghostty's `renderer.State.preedit` interact with cell serialization?
- What cell attributes should preedit cells have (foreground color, decoration flags)?
- How should dirty tracking handle preedit changes (preedit is not in the terminal grid, so grid dirty bits don't naturally cover it)?
- `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.7/research/07-ghostty-preedit-cell-serialization.md` has initial findings, but implementation-level details are needed.

### 2. Verify ghostty preedit behavior on latest upstream

The visual PoC used the it-shell v1 fork (`76b77047`). The source reading used upstream (`2502ca29`). Before finalizing the rendering model, build and test with the ghostty version we'll actually ship. Confirm block cursor behavior is stable.
