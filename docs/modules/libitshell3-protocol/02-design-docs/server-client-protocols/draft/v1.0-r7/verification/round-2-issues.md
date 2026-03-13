# Verification Round 2 Issues

## Round Metadata

- **Round**: 2
- **Date**: 2026-03-06
- **Verifiers**: semantic-verifier (sonnet), terminology-verifier (sonnet), cross-reference-verifier (sonnet), history-guardian (opus)

## Issue List

### V2-01 — Doc 05 §8.2 imprecise preedit bypass condition

| Field | Value |
|-------|-------|
| Issue ID | V2-01 |
| Severity | minor |
| Source document(s) | Doc 05 Section 8.2 Rule 2 vs. Doc 04 Section 4.1 and Doc 06 |
| Description | Rule 2 says "When the preedit state changes (PreeditStart, PreeditUpdate, PreeditEnd), the server MUST flush the FrameUpdate immediately." This loose phrasing would include cursor-only preedit moves. The normative bypass condition in Doc 04/06 is precise: `frame_type=0 AND preedit JSON present AND (preedit.active changed OR preedit.text changed)`. Cursor-only metadata updates do NOT trigger bypass per Doc 04/06, but would satisfy Doc 05's phrasing. |
| Expected correction | Tighten Rule 2 to match the precise bypass condition from Doc 04. |
| Consensus note | All 4 verifiers unanimously confirmed. The imprecision could mislead implementers into bypassing for cursor-only preedit moves. |

### V2-02 — Doc 01 §5.7 health table omits stale recovery deliveries

| Field | Value |
|-------|-------|
| Issue ID | V2-02 |
| Severity | minor |
| Source document(s) | Doc 01 Section 5.7 "stale" row vs. Doc 06 Section 2.10, Resolution 14 |
| Description | The health table says "None (except preedit bypass)" for stale client frame delivery. Doc 06 §2.10 specifies that during stale recovery, LayoutChanged and PreeditSync are also sent via the direct message queue before the I-frame. The table omits these recovery-path deliveries. |
| Expected correction | Amend the "Frame delivery" cell for "stale" row to note that recovery sends LayoutChanged + PreeditSync via direct queue before the I-frame. |
| Consensus note | All 4 verifiers unanimously confirmed. The table describes steady-state correctly but is misleading about recovery. |

### V2-03 — Doc 05 §2.4 PreeditSync missing stale recovery trigger

| Field | Value |
|-------|-------|
| Issue ID | V2-03 |
| Severity | minor |
| Source document(s) | Doc 05 Section 2.4 vs. Doc 06 Section 2.10, Resolution 20 |
| Description | Doc 05 §2.4 describes PreeditSync only for the "late-joining client" (attach) scenario. Doc 06 §2.10 and Resolution 20 specify it is also enqueued during stale recovery. The send-trigger list is incomplete. |
| Expected correction | Add stale recovery as a second trigger for PreeditSync in Doc 05 §2.4. |
| Consensus note | All 4 verifiers unanimously confirmed. |

### V2-04 — Doc 04 §6.1 ScrollRequest I-frame delivery path unspecified

| Field | Value |
|-------|-------|
| Issue ID | V2-04 |
| Severity | minor |
| Source document(s) | Doc 04 Section 6.1 and Section 7.3 |
| Description | ScrollRequest gets a `frame_type=2` (I-frame) response. Unlike resize/screen-switch (global state changes), scroll is a per-client viewport operation. If the scroll I-frame is written to the shared ring, all clients would see a scrolled viewport they never requested. The spec does not specify that scroll I-frames must use the direct queue. |
| Expected correction | Specify that scroll-induced I-frames are delivered via the direct message queue (per-client), not the shared ring. |
| Consensus note | All 4 verifiers unanimously confirmed. This is a genuine design gap. |

### V2-05 — `CJK_CAP_PREEDIT` vs wire format string `"preedit"`

| Field | Value |
|-------|-------|
| Issue ID | V2-05 |
| Severity | minor |
| Source document(s) | Doc 04 Section 4.2 and Doc 05 Section 1 vs. Doc 02 (handshake) |
| Description | Two locations use `CJK_CAP_PREEDIT` (C-macro-style), but all wire format capability references use plain string `"preedit"`. |
| Expected correction | Replace `CJK_CAP_PREEDIT` with `"preedit"` in both locations. |
| Consensus note | All 4 verifiers unanimously confirmed. |

### V2-06 — `session_id` in struct vs `preedit_session_id` on wire

| Field | Value |
|-------|-------|
| Issue ID | V2-06 |
| Severity | minor |
| Source document(s) | Doc 05 Section 6.2 (PanePreeditState struct) vs. wire message payloads |
| Description | Struct definition uses `session_id: u32` but wire messages use `preedit_session_id`. |
| Expected correction | Change struct field to `preedit_session_id` to match wire format. |
| Consensus note | All 4 verifiers unanimously confirmed. |

### V2-07 — `STALE_CLIENT` all-caps vs `"stale_client"` lowercase

| Field | Value |
|-------|-------|
| Issue ID | V2-07 |
| Severity | minor |
| Source document(s) | Doc 06 Section 2.8 and Doc 01 Section 5.7 vs. Doc 02 Section 11.1 |
| Description | Doc 06 §2.8 and Doc 01 §5.7 use `STALE_CLIENT` (all-caps constant style). Doc 02 §11.1 defines disconnect reasons as lowercase strings. |
| Expected correction | Use `"stale_client"` (lowercase string) in Doc 06 §2.8 and Doc 01 §5.7. |
| Consensus note | All 4 verifiers unanimously confirmed. |

### V2-08 — Wire trace `reason=replaced` vs canonical `"replaced_by_other_client"`

| Field | Value |
|-------|-------|
| Issue ID | V2-08 |
| Severity | minor |
| Source document(s) | Doc 05 Section 6.4 vs. Doc 05 Section 6.3 |
| Description | Wire trace uses `reason=replaced` but the canonical value is `"replaced_by_other_client"`. |
| Expected correction | Change wire trace to `reason="replaced_by_other_client"`. |
| Consensus note | All 4 verifiers unanimously confirmed. |

### V2-09 — Unquoted `reason=cancelled` in wire trace

| Field | Value |
|-------|-------|
| Issue ID | V2-09 |
| Severity | minor |
| Source document(s) | Doc 05 Section 3.4 |
| Description | Wire trace shows `reason=cancelled` (unquoted) but all other wire traces in the document quote string values. |
| Expected correction | Change to `reason="cancelled"`. |
| Consensus note | All 4 verifiers unanimously confirmed. |

## Dismissed Issues Summary

| Issue | Reason for Dismissal |
|-------|---------------------|
| CR-A: Doc 03 v0.5 changelog "per-pane" vs normative Section 8 "per-session" | History-guardian veto accepted unanimously. The v0.5 changelog accurately describes what was added at v0.5 (per-pane design). The v0.7 changelog (Doc 03 line 1128) records the transition to per-session. Historical record is coherent. |
| CR-B: Doc 06 v0.5 changelog "per-pane ImeEngine" vs normative Section 4.4 "per-session" | History-guardian veto accepted unanimously. Same reasoning. The v0.7 changelog (Doc 06 line 1243) explicitly records the per-session transition. |
