# Daemon v1.0-r5 Verification — Round 1

**Date**: 2026-03-15
**Verdict**: Issues found — fix required.

---

## Confirmed Issues

### SEM-01 — Post-debounce Idle suppression duration inconsistency

**Severity**: minor
**Location**: `01-internal-architecture.md` §3.4 vs `04-runtime-policies.md` §5.7
**Phase 1 source**: semantic-verifier
**Phase 2 verdict**: confirm (both history-guardian and issue-reviewer)

**Description**: Two normative clauses contradict each other on post-debounce Idle suppression:

- `01-internal-architecture.md` §3.4: "During the debounce window and for **500ms after the debounce fires**, the server MUST NOT transition the pane's coalescing tier to Idle."
- `04-runtime-policies.md` §5.7: "During an active resize drag (daemon receiving WindowResize events within the **250ms debounce window**), the daemon suppresses the Idle timeout." — no mention of any post-debounce suppression period.

An implementation following doc04 §5.7 alone would allow the pane to transition to Idle immediately after the debounce fires, which conflicts with the MUST NOT rule in doc01 §3.4.

**Required fix**: Align the two documents. Either add the 500ms post-debounce suppression to doc04 §5.7, or remove/clarify it in doc01 §3.4. One document must be the normative source; the other must reference it or match it exactly.

---

### CRX-02 — `Disconnect` reason field notation inconsistency

**Severity**: minor
**Location**: `03-lifecycle-and-connections.md` lines 228, 734; `04-runtime-policies.md` lines 132, 496
**Phase 1 source**: consistency-verifier
**Phase 2 verdict**: confirm (both history-guardian and issue-reviewer)

**Description**: The `Disconnect` message reason field is written in four different notations across four locations:

| Location | Notation |
|----------|----------|
| doc03 line 228 | `reason: server_shutdown` (field notation, unquoted) |
| doc03 line 734 | `reason="version_mismatch"` (equals-sign, quoted string) |
| doc04 line 132 | `Disconnect("stale_client")` (parenthetical, quoted string) |
| doc04 line 496 | `Disconnect(TIMEOUT)` (parenthetical, unquoted constant) |

**Required fix**: Normalize all four occurrences to a single notation that matches the protocol spec's canonical form for reason values.

---

## Dismissed Issues

### CRX-01 — Missing v0.5 changelog entry (DISMISSED)

**Phase 2 verdict**: history-guardian dismiss (Category 1 — historical records), issue-reviewer confirm → **contested** → **owner decision: dismiss**
**Reason**: The `vX.Y changes:` lines are historical changelog entries, not current normative text. Missing a changelog entry for v0.5 is a gap in the historical record, not a spec defect.

---

## Summary

| Round | Issues Found | Confirmed | Dismissed |
|-------|-------------|-----------|-----------|
| Round 1 | 3 | 2 (SEM-01, CRX-02) | 1 (CRX-01) |
