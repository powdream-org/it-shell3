# Round 1 Verification Issues (Daemon v1.0-r7)

- **Date**: 2026-03-24
- **Phase 1**: consistency-verifier + semantic-verifier
- **Phase 2**: issue-reviewer-fast + issue-reviewer-deep

## Confirmed Issues

### V1-01 (Critical, New) — Pane struct missing two-phase flags

**Location**: doc01 §3.3 (Pane struct, lines 531-547) vs doc03 §3.2 (pseudocode)

doc03 §3.2 uses `pane.flags |= PANE_EXITED` and `pane.flags |= PTY_EOF` but
doc01 §3.3 Pane struct has no `flags` field — only `is_running: bool` and
`exit_status: ?u8`.

**Impact chain**: doc01 §3.3 must add flags (or two explicit booleans).

---

### V1-02 (Critical, New) — doc01 §3.4 still describes single-phase SIGCHLD

**Location**: doc01 §3.4 (PTY Lifecycle, lines 555-564)

doc01 §3.4 describes immediate single-phase SIGCHLD handling (set flag, send
notification, close pane). Contradicts the new two-phase model in doc03 §3.2.
The resolution doc states doc01 §3.4 should reference doc03 §3.2 as the single
authoritative specification.

**Impact chain**: doc01 §3.4 must be rewritten to forward to doc03 §3.2.

---

### V1-03 (Critical, New) — doc01 §3.11 broken "doc03 Section 7" reference

**Location**: doc01 §3.11 (line 822)

Cites "doc03 Section 7" for the response-before-notification rule. Daemon doc03
Section 7 is "SSH Fork+Exec (Deferred to Phase 5)". The rule is defined in the
protocol docs.

**Impact chain**: doc01 §3.11 reference must use loose prose per cross-document
reference conventions.

---

### V1-04 (Critical, Pre-existing) — doc02 §4.1 broken "doc04 §11" reference

**Location**: doc02 §4.1 (line 340)

Cites "doc04 §11" for preedit exclusivity invariant. In v1.0-r7, doc04 §11 is
now "Silence Detection Timer" (was "Design Decisions Log" in v1.0-r6). The
invariant is in doc04 §6.1.

**Impact chain**: doc02 §4.1 reference must be updated to §6.1.

---

### V1-05 (Minor, New) — `destroySessionEntry()` shared function misleading

**Location**: doc03 §3.2 step 12 (line 567) and §3.4 (lines 733-738)

§3.2 step 12 calls `destroySessionEntry(session_entry, requester: null)` and
§3.4 claims both paths "reuse the same function." However, the Phase 3
notification ordering differs: CTR-14 (requester path) sends
DestroySessionResponse before SessionListChanged, while CTR-18 (SIGCHLD path)
sends SessionListChanged first with no response. The paths cannot share a single
function without conditional ordering.

**Owner direction**: Option A — drop the shared function claim. §3.2 step 12
inlines the last-pane destroy procedure. §3.4 narrative says "similar to" not
"reuses."

**Impact chain**: doc03 §3.2 step 12, doc03 §3.4 narrative (lines 733-738),
resolution doc shared teardown references.

---

### V1-07 (Minor, New) — doc03 §3.2 step 4 missing preedit state clearance

**Location**: doc03 §3.2 step 4 (lines 528-531)

Does `engine.reset()` + sends `PreeditEnd` but omits
`session.current_preedit = null` and `session.preedit.owner = null`, which doc04
§8.3 requires for pane-close procedures.

**Impact chain**: doc03 §3.2 step 4 only.

---

### V1-08 (Minor, Pre-existing) — doc03 §4.5 wrong protocol section reference

**Location**: doc03 §4.5 (line 884)

Cites "protocol doc 03 Section 8" for readonly attachment. Protocol doc03
Section 8 is "Multi-Client Behavior"; readonly permissions are in Section 9.

**Impact chain**: doc03 §4.5 only.

---

### V1-09 (Minor, New) — doc04 §11.6 wrong disconnect type reference

**Location**: doc04 §11.6, cleanup trigger 2 (line 947)

Labeled "Graceful disconnect" citing "doc03 Section 3.3." Section 3.3 is "Client
Disconnect (Unexpected)", not graceful disconnect.

**Impact chain**: doc04 §11.6 only.

---

### V1-10 (Critical, Pre-existing) — doc02 §2 broken "protocol doc 05 Section 7.7" reference

**Location**: doc02 §2 (line 565)

Cites "protocol doc 05 Section 7.7" but protocol doc 05 structure skips Section
7 entirely (goes 6 → 8). The referenced section does not exist. Found by
same-class sweep.

**Impact chain**: doc02 §2 only.

---

## Dismissed Issues

### V1-06 (Minor, New) — PreeditEnd ordering relative to DestroySessionResponse

Both Phase 2 reviewers dismissed. `PreeditEnd` in Phase 1 of §3.4 is IME
teardown required before PTY close, not a response-paired notification. The
response-before-notification rule applies to `DestroySessionResponse` vs
`SessionListChanged`, which is correctly ordered.

### R1-01 (Critical, New) — Resolution doc "doc03 Section 7" references

Fast-pathed: owner fixed immediately (3 occurrences in resolution doc updated to
"per protocol docs").
