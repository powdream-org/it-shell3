# Round 3 Verification Issues (Daemon v1.0-r7)

- **Date**: 2026-03-24
- **Phase 1**: consistency-verifier (sonnet) + semantic-verifier (sonnet)
- **Phase 2**: issue-reviewer-fast (sonnet) + issue-reviewer-deep (sonnet)

## Confirmed Issues

### V3-01 (Minor, Pre-existing) — doc01 §3.3 Pane struct missing silence fields

**Location**: doc01 §3.3 (lines 530-551)

CTR-13 resolution adds `silence_subscriptions` and `silence_deadline` to Pane
(doc04 §11.4 labels them "new fields" for `server/pane.zig`). doc01 §3.3 Pane
struct definition does not include them.

**Expected correction**: Add
`silence_subscriptions:
BoundedArray(SilenceSubscription, MAX_SILENCE_SUBSCRIBERS)`
and `silence_deadline: ?i64` to the Pane struct, with a reference to doc04 §11
for semantics.

**Impact chain**: doc01 §3.3 only.

---

### V3-02 (Minor, Pre-existing) — doc03 §3.3 missing removeClientSubscriptions()

**Location**: doc03 §3.3 (lines 651-668)

CTR-13 cleanup trigger 2 requires removing silence subscriptions on client
disconnect. doc03 §3.3 pseudocode omits `removeClientSubscriptions(client_id)`.

**Expected correction**: Add `removeClientSubscriptions(client.client_id)` to
the `Free ClientState` block before deallocation.

**Impact chain**: doc03 §3.3 only.

---

### V3-03 (Minor, Pre-existing) — doc03 §4.2 missing silence cleanup for detach

**Location**: doc03 §4.2 state transitions table (~line 808)

CTR-13 cleanup trigger 4 requires removing silence subscriptions on
OPERATING→READY (session detach). The DetachSessionRequest action column omits
this.

**Expected correction**: Extend the DetachSessionRequest action to include
removing silence subscriptions for the detached session's panes.

**Impact chain**: doc03 §4.2 only.

---

### V3-04 (Minor, Pre-existing) — doc04 §8.2 missing silence cleanup for eviction

**Location**: doc04 §8.2 eviction procedure (~line 658)

CTR-13 cleanup trigger 5 requires removing silence subscriptions on client
eviction. doc04 §8.2 three-step eviction procedure omits
`removeClientSubscriptions(client_id)`.

**Expected correction**: Add a step to call
`removeClientSubscriptions(client_id)` before or as part of connection teardown
(Step 3).

**Impact chain**: doc04 §8.2 only.

---

### V3-06 (Critical, Pre-existing) — doc03 §3.3 omits preedit ownership cleanup

**Location**: doc03 §3.3 (lines 651-668) vs doc04 §6.2 and §8.2

doc04 §8.2 requires that unexpected client disconnect triggers preedit
commit+ownership clearing if the disconnecting client is the preedit owner.
doc03 §3.3 states "no session cleanup needed" and omits preedit ownership check
entirely.

**Expected correction**: Add preedit ownership check to doc03 §3.3: if the
disconnecting client is `session.preedit.owner`, execute §8.1 steps 1-7 before
tearing down ClientState.

**Impact chain**: doc03 §3.3 only.

---

### V3-08 (Minor, Pre-existing) — "next most-recently-active client" unsupported

**Location**: doc04 §2.2 (lines 51-61)

doc04 §2.2 says daemon falls back to "the next most-recently-active healthy
client" but `SessionEntry` only stores a single `latest_client_id: u32` — no
history or timestamps to support MRU fallback.

**Expected correction**: Weaken the claim to match the data structure: fallback
to any remaining healthy client (e.g., largest dimensions), or document that
`latest_client_id` is updated on each client message so the "latest" is always
current and no second-place tracking is needed (just re-scan attached clients).

**Impact chain**: doc04 §2.2 only.

---

### V3-09 (Critical, Pre-existing) — Focus change doesn't clear preedit.owner

**Location**: doc01 §4.3 (lines 933-953) vs doc04 §8.3

doc01 §4.3 `handleIntraSessionFocusChange` clears `current_preedit` and sends
`PreeditEnd` but omits clearing `session.preedit.owner` and incrementing
`session.preedit.session_id`, both required by doc04 §8.3 → §8.1 steps 6-7.

**Expected correction**: Add `session.preedit.owner = null` and
`session.preedit.session_id += 1` to the pseudocode after `PreeditEnd` send.

**Impact chain**: doc01 §4.3 only.

---

### V3-12 (Critical, Pre-existing) — InputMethodSwitch missing cleanup

**Location**: doc04 §8.4 (lines 737-741)

`InputMethodSwitch` with `commit_current=false` calls `engine.reset()` but omits
clearing `session.current_preedit` and `session.preedit.owner`. Contrast with
§8.3 pane close which correctly does both.

**Expected correction**: Add clearing `session.current_preedit = null` and
`session.preedit.owner = null` after `engine.reset()` in the
`commit_current=false` path.

**Impact chain**: doc04 §8.4 only.

---

