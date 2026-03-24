# Round 2 Verification Issues (Daemon v1.0-r7)

- **Date**: 2026-03-24
- **Phase 1**: consistency-verifier + semantic-verifier
- **Phase 2**: issue-reviewer-fast + issue-reviewer-deep

## Confirmed Issues

### V2-01 (Critical, New) — reset()/deactivate() conflict for last-focused-pane

**Location**: doc03 §3.2 steps 4 and 12 (lines 527-533, 567-577)

Step 4 runs `engine.reset()` (discards composition) when the destroyed pane is
the focused pane. Step 12 runs `engine.deactivate()` (flush committed text) for
the last-pane case. When the last pane IS the focused pane, both execute: step 4
discards the composition via `reset()`, then step 12 attempts to flush via
`deactivate()` — but there is nothing left to flush because `reset()` already
discarded everything.

**Expected correction**: Step 4 must branch: if session has remaining panes, run
`reset()` (discard — PTY is dead); if this is the last pane, skip `reset()` and
let step 12's `deactivate()` handle IME cleanup (flush committed text
best-effort before session destroy).

**Impact chain**: doc03 §3.2 steps 4 and 12 only.

---

### V2-03 (Minor, New) — doc01 bool fields vs doc03 bitmask syntax mismatch

**Location**: doc01 §3.3 (lines 548-550) vs doc03 §3.2 pseudocode

doc01 §3.3 Pane struct declares `pane_exited: bool` and `pty_eof: bool` (V1-01
fix). doc03 §3.2 pseudocode uses bitmask syntax: `pane.flags |= PANE_EXITED` and
`pane.flags |= PTY_EOF`. The two representations are inconsistent — doc01 uses
explicit booleans, doc03 uses a flags bitmask.

**Expected correction**: doc03 §3.2 pseudocode should use the bool field syntax
matching doc01: `pane.pane_exited = true` and `pane.pty_eof = true`, with the
trigger condition `if pane.pane_exited and pane.pty_eof`.

**Impact chain**: doc03 §3.2 pseudocode (SIGCHLD handler and PTY EOF handler).

---

### V2-04 (Minor, Pre-existing) — doc04 §5.3 overlayPreedit() step ordering

**Location**: doc04 §5.3 (lines 341-346)

Step 2 says "applies preedit via `overlayPreedit()` post-`bulkExport()`" but
`bulkExport()` does not happen until step 3. The ordering is self-contradictory:
step 2 references a post-condition of step 3.

**Expected correction**: Reorder steps: (1) processKey(), (2) RenderState
update + bulkExport, (3) overlayPreedit post-export, (4) flush to clients. Or
merge steps 2-3 into a single step with correct sequencing.

**Impact chain**: doc04 §5.3 only.

---

### R2-01 (Critical, Pre-existing) — doc04 §6.1 broken §11 reference

**Location**: doc04 §6.1 (line 454)

Cites "§11" for per-session IME engine preventing multi-pane simultaneous
composition. In v1.0-r6, §11 was "Design Decisions Log" which contained this
invariant. In v1.0-r7, §11 is now "Silence Detection Timer" (CTR-13 addition).
The old Design Decisions Log was renumbered to §12.

**Expected correction**: Remove the parenthetical citation entirely. The
sentence "The per-session IME engine prevents multi-PANE simultaneous
composition" is self-explanatory — the proof follows immediately in §6.1 itself.
No section reference needed.

**Impact chain**: doc04 §6.1 only. Same-class sweep confirmed no other stale §11
references in spec docs.

---

### R2-03 (Minor, New) — doc04 §11.6 trigger 2 spurious §2.1 reference

**Location**: doc04 §11.6, cleanup trigger 2 (line 947)

Trigger 2 cites "doc03 Sections 2.1, 3.3". Section 2.1 is "Daemon Graceful
Shutdown", not client disconnect. Section 3.3 is "Client Disconnect
(Unexpected)" which is correct. The §2.1 reference is spurious — introduced
during the V1-09 fix (which corrected the label from "Graceful disconnect" to
"Client disconnect" but added an incorrect section reference).

**Expected correction**: Remove "2.1" from the citation, leaving only "doc03
Section 3.3". Or use loose prose: "Client disconnect handler (doc03)".

**Impact chain**: doc04 §11.6 only.

---

## Dismissed Issues

### V2-02 (Minor, New) — Owner-directed dismiss

Dismissed by owner direction during Round 2 review. Details in Round 2
verification session.

### R2-02 (Minor, New) — Resolution doc "doc03 Section 7" reference

Fast-pathed: fixed immediately during Round 2 verification. Cross-CTR table row
5 (line 563 of resolution doc) updated from "doc03 Section 7" to "per protocol
docs". This was a missed instance from the R1-01 fast-path fix.

## Cascade Analysis

**Cluster A+B** (V2-01 + V2-03): Both touch doc03 §3.2. V2-03 also touches doc01
§3.3. V2-01 restructures step 4/12 branching; V2-03 updates flag syntax in the
same pseudocode. Must be handled by one writer sequentially. Risk: low
(localized changes, no cross-module impact).

**Cluster C** (V2-04 + R2-01 + R2-03): All in doc04, different sections (§5.3,
§6.1, §11.6). No interdependencies. Can be one writer. Risk: none (independent
single-line or small-block fixes).

Clusters A+B and C share no files — can run in parallel.
