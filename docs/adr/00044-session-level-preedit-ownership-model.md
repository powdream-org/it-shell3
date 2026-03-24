# 00044. Session-Level Preedit Ownership Model

- Date: 2026-03-24
- Status: Accepted

## Context

The daemon uses a per-session IME engine (one `ImeEngine` per session) that
processes keystrokes and produces composition (preedit) state. Two contention
scenarios exist:

1. **Multi-pane**: Can two panes in the same session have active preedit
   simultaneously? No — one engine, one composition state machine.
2. **Multi-client**: Can two clients attached to the same session both send
   composing keystrokes to the focused pane? Yes — tmux control-mode pattern.

The prior design used a `PanePreeditState` struct with `owner: ?u32`,
`preedit_text: []const u8`, and `preedit_session_id: u32`, placed per-pane. This
raised three problems:

- **Unclear scope**: The per-pane placement implied multi-pane contention
  tracking, but the per-session engine makes multi-pane simultaneous composition
  structurally impossible. Verification flagged this as a contradiction between
  doc04 §6.1 (per-pane ownership) and §11 ("physically impossible").
- **Redundant preedit text**: `PanePreeditState.preedit_text` duplicated
  `Session.current_preedit` (the authoritative preedit cache used by
  `overlayPreedit()` at export time). Two copies of preedit text with no defined
  sync semantics is a divergence bug waiting to happen.
- **Missing `preedit_pane` tracking**: No field recorded which pane had active
  preedit, raising the question of whether an explicit `preedit_pane` field was
  needed.

The IME engine API (`processKey(keycode, modifiers)`) has no `client_id`
parameter — it is completely client-agnostic. Without ownership tracking,
interleaved keystrokes from two clients would be composed into a single jamo
stack, producing silent data corruption (wrong Hangul output, not a crash).

## Decision

Three related decisions that form the session-level preedit ownership model:

**1. Orthogonal contention model.** The per-session engine prevents multi-pane
simultaneous composition (structural). `PreeditState.owner` handles multi-client
contention on the focused pane (behavioral). These are orthogonal invariants
documented separately: §11 covers multi-pane; §6.2 covers multi-client.

**2. Eliminate `PanePreeditState`.** Replace with a `PreeditState` sub-struct on
`Session`:

```zig
PreeditState {
    owner: ?u32,       // client_id of composing client, null = no active composition
    session_id: u32,   // monotonic counter for PreeditStart/Update/End/Sync wire messages
}
```

- `preedit_text` removed — `Session.current_preedit` is the single authoritative
  source for both rendering and ownership operations.
- Struct renamed from `PanePreeditState` to `PreeditState` (no per-pane
  granularity exists).
- Struct placed on `Session`, not `Pane` (preedit exclusivity is per-session).

**3. Focus-preedit invariant.** The pane with active preedit is always
`Session.focused_pane`. No explicit `preedit_pane` field. Proof: focus change
always commits preedit; new composition can only start on the focused pane;
therefore preedit on a non-focused pane is structurally impossible.

## Consequences

**What gets easier:**

- Ownership model is self-evident in the data structure — one `PreeditState` on
  `Session`, not 16 nullable instances across panes.
- No sync hazard between preedit text copies — single authoritative source.
- No `preedit_pane` field to keep synchronized with `focused_pane` — the
  invariant is maintained structurally by the focus-change procedure.
- Clear separation of concerns: §11 documents multi-pane prevention, §6.2
  documents multi-client ownership, no overlap.

**What gets harder:**

- If a future version introduces floating panes or detached compositions
  (preedit on a non-focused pane), the focus-preedit invariant would need to be
  relaxed, and `PreeditState` would need a pane identifier. This is not a v1
  concern.

**Obligations:**

- Every focus-change path must commit preedit before updating `focused_pane`.
  This is enforced by the §8.1 ownership transfer procedure referenced by all
  state-change procedures in §8.2-§8.4.
- `preedit_session_id` must be maintained as a monotonic counter — it has four
  wire protocol consumers (PreeditStart 0x0400, PreeditUpdate 0x0401, PreeditEnd
  0x0402, PreeditSync 0x0403) and is used for stale message detection.