### V3-13 (Minor, Pre-existing) — LayoutChanged before WindowResizeAck

**Location**: doc04 §2.6 (lines 89-102)

`LayoutChanged` (step 3) is sent before `WindowResizeAck` (step 5), violating
the response-before-notification rule cited in doc01 §3.11. Owner confirmed.

**Expected correction**: Reorder steps so `WindowResizeAck` is sent to the
requesting client before `LayoutChanged` is broadcast to all clients. Or add a
note explaining why resize is an exception to the rule (if intentional).

**Impact chain**: doc04 §2.6 only.

---

### V3-14 (Minor, New) — Silence timer reset placement contradiction

**Location**: doc04 §11.3 (line 905) vs doc03 §3.2 Phase 2 (line 490)

doc04 §11.3: timer resets "after `read(pty_fd)`, before `terminal.vtStream()`".
doc03 §3.2 comment places it after `vtStream()` under "normal processing:
dirty_mask, silence timer reset, coalescing".

**Expected correction**: Update doc03 §3.2 comment to match doc04 §11.3 (silence
timer reset before vtStream). doc04 §11.3 is the normative source.

**Impact chain**: doc03 §3.2 comment only.

---

### V3-15 (Minor, Pre-existing) — "stale" terminology conflation

**Location**: doc04 §2.5 (lines 74-87)

§2.5 uses "becomes stale again" to describe re-entering resize exclusion within
the 5-second hysteresis window. §3.2 defines "stale" as a formal health state
requiring 60s timeout. Same word, different meanings. Owner confirmed.

**Expected correction**: Replace "becomes stale again" with "becomes
resize-excluded again" or "re-enters the exclusion state" to distinguish from
the formal health state.

**Impact chain**: doc04 §2.5 only.

---

### V3-16 (Minor, New) — PreeditEnd reason missing in doc03 §3.4

**Location**: doc03 §3.4 Phase 1 (~line 696) vs doc03 §3.2 step 12

doc03 §3.2 step 12 specifies `PreeditEnd{ reason: "session_destroyed" }`. doc03
§3.4 Phase 1 sends `PreeditEnd to all attached clients` without specifying a
reason field.

**Expected correction**: Add `reason: "session_destroyed"` to the PreeditEnd in
doc03 §3.4 Phase 1.

**Impact chain**: doc03 §3.4 only.

---

### V3-17 (Minor, Pre-existing) — "only scenarios" for reset() excludes error recovery

**Location**: doc04 §7.3 (lines 534-537) and §7.7 summary table

§7.3 claims `engine.reset()` is used "only" in non-last pane close and
`InputMethodSwitch`. §8.5 error recovery also uses `engine.reset()`. The §7.7
summary table omits the error recovery row.

**Expected correction**: Update §7.3 to include error recovery as a third
scenario. Add an error recovery row to §7.7 summary table.

**Impact chain**: doc04 §7.3 and §7.7 only.

---

## Fast-Pathed Issues

### V3-07 (Critical, New) — Last-pane deactivate() after PTY fd closed

Owner confirmed and fixed immediately during verification. `engine.deactivate()`

- PTY write moved from step 12 to step 4's last-pane branch (before step 6
  closes `pane.pty_fd`). Step 12 simplified to `engine.deinit()` +
  notifications.

---

## Dismissed Issues

### V3-05 (Minor, New) — doc03 §3.2 prose uppercase PANE_EXITED/PTY_EOF

Both Phase 2 reviewers dismissed. Category 4 — uppercase `PANE_EXITED`/`PTY_EOF`
in prose are conceptual flag names, not struct field references. The pseudocode
directly below uses correct bool field syntax. Standard documentation
convention.

### V3-11 (Critical, Pre-existing) — Commit source of truth contradiction

Owner dismissed. doc01 §3.8 describes cache authority at export time; doc04 §8.1
describes live ImeResult handling for PTY write. Consistent in full context —
the word "commit-to-PTY" in §3.8 is imprecise but not a design contradiction.

---

## Excluded Re-Raises

### V3-10 — destroySessionEntry() shared function

Excluded before Phase 2. Re-raise of V1-05 from Round 1 — owner chose Option A
(drop shared function, inline both paths) which was applied and verified.

---

## Cascade Analysis

**Cluster A** (V3-02 + V3-03 + V3-06 + V3-16): All in doc03. V3-02 and V3-06
both modify §3.3 (client disconnect). V3-03 modifies §4.2 (state transitions).
V3-16 modifies §3.4 (session destroy). One writer for doc03.

**Cluster B** (V3-09): doc01 §4.3 only. One writer.

**Cluster C** (V3-01): doc01 §3.3 only. Can combine with Cluster B (same file).

**Cluster D** (V3-04 + V3-08 + V3-12 + V3-13 + V3-15 + V3-17): All in doc04,
different sections. One writer.

**Cluster E** (V3-14): doc03 §3.2 comment. Can combine with Cluster A (same
file).

Final clusters: **A+E** (doc03, 5 issues), **B+C** (doc01, 2 issues), **D**
(doc04, 6 issues). All 3 clusters touch different files — parallel.
