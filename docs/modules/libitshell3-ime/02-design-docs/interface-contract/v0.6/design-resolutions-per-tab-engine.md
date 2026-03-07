# Design Resolutions: Per-Session Engine Architecture

**Version**: v0.6
**Date**: 2026-03-05
**Status**: Resolved (full consensus)
**Participants**: principal-architect, ime-expert, cjk-specialist
**Discussion rounds**: 3 (initial proposals, counterpoints with protocol analysis, convergence)
**Source issues**: Owner Decision 3 (per-tab engine), Handover v0.5-to-v0.6 Section "Per-Discussion Research Tasks" Item 2

---

## Table of Contents

1. [Engine Lifecycle](#resolution-1-one-imeengine-instance-per-session)
2. [Focus-Change Preedit Handoff](#resolution-2-flush-commit-on-intra-session-pane-focus-change)
3. [activate()/deactivate() Semantics](#resolution-3-activatedeactivate-scoped-to-session-level-focus)
4. [deactivate() Must Flush](#resolution-4-deactivate-must-flush-pending-composition)
5. [Shared Engine Memory Ownership](#resolution-5-shared-engine-memory-ownership-invariant)
6. [Engine Pane-Agnosticism](#resolution-6-engine-is-completely-pane-agnostic)
7. [New Pane Inherits Session Input Method](#resolution-7-new-pane-inherits-sessions-current-input-method)
8. [Session Persistence Schema](#resolution-8-session-persistence-moves-to-session-level)
9. [LayoutChanged Leaf Nodes](#resolution-9-layoutchanged-leaf-nodes-kept-redundant-with-normative-note)
10. [AttachSessionResponse Simplification](#resolution-10-attachsessionresponse-session-level-input-method-fields)
11. [InputMethodSwitch Wire Format](#resolution-11-inputmethodswitch-removes-per_pane-keeps-pane_id)
12. [InputMethodAck Session-Wide Scope](#resolution-12-inputmethodack-normative-note-on-session-wide-scope)
13. [Preedit Exclusivity Rule](#resolution-13-preedit-exclusivity-rule)
14. [Preedit Lifecycle Messages Unchanged](#resolution-14-preedit-lifecycle-messages-unchanged)
15. [FrameUpdate Unchanged](#resolution-15-frameupdate-unchanged)
16. [Vtable Unchanged](#resolution-16-vtable-signatures-unchanged)
17. [Wire Protocol Changes Summary](#wire-protocol-changes-summary)
18. [IME Contract Sections Requiring Updates](#ime-contract-sections-requiring-updates)
19. [Prior Art References](#prior-art-references)

---

## Resolution 1: One ImeEngine instance per session

**Consensus (3/3).** The server creates one `HangulImeEngine` instance per session (what the owner calls a "tab"). All panes within a session share the same engine instance and the same `active_input_method` state.

- Created on session creation: `HangulImeEngine.init(allocator, "direct")`
- Destroyed on session destruction: `engine.deinit()`
- The zero-pane scenario does not arise -- closing the last pane destroys the session (doc 03 Section 10, Q1).
- The engine has no pane awareness. It is a pure composition state machine. If it sits idle with no `processKey()` calls, nothing happens -- no timers, no background state, no resources held beyond the `HangulInputContext` allocation.

**Replaces**: The v0.5 per-pane model where each Pane holds its own ImeEngine.

**Rationale**: The owner decided (Decision 3) that switching to Korean in one pane should affect the whole tab. A shared engine naturally provides this -- all panes route key events to the same engine, which has a single `active_input_method`. This matches typical terminal multiplexer UX expectations.

**Affected sections**: 3.5 (ImeEngine doc comment), 3.7 (session persistence text), 4 (responsibility matrix), 5 (ghostty integration examples), 9 (session persistence).

---

## Resolution 2: Flush (commit) on intra-session pane focus change

**Consensus (3/3).** When focus moves from pane A to pane B within the same session, the server calls `engine.flush()` and routes the committed text to pane A's PTY.

**Sequence:**

1. Server calls `engine.flush()` -- commits in-progress composition
2. Server consumes ImeResult immediately: sends `committed_text` to pane A's PTY via `ghostty_surface_key()`, clears pane A's preedit overlay via `ghostty_surface_preedit(null, 0)`
3. Server sends `PreeditEnd(pane=A, reason="focus_changed")` to all clients (immediate delivery, bypasses coalescing -- already specified in doc 05 Section 7.7)
4. Server updates `focused_pane = pane_b`
5. Pane B starts with empty composition. Next `processKey()` results route to pane B.

**Edge case -- engine already empty**: `flush()` returns `ImeResult{}` (all null/false). The server does nothing. The path is uniform regardless of composition state.

**Alternatives considered:**

- **Reset (cancel)**: Rejected. Data loss -- user loses typed jamo. Violates the settled flush policy (all composition-breaking events flush, never cancel).
- **Preserve/restore composition across pane switches**: Rejected. libhangul has no snapshot/restore API. Over-engineered -- users don't switch panes mid-syllable and expect to continue. ibus-hangul and fcitx5-hangul both flush on focus-out with no restoration on focus-in.

**libhangul safety (confirmed by ime-expert)**: After `hangul_ic_flush()`, all jamo slots are zeroed by `hangul_buffer_clear()`, `hangul_ic_is_empty()` returns true. The next `hangul_ic_process()` starts a completely fresh composition. libhangul has no concept of "context" -- it is a pure state machine. No lingering state between pane switches.

**Affected sections**: 5 (ghostty integration -- handleKeyEvent routing).

---

## Resolution 3: activate()/deactivate() scoped to session-level focus

**Consensus (3/3).** `activate()` and `deactivate()` are redefined as session-level focus methods. `flush()` is used for intra-session pane focus changes.

| Event | Engine method | Description |
|---|---|---|
| Intra-session pane focus change | `flush()` | Commit composition. Engine stays active. Server routes result to old pane. |
| Inter-session tab switch (away) | `deactivate()` | Commit composition + engine-specific cleanup. Engine goes idle. |
| Inter-session tab switch (to) | `activate()` | Signal engine becoming active. No-op for Korean. |
| App loses OS focus | `deactivate()` | Same as inter-session switch. |
| Session close | `deactivate()` then `deinit()` | Clean shutdown. |

**Rationale**: `flush()` ends the current composition session. `deactivate()` ends the engine's active period entirely. For Korean (v1), the distinction is invisible -- `deactivate()` IS `flush()`. But the contract is designed for multiple languages. For future engines (e.g., Japanese with candidate window), `deactivate()` may dismiss candidate UI, save user dictionary, release candidate caches -- behavior that would be wasteful and UX-breaking for a lightweight intra-session pane switch where the engine remains active.

**Server-side code pattern:**

```
// Intra-session pane focus change
result = session.engine.flush()
consume(pane_a.pty, result)     // MUST consume before next engine call
// route keys to pane B

// Inter-session tab switch
result = session1.engine.deactivate()
consume(session1.focused_pane.pty, result)
session2.engine.activate()
```

**Discussion note**: cjk-specialist initially argued for using `deactivate()/activate()` uniformly for all focus transitions (intra and inter), citing code path simplicity. The future Japanese engine scenario (candidate window dismissal, dictionary persistence, cache release on intra-tab pane switch) persuaded them to concede. The semantic distinction between "composition done" (`flush`) and "engine going idle" (`deactivate`) is important for future correctness.

**Affected sections**: 3.5 (ImeEngine vtable doc comments for `activate`, `deactivate`, `flush`).

---

## Resolution 4: deactivate() MUST flush pending composition

**Consensus (3/3).** New normative requirement for all ImeEngine implementations:

> `deactivate()` MUST flush any pending composition before returning. The returned `ImeResult` contains the flushed text. Calling `flush()` before `deactivate()` is redundant but harmless (deactivate on empty composition returns empty ImeResult).

**Rationale**: Prevents a bug class where a future engine implementation forgets to flush in `deactivate()`. For Korean: `deactivate()` calls `hangul_ic_flush()` internally. For future Japanese: `deactivate()` calls `flush()` then dismisses candidate UI.

**Affected sections**: 3.5 (ImeEngine vtable, `deactivate` doc comment).

---

## Resolution 5: Shared engine memory ownership invariant

**Consensus (3/3).** New paragraph for Section 6 (Memory Ownership):

> **Shared engine invariant**: When multiple panes share a single engine instance (per-session ownership), the caller MUST consume the `ImeResult` (process `committed_text` via `ghostty_surface_key`, update preedit via `ghostty_surface_preedit`) before making any subsequent call to the same engine instance. This is required because the next call overwrites the engine's internal buffers. In practice, this is satisfied naturally: the server processes one key event at a time on the main thread, and `ImeResult` consumption is synchronous within the key handling path.

**Rationale**: With per-pane engines (v0.5), there was no contention -- each pane had its own buffers. With shared per-session engine, buffer ownership becomes a documented invariant. The constraint was implicitly true before; it must be explicit now.

**Affected sections**: 6 (Memory Ownership).

---

## Resolution 6: Engine is completely pane-agnostic

**Consensus (3/3).** The engine has no concept of `pane_id`, `session_id`, or focus state. It processes keys and manages composition. The server is the routing layer that directs `ImeResult` to the correct pane's PTY and surface.

No `focusChanged(pane_id)` or similar method will be added to the vtable.

**Rationale**: The engine's abstraction level is composition logic. Pane routing is a server concern. Adding pane awareness would couple the engine to the session model, violating Design Principle #5 (testable via trait) and complicating mock injection.

**Affected sections**: 4 (responsibility matrix -- clarify engine vs server boundaries).

---

## Resolution 7: New pane inherits session's current input method

**Consensus (3/3).** When a new pane is created (e.g., via split), it inherits the session's current `active_input_method`. No engine API call is needed -- the server routes key events from the new pane to the shared engine when it gets focus.

If the new pane immediately gets focus (typical for pane splits), the server calls `flush()` first to commit any in-progress composition on the previously focused pane (same intra-session focus change sequence defined in Resolution 2).

**Replaces**: v0.5 behavior where new panes default to `"direct"` with their own engine instance.

**Affected sections**: 4 (responsibility matrix), protocol doc 03 (CreatePaneRequest, SplitPaneRequest default input method notes).

---

## Resolution 8: Session persistence moves to session level

**Consensus (3/3).** `input_method` and `keyboard_layout` move from per-pane to per-session in both the IME contract and session snapshot format.

**Current (v0.5, per-pane):**

```json
{
  "panes": [
    { "pane_id": 1, "ime": { "input_method": "korean_2set" } },
    { "pane_id": 2, "ime": { "input_method": "direct" } }
  ]
}
```

**Proposed (v0.6, per-session):**

```json
{
  "session_id": 1,
  "name": "my-session",
  "ime": {
    "input_method": "korean_2set",
    "keyboard_layout": "qwerty"
  },
  "panes": [
    { "pane_id": 1 },
    { "pane_id": 2 }
  ]
}
```

On restore: one engine created per session with the saved `input_method` string. All panes share the engine. Preedit is not restored (commit-on-restore rule unchanged).

**keyboard_layout also at session level**: Both orthogonal axes of the engine's configuration (`input_method` + `keyboard_layout`) live at the same scope. A user does not expect different panes in the same tab to have different physical keyboard layouts.

**Affected sections**: 9 (Session Persistence -- entire section rewrite).

---

## Resolution 9: LayoutChanged leaf nodes kept redundant with normative note

**Consensus (3/3).** Keep `active_input_method` and `active_keyboard_layout` in per-pane leaf nodes of the LayoutChanged layout tree. All leaves carry the same value, reflecting the session's shared engine state. Add a normative note:

> All leaf nodes in a session MUST have identical `active_input_method` and `active_keyboard_layout` values. The server populates these from the session's shared engine state.

**Rationale:**

1. **No wire format breaking change** -- clients that parse per-pane input method from leaf nodes continue to work unchanged.
2. **Self-contained leaf nodes** -- a client rendering a pane can look at just the leaf node without walking up to session-level fields.
3. **Future-proofing** -- if v2 supports per-pane override (e.g., "pin this pane to direct mode"), the wire format already supports it.
4. **Trivially cheap** -- a few extra JSON bytes per leaf node.

**Affected docs**: Protocol doc 03 (LayoutChanged normative note).

---

## Resolution 10: AttachSessionResponse session-level input method fields

**Consensus (3/3).** Replace the `pane_input_methods` array in AttachSessionResponse with session-level fields:

```json
{
  "status": 0,
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "active_input_method": "korean_2set",
  "active_keyboard_layout": "qwerty"
}
```

The `pane_input_methods` array is no longer needed because all panes share the same input method. A single session-level field suffices. Leaf nodes in LayoutChanged (Resolution 9) provide the same data per-pane for self-containedness.

**Affected docs**: Protocol doc 03 (AttachSessionResponse, AttachOrCreateResponse).

---

## Resolution 11: InputMethodSwitch removes `per_pane`, keeps `pane_id`

**Consensus (3/3).** The InputMethodSwitch (0x0404) wire format changes:

- **Remove `per_pane` field**: Obsolete with per-session engine. There is no meaningful `per_pane=true` behavior.
- **Keep `pane_id`**: All C->S messages use `pane_id` for addressing. Protocol consistency wins over semantic precision. The server derives the session from the pane.

**Revised wire format:**

```json
{
  "pane_id": 1,
  "input_method": "korean_2set",
  "keyboard_layout": "qwerty",
  "commit_current": true
}
```

**Server behavior change**: The server applies the input method switch to the entire session (all panes), not just the identified pane. This is documented in the behavior description.

**Rationale for not adding `session_id`**: Introducing session-level addressing in C->S messages would be a precedent change. Currently, the client addresses everything by pane. Mixing pane-addressed and session-addressed messages adds complexity. The server already maintains the `pane_id -> session_id` mapping.

**Discussion note**: cjk-specialist initially proposed adding `session_id` + keeping `pane_id`. After considering the protocol consistency argument (all C->S messages use pane_id), they accepted the simpler approach.

**Affected docs**: Protocol doc 05 (Section 4.1 InputMethodSwitch, Section 4.3 Per-Pane Input Method State).

---

## Resolution 12: InputMethodAck normative note on session-wide scope

**Consensus (3/3).** InputMethodAck (0x0405) keeps `pane_id` (set to the focused pane when the switch occurred). Add a normative note:

> InputMethodAck `pane_id` identifies the pane that was focused when the input method switch occurred. Clients MUST update the input method state for ALL panes in the session, not just the identified pane.

This clarifies the session-wide scope without changing the wire format.

**Affected docs**: Protocol doc 05 (Section 4.2 InputMethodAck).

---

## Resolution 13: Preedit exclusivity rule

**Consensus (3/3).** New normative rule for doc 05:

> At most one pane in a session can have active preedit at any time. This is naturally enforced by the single engine instance per session -- the engine has one `HangulInputContext` with one jamo stack.

**Rationale**: The single-engine architecture makes this invariant implicit. Stating it explicitly enables protocol-level validation and prevents future confusion if the preedit protocol is read in isolation from the IME contract.

**Affected docs**: Protocol doc 05 (Section 1 overview or new normative section).

---

## Resolution 14: Preedit lifecycle messages unchanged

**Consensus (3/3).** PreeditStart, PreeditUpdate, PreeditEnd, and PreeditSync remain per-pane messages. Preedit rendering happens at a specific pane's cursor position. The fact that the engine is shared does not affect the preedit wire format.

`PreeditEnd` with `reason="focus_changed"` (doc 05 Section 7.7) already handles the intra-session pane focus change case. No new reason values are needed.

**Affected docs**: None (no changes needed).

---

## Resolution 15: FrameUpdate unchanged

**Consensus (3/3).** FrameUpdate does not carry `active_input_method` as a top-level field. The client tracks input method state via the two-channel model:

1. LayoutChanged leaf nodes (authoritative on attach/structural change)
2. InputMethodAck (incremental on switch)

No change is needed to FrameUpdate or doc 04.

**Affected docs**: None.

---

## Resolution 16: Vtable signatures unchanged

**Consensus (3/3).** The ImeEngine vtable retains its 8 methods with identical signatures. Only doc comments change:

| Method | Doc comment change |
|---|---|
| `activate` | "Pane gained focus" -> "Session gained focus (e.g., user switched to this tab). No-op for Korean." |
| `deactivate` | "Pane lost focus. Engine should flush pending composition." -> "Session lost focus (e.g., user switched to another tab, app lost OS focus). Engine MUST flush pending composition." |
| `flush` | "Used when: pane switch, language switch, focus loss." -> "Used when: intra-session pane focus change, language switch. Also called internally by deactivate()." |

All other methods (`processKey`, `reset`, `isEmpty`, `getActiveInputMethod`, `setActiveInputMethod`) are unchanged.

**Affected sections**: 3.5 (ImeEngine vtable doc comments only).

---

## Wire Protocol Changes Summary

### Removed fields

| Message | Field | Reason |
|---------|-------|--------|
| InputMethodSwitch (0x0404) | `per_pane` | Obsolete with per-session engine |

### Modified messages

| Message | Change | Doc |
|---------|--------|-----|
| AttachSessionResponse | Replace `pane_input_methods` array with session-level `active_input_method` + `active_keyboard_layout` | Doc 03 |
| AttachOrCreateResponse | Same as above | Doc 03 |
| InputMethodAck (0x0405) | Add normative note: clients MUST update ALL panes in session | Doc 05 |
| LayoutChanged | Add normative note: all leaf nodes MUST have identical input method values | Doc 03 |

### No new message types

No new message types are introduced. The architectural change is handled entirely through semantic updates to existing messages.

---

## IME Contract Sections Requiring Updates

| Section | Change |
|---------|--------|
| 3.5 (ImeEngine) | "libitshell3's Pane holds an ImeEngine" -> "libitshell3's Session holds an ImeEngine". Doc comments for activate/deactivate/flush per Resolution 3, 4, 16. |
| 3.7 (HangulImeEngine) | "saved per pane" -> "saved per session" |
| 4 (Responsibility Matrix) | "Per-pane ImeEngine lifecycle" -> "Per-session ImeEngine lifecycle". Clarify engine pane-agnosticism. |
| 5 (ghostty Integration) | `handleKeyEvent` uses `session.engine` not `pane.ime`. `handleInputMethodSwitch` similar. Add intra-session focus change handling code example. |
| 6 (Memory Ownership) | Add shared engine invariant paragraph (Resolution 5). |
| 9 (Session Persistence) | Entire section rewrite: per-pane -> per-session schema (Resolution 8). |
| 10 (Open Questions) | Remove Q3 (resolved: per-session engine). |

---

## Prior Art References

| Decision | ibus-hangul | fcitx5-hangul | tmux/terminal UX |
|----------|------------|---------------|-------------------|
| Flush on focus change | `focus_out()` calls `hangul_ic_flush()` | `deactivate()` calls `flush()` | N/A (no IME) |
| No composition restore on focus-in | No restoration | No restoration | N/A |
| activate/deactivate semantics | `focus_in()`/`focus_out()` at window level | `activate()`/`deactivate()` at input context level | N/A |
| Per-tab (not per-pane) input method | N/A (desktop window manager) | fcitx5 global mode is per-seat, not per-window | tmux has no IME concept |
| Shared engine, single composition | One `HangulInputContext` per ibus engine instance | One hangul state per fcitx5 input context | N/A |
