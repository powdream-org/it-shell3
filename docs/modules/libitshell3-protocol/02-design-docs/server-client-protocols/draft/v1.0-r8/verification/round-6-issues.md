# Verification Round 6 Issues

- **Round**: 6
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V6-01 — Doc 02 Section 9.2 stale PreeditSync ordering (incomplete V5-03 fix)

- **Severity**: minor
- **Source documents**: Protocol v0.8 `02-handshake-capability-negotiation.md` Section 9.2 (lines 717–721); `03-session-pane-management.md` Section 1.6 (lines 198–202)
- **Description**: V5-03 corrected PreeditSync ordering in doc 03 Section 1.6 and doc 06 Section 2.3, but did not update doc 02 Section 9.2. Doc 02 Section 9.2 still lists: (1) LayoutChanged, (2) I-frame, (3) PreeditSync, (4) ClientAttached — placing PreeditSync AFTER the I-frame. Doc 03 Section 1.6 (corrected) lists PreeditSync BEFORE the I-frame per doc 06 Section 2.2's "context before content" principle.
- **Expected correction**: Update doc 02 Section 9.2 to match the corrected ordering: LayoutChanged → PreeditSync (if applicable, via direct queue) → I-frame → ClientAttached.
- **Consensus note**: All 4 verifiers confirmed.

### V6-02 — "PreeditSync-triggered frames" ambiguous terminology in Doc 06 Section 2.3

- **Severity**: minor
- **Source documents**: Protocol v0.8 `06-flow-control-and-auxiliary.md` Section 2.3 (line 276)
- **Description**: Doc 06 Section 2.3 reads: "All rendering frames (I-frames, P-frames, PreeditSync-triggered frames) go through the ring." The term "PreeditSync-triggered frames" is non-standard (appears nowhere else in any document) and ambiguous. PreeditSync is a direct-queue message, not a ring-buffer frame. The parenthetical conflates direct-queue control messages with ring-buffer rendering frames, potentially misleading readers into thinking PreeditSync travels through the ring.
- **Expected correction**: Remove "PreeditSync-triggered frames" from the enumeration. Replace with "(I-frames, P-frames)" only. Preedit content appearing as CellData within I/P-frames is already documented in doc 05 Sections 14.1–14.2.
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| R6-01 (Doc 06 Section 2.2 not naming PreeditUpdate in direct queue list) | No unanimous consensus reached. Reports conflicted on disposition. |
| R6-02 ("per-pane" qualifier for session-level attributes in Doc 03 Section 1.6) | "Per-pane" describes structural JSON placement in leaf nodes, not ownership semantics. Both doc 02 and doc 03 include inline normative qualification clarifying the session-shared nature. Unanimously dismissed. |
