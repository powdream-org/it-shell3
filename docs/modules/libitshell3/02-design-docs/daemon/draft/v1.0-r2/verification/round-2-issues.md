# Verification Round 2 Issues

**Round**: 2
**Date**: 2026-03-10
**Verifiers**: cross-reference-verifier, semantic-verifier, terminology-verifier, history-guardian

---

## Confirmed Issues

### V2-01: SplitNode remnants in v0.1 resolution doc R1 and R3 narrative

**Severity**: minor
**Source documents**: `draft/v1.0-r1/design-resolutions/01-daemon-architecture.md` — R1 module description (line 23), R3 decision sentence (line 80)
**Description**: V1-03 fix updated code blocks and rationale text but missed two narrative lines. R1 line 23 still says `SplitNode (tree shape, leaf = PaneId)` and R3 line 80 still says "Each Session directly owns a SplitNode tree (binary split)." All other locations across all five documents use `SplitNodeData` and `PaneSlot`.
**Expected correction**: Replace `SplitNode (tree shape, leaf = PaneId)` with `SplitNodeData (tree shape, leaf = PaneSlot)` in R1; replace "SplitNode tree" with `SplitNodeData` tree or `tree_nodes` array in R3.
**Consensus note**: All 4 verifiers confirmed. The v0.1 resolution doc is living normative text (V1-03 was applied to it), so these are genuine stale residuals.

---

### V2-02: pty_master_fd vs pty_fd in doc 03 Step 6 pseudocode

**Severity**: minor
**Source documents**: `draft/v1.0-r2/03-lifecycle-and-connections.md` Section 1.1 Step 6 pseudocode
**Description**: The forkpty result is bound to `pty_master_fd`, but the kqueue registration line immediately after says `EVFILT_READ on pty_fd` — two names for the same fd within the same code block. All other documents use `pty_fd` exclusively. The `Pane` struct declares `pty_fd: posix.fd_t`.
**Expected correction**: Use `pty_fd` consistently throughout the Step 6 pseudocode block.
**Consensus note**: All 4 verifiers confirmed. Internal naming inconsistency within a single code block.

---

### V2-03: pane_slots placement contradicts between normative documents

**Severity**: critical
**Source documents**:
- `draft/v1.0-r1/design-resolutions/01-daemon-architecture.md` R1 rationale (line 55): "`pane_slots: [MAX_PANES]?*Pane` **in `server/`**" and "not by pointer, preserving the dependency boundary"
- `draft/v1.0-r2/01-internal-architecture.md` Section 3.3: `pane_slots: [MAX_PANES]?*Pane` inside `Session` annotated as `// core/session.zig`
- Also within v0.1 resolution doc itself: R1 (line 55) says "in server/" while R3 (line 88) shows pane_slots inside Session (in core/)
**Description**: Two normative documents contradict each other on where `pane_slots` lives and whether `core/` references panes by slot index or pointer. The v0.1 R1 rationale explicitly states the field is "in server/" to preserve the dependency boundary. The v0.2 spec places it inside `Session` in `core/session.zig` using `?*Pane`. The v0.2 resolution doc contains no resolution covering this placement change. This is a pre-existing contradiction (present within the v0.1 resolution doc itself), not introduced by v0.2 changes.
**Expected correction**: Owner decision required — either (a) move pane_slots back to server/ and update v0.2 doc 01, or (b) update v0.1 R1 rationale to reflect the actual placement in core/. The architectural invariant ("core/ depends on nothing") must be reconciled.
**Consensus note**: All 4 verifiers confirmed critical. History-guardian confirmed this is not a historical-record false alarm — both sources are current normative text.

---

## Dismissed Issues

### S2-02: State machine diagram vs transitions table for client disconnect

**Dismissed by**: All 4 verifiers unanimously.
**Reason**: Doc 03 Section 3.3 explicitly states the diagram shows "the primary graceful flow" and that unexpected disconnects are "a distinct path that skips DISCONNECTING." The document is intentionally scoped and internally coherent when read as a whole.
