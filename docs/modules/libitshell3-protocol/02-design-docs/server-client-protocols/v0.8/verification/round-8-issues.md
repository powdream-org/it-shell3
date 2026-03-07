# Verification Round 8 Issues

- **Round**: 8
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V8-01 — Doc 02 Section 10.1 stale "preedit overlays" terminology in behavior table

- **Severity**: minor
- **Source documents**: Protocol v0.8 `02-handshake-capability-negotiation.md` Section 10.1 (line 910)
- **Description**: The `"preedit_sync"` capability behavior table entry reads: "Multi-client preedit: all attached clients see **preedit overlays** from the composing client." The term "preedit overlays" is stale v0.7 terminology. In v0.8, preedit is rendered as cell data in I/P-frames, not as overlays. The `preedit_sync` capability controls the 0x04xx lifecycle messages (PreeditStart/Update/End/Sync), not a rendering overlay mechanism. The same document's normative Section 5.1 (lines 393–396) correctly describes `preedit_sync` without overlay language.
- **Expected correction**: Replace "preedit overlays from the composing client" with "preedit cell data from the composing pane" (or equivalent v0.8-consistent phrasing).
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| R8-S01 (Doc 01 Section 9.1 RowData header size 5B vs 9B) | No unanimous consensus (2 confirm, 2 dismiss). Dispute centers on whether selection_start/selection_end are always-present or conditional per doc 04 Section 4.3's "if bit 0" annotation and variable offset for num_cells. |
| R8-T02 (Doc 05 Section 9.3 "preedit overlay" in non-normative future section) | No unanimous consensus (2 confirm, 2 dismiss). Section 9.3 is explicitly labeled "Alternative: Resume Composition (Future)" and deferred to v2. Non-normative future speculation not held to current terminology standards. |
