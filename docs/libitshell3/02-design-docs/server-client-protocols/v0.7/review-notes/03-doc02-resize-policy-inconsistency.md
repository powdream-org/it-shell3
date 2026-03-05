# Doc 02 Multi-Client Resize Policy Inconsistency

**Date**: 2026-03-05
**Raised by**: verification team (round 2)
**Severity**: MEDIUM
**Affected docs**: doc 02 (02-handshake-capability-negotiation.md)
**Status**: open

---

## Problem

Doc 02 Sections 9.6, 9.9, and 9.2 describe the multi-client resize behavior using only `min()` semantics, without acknowledging the dual-policy model (`latest` default / `smallest` opt-in) introduced in v0.7.

Specific locations:

1. **Section 9.6 (line 834)**: States "Uses the minimum (cols, rows) across all attached clients (like tmux `aggressive-resize`)." This describes only the `smallest` policy and omits the `latest` policy entirely -- even though `latest` is the default.

2. **Section 9.9 (lines 858-884)**: The full resize algorithm uses only `min()` computation:
   ```
   Recompute effective_cols = min(client.cols for all attached clients).
   Recompute effective_rows = min(client.rows for all attached clients).
   ```
   This algorithm does not account for the `latest` policy (which uses the most recently active client's dimensions, not the minimum), nor stale client exclusion, nor resize debounce, nor re-inclusion hysteresis.

3. **Section 9.2 (lines 687-731)**: The `AttachSessionResponse` JSON example and field table are missing the `resize_policy` field. Compare with doc 03 Section 1.6 (line 210), which includes `"resize_policy": "latest"` in the example and documents the field as: `Server's active resize policy: "latest" or "smallest". Informational -- not negotiated. See Section 5.1.`

The authoritative spec for the resize algorithm is doc 03 Section 5.1, which fully documents both policies, stale exclusion, debounce, and re-inclusion hysteresis. Doc 01 Section 13.1 also correctly describes the dual-policy model. Only doc 02 was not updated.

## Analysis

This is a cross-document consistency issue, not a protocol ambiguity. The authoritative sources (doc 01 Section 13.1, doc 03 Section 5.1) are complete and consistent with each other. Doc 02 predates the v0.7 dual-policy additions and was not updated to match.

An implementor reading only doc 02 would believe that `min()` is the sole resize strategy and that `AttachSessionResponse` does not carry a `resize_policy` field. Reading doc 03 would correct this, but the inconsistency is confusing and could cause errors if doc 02 is used as a quick reference.

Impact is MEDIUM because:
- The authoritative spec (doc 03 Section 5.1) is correct and complete.
- Doc 02 is positioned as the handshake/session-attach overview, not the normative resize specification.
- However, doc 02 Section 9.9 presents a full algorithm (not a summary), which makes it look authoritative when it is actually stale.

## Proposed Change

**Option A**: Replace doc 02 Section 9.9 algorithm with a cross-reference to doc 03 Section 5.1, and update Sections 9.6 and 9.2 accordingly.

For Section 9.6 line 834, replace:
```
Uses the minimum (cols, rows) across all attached clients (like tmux `aggressive-resize`).
```
with:
```
Terminal dimensions are computed according to the server's resize policy (`latest` or `smallest`).
`latest` (default) uses the most recently active client's dimensions; `smallest` uses
min(cols, rows) across all eligible clients. See doc 03 Section 5.1 for the full algorithm.
```

For Section 9.9, replace the detailed algorithm with a summary and cross-reference:
```
### 9.9 Multi-Client Resize Algorithm

The server supports two resize policies (`latest` default, `smallest` opt-in) with stale
client exclusion, resize debounce, and re-inclusion hysteresis. See doc 03 Section 5.1 for
the full normative algorithm.

Per-client virtual viewports (where each client sees a viewport into a larger terminal) are
deferred to v2.
```

For Section 9.2, add `resize_policy` to both the JSON example and the field table, matching doc 03 Section 1.6.

- Pro: Eliminates duplication. Single source of truth for the resize algorithm in doc 03.
- Con: Doc 02 becomes less self-contained for readers who want a quick overview of session attach behavior.

**Option B**: Update doc 02 Sections 9.6, 9.9, and 9.2 to fully match doc 03 Section 5.1 content.

- Pro: Doc 02 is self-contained.
- Con: Duplicates the algorithm in two places, increasing future maintenance burden and inconsistency risk.

**Recommendation**: Option A. Doc 03 is the normative source for session/pane management; resize is a session-level concern. Doc 02 should summarize and cross-reference, not duplicate.

## Owner Decision

{Pending.}

## Resolution

{Open.}
