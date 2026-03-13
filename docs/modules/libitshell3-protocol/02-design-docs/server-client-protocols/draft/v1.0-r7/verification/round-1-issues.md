# Verification Round 1 Issues

## Round Metadata

- **Round**: 1
- **Date**: 2026-03-06
- **Verifiers**: semantic-verifier (sonnet), terminology-verifier (sonnet), cross-reference-verifier (sonnet), history-guardian (opus)

## Issue List

### V1-01 — `frame_sequence` scope in resolution summary table

| Field | Value |
|-------|-------|
| Issue ID | V1-01 |
| Severity | critical |
| Source document(s) | `design-resolutions/01-i-p-frame-ring-buffer.md` — "Wire Protocol Changes Summary" table and "Normative Notes Added/Changed" table vs. Resolution 19 body text; also Doc 04 Section 4.1, Doc 06 Section 2.3 |
| Description | The resolution doc summary tables state that `frame_sequence` is "incremented only for grid-state frames (section_flags bit 4 set)". Resolution 19 body text explicitly says ALL ring frames increment `frame_sequence`, including `frame_type=0` cursor-only frames which do NOT have section_flags bit 4 set. Doc 04 Section 4.1 and Doc 06 Section 2.3 also say "every frame written to the ring buffer" increments `frame_sequence`. The summary tables are the sole outlier. |
| Expected correction | Summary tables should read "incremented for every frame written to the ring buffer" (or equivalent), consistent with Resolution 19 body text and spec documents. |
| Consensus note | All 4 verifiers unanimously confirmed. Resolution 19 body text and both spec documents agree; only the summary tables are wrong. |

### V1-02 — Preedit bypass frame size "~90 bytes" vs "~110 bytes"

| Field | Value |
|-------|-------|
| Issue ID | V1-02 |
| Severity | critical |
| Source document(s) | **Wrong locations**: Doc 01 Section 10.1 Coalescing Tiers table ("90B/frame"), Doc 06 Section 1.5 power-aware throttling prose ("~90 bytes"). **Correct locations**: Doc 01 Section 10.3 ("~110B/frame"), Doc 05 Section 8.4 ("~110 bytes" with breakdown: 16 + 20 + 4 + ~70 = ~110), Doc 06 Section 2.2 ("~110 bytes"), Resolution 17 ("~110 bytes"). |
| Description | Two normative locations state the preedit-only bypass frame size as "~90 bytes" / "90B/frame". All other normative sources — including within the same document (Doc 01 Section 10.3) — state "~110 bytes". The ~110 byte figure is consistent with the wire format breakdown. The ~90 byte figure is stale. |
| Expected correction | Doc 01 Section 10.1: "90B/frame" should be "~110B/frame". Doc 06 Section 1.5: "~90 bytes" should be "~110 bytes". |
| Consensus note | All 4 verifiers unanimously confirmed. The ~110-byte breakdown is mathematically grounded; "~90 bytes" is a pre-revision artifact that was not updated when the frame format changed. |

## Dismissed Issues Summary

| Issue | Reason for Dismissal |
|-------|---------------------|
| T-01: Doc 06 v0.5 changelog "per-pane ImeEngine" | History-guardian veto accepted unanimously. The v0.5 changelog accurately records the design that existed at v0.5. The v0.7 changelog separately records the change to per-session architecture. Updating the v0.5 entry would be rewriting history. |
| T-03: Heading variation ("Preedit-Only FrameUpdate (Bypass Buffer)" vs "Preedit Bypass Buffer") | Dismissed unanimously. Real naming variation between Doc 05 Section 8.4 and Doc 06 Section 2.2, but no behavioral contradiction. Different documents may use contextually appropriate heading names for the same concept. |
| T-04: `preedit_active` vs `active_*` prefix pattern | Dismissed unanimously. Plausibly intentional distinction: `active_input_method` and `active_keyboard_layout` are string-valued state identifiers, while `preedit_active` is a boolean predicate. No behavioral contradiction. |
