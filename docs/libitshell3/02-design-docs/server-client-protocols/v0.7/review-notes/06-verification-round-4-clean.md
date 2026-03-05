# Verification Round 4 (Final) -- CLEAN

**Date**: 2026-03-05
**Verifier**: Protocol Architect (fresh context, no prior round participation)
**Scope**: All six v0.7 protocol documents (01-06), cross-document consistency
**Prior round fixes verified**: R1 (0x0184->0x0185), R2 (dual-policy resize + resize_policy in AttachSessionResponse), R3 (resize_policy in AttachOrCreateResponse)

---

## Checklist Results

### 1. Message type registry complete

**PASS.** Doc 01 Section 4.2 is the exhaustive registry. All message types cross-checked against their owning documents:

- Handshake (0x0001-0x0005, 0x00FF): matches doc 02
- Session/Pane (0x0100-0x0153, 0x0180-0x0185, 0x0190-0x0191): matches doc 03, including ClientHealthChanged at 0x0185
- Input (0x0200-0x0206): matches doc 04
- RenderState (0x0300-0x0305): matches doc 04
- CJK/IME (0x0400-0x0406, 0x04FF): matches doc 05
- Flow Control (0x0500-0x0506): matches doc 06
- Clipboard (0x0600-0x0604): matches doc 06
- Persistence (0x0700-0x0707): matches doc 06
- Notifications (0x0800-0x0806, 0x0810-0x0813): matches doc 06
- Extensions (0x0A00-0x0A02): matches doc 06

No missing entries or mismatches found.

### 2. 0x0185 consistent everywhere

**PASS.** All normative text uses `0x0180-0x0185` as the notification range upper bound:

- Doc 01 Section 4.2 registry: 0x0185 present
- Doc 01 Section 13.2: 0x0185 referenced
- Doc 03 message type table: 0x0185 present
- Doc 03 Section 4 introductory note: `0x0180-0x0185`
- Doc 03 Section 4.6: ClientHealthChanged at 0x0185, "always-sent convention as 0x0180-0x0185"
- Doc 03 Section 7: `0x0180-0x0185`
- Doc 03 Section 9 readonly receives: ClientHealthChanged listed
- Doc 06 Section 2.6: 0x0185 referenced
- Doc 06 Section 6 default subscriptions: `ClientHealthChanged (0x0185, doc 03, always sent)`

Remaining `0x0180-0x0184` occurrences are exclusively in historical changelog entries (v0.6) describing pre-ClientHealthChanged state -- correct in context.

### 3. Field names consistent -- `resize_policy` in all response messages

**PASS.** `resize_policy` field verified in all three locations:

- Doc 02 Section 9.2 AttachSessionResponse: JSON example line 697, field table line 711. Cross-refs doc 03 Section 5.1.
- Doc 03 Section 1.6 AttachSessionResponse: JSON example line 210, field table line 224. Cross-refs Section 5.1.
- Doc 03 Section 1.14 AttachOrCreateResponse: JSON example line 358, field table line 372. Cross-refs Section 5.1.

Field description consistent across all three: `Server's active resize policy: "latest" or "smallest". Informational -- not negotiated.`

### 4. Health states uniform

**PASS.** Only `"healthy"` and `"stale"` appear as protocol-visible health state values across all six documents:

- Doc 01 Section 13.2: two-row table (`healthy`, `stale`)
- Doc 03 Section 4.6: health state model table (`healthy`, `stale`)
- Doc 06 Section 2.6: escalation timeline references `stale`

`"paused"` is consistently described as an orthogonal flow-control state, NOT a health state (doc 01 line 1007, doc 03 line 879). `"degraded"` appears only as an English adjective in doc 05, not as a health state value. No spurious health state values found.

### 5. Resize policy consistent

**PASS.** Dual-policy model (`latest` default, `smallest` opt-in) is consistently described:

- Doc 01 Section 13.1: two-policy table with stale exclusion
- Doc 02 Section 9.6: references dual-policy with cross-ref to doc 03 Section 5.1
- Doc 02 Section 9.9: summary with cross-ref to doc 03 Section 5.1
- Doc 03 Section 5.1: full normative algorithm
- Doc 03 Section 8 (Window Size): references dual-policy model

No stale hardcoded `min()` references remain outside the `smallest` policy context.

### 6. Disconnect reason consistent

**PASS.** Canonical enum in doc 02 Section 11.1:
`"normal"`, `"error"`, `"timeout"`, `"version_mismatch"`, `"auth_failed"`, `"server_shutdown"`, `"replaced"`, `"stale_client"`

All disconnect reason usages across docs match:
- Doc 01 line 1023: `reason "stale_client"` -- matches
- Doc 06 line 258, 382, 430: `reason "stale_client"` -- matches
- Doc 06 line 1113: `reason "error"` -- matches (was `"protocol_error"` in earlier version, fixed)

### 7. PreeditEnd reason consistent

**PASS.** Canonical enum in doc 05 Section 2.3:
`"committed"`, `"cancelled"`, `"pane_closed"`, `"client_disconnected"`, `"replaced_by_other_client"`, `"focus_changed"`, `"input_method_changed"`, `"client_evicted"`

All PreeditEnd reason usages match:
- Doc 02 Section 9.6: `"replaced_by_other_client"` -- matches
- Doc 03 Section 2.7: `"focus_changed"` -- matches
- Doc 06 Section 2.6-2.7: `"client_evicted"` -- matches
- Doc 05 internal usage (Sections 6, 7, 8, 9, 11): all reason values found in the enum

### 8. Cross-references correct

**PASS.** Verified key cross-references:

- Doc 01 -> doc 03 Section 1.6 (AttachSessionResponse, resize_policy): correct
- Doc 01 -> doc 03 Section 4 (ClientHealthChanged): correct
- Doc 01 -> doc 06 Section 2.3 (FlowControlConfig): correct
- Doc 01 -> doc 06 Section 2 (smooth degradation): correct
- Doc 02 -> doc 03 Section 5.1 (resize algorithm): correct
- Doc 02 -> doc 03 Section 9 (readonly permissions): correct
- Doc 02 -> doc 05 Section 6.3 (preedit exclusivity): correct
- Doc 03 -> doc 05 Section 7.7 (focus change race): correct
- Doc 03 -> doc 06 Section 2 (PausePane escalation): correct
- Doc 03 -> doc 06 Section 4.4 (RestoreSessionResponse IME init): correct
- Doc 04 -> doc 03 Section 9 (readonly permissions table): correct
- Doc 05 -> doc 04 Section 2.8 (ERR_ACCESS_DENIED for readonly): correct
- Doc 06 -> doc 05 Section 2.3 (PreeditEnd reason definition): correct

### 9. Timeouts consistent

**PASS.** Timeout values verified across doc 01, 02, and 06:

| Timeout | Doc 01 | Doc 02 | Doc 06 |
|---------|--------|--------|--------|
| Transport connect | 5s | 5s | -- |
| ClientHello->ServerHello | 5s | 5s | -- |
| READY->Attach/Create | 60s | 60s | -- |
| Heartbeat response | 90s | 90s | 90s |
| Heartbeat interval | 30s | -- | -- |
| Resize exclusion | 5s | -- | 5s |
| Stale (local) | 60s | -- | 60s |
| Stale (SSH) | 120s | -- | 120s |
| Eviction | 300s | 300s (changelog) | 300s |
| Re-inclusion hysteresis | 5s | 5s | -- |

### 10. Version headers v0.7

**PASS.** All six documents have v0.7 in their status headers:

- Doc 01: `**Status**: Draft v0.7` (line 3)
- Doc 02: `**Status**: Draft v0.7` (line 3)
- Doc 03: `**Version**: v0.7` (line 3)
- Doc 04: `**Status**: Draft v0.7` (line 3)
- Doc 05: `**Status**: Draft v0.7` (line 3)
- Doc 06: `**Version**: v0.7` (line 3)

All dates are 2026-03-05.

### 11. Changelogs accurate

**PASS.** Verified changelog entries in each document:

- Doc 01: v0.7 changelog (line 1039) documents ClientHealthChanged registry entry and resize/health model overview. Accurate.
- Doc 02: v0.7 changelog (line 1011) documents `"stale_client"` disconnect reason and resize algorithm update. Accurate.
- Doc 03: v0.7 changelog (line 1103) documents ClientHealthChanged, resize_policy, Section 4 range update, Section 5.1 rewrite, Section 7 range update, Section 8 Window Size update. Accurate.
- Doc 04: v0.7 change notes (line 8) document version bump with no substantive changes, I-frame/P-frame deferred. Accurate.
- Doc 05: v0.7 change notes (line 8) document `"client_evicted"` PreeditEnd reason and residual `empty` -> `null` fix. Accurate.
- Doc 06: v0.7 changelog (line 1151) documents ClientHealthChanged references, heartbeat orthogonality, disconnect reason alignment, buffer limit deferral. Accurate.

### 12. Deferred items not applied (buffer 1MB)

**PASS.** Doc 06 Section 2 output queue table (line 312) retains "1 MB" as the per-pane per-client buffer limit. The v0.7 changelog (line 1170) explicitly notes the deferral: "Per-(client, pane) buffer limit reduction from 1 MB to 512 KB -- deferred pending the I-frame/P-frame design discussion (Phase 3, Issues 22-24)."

---

## Prior Round Fix Verification

### R1: Doc 03 notification range 0x0184 -> 0x0185

**CONFIRMED FIXED.** Doc 03 Section 4.6 ClientHealthChanged "Always-sent" note (line 870) now reads `0x0180-0x0185`. Verified by grep: no normative text contains `0x0180-0x0184`.

### R2: Doc 02 stale min() resize -> dual-policy cross-ref + resize_policy in AttachSessionResponse

**CONFIRMED FIXED.** Doc 02 Sections 9.6 and 9.9 reference the dual-policy model with cross-ref to doc 03 Section 5.1. Doc 02 Section 9.2 AttachSessionResponse includes `resize_policy` in JSON example and field table.

### R3: Doc 03 AttachOrCreateResponse missing resize_policy -> added

**CONFIRMED FIXED.** Doc 03 Section 1.14 AttachOrCreateResponse (lines 351-374) includes `"resize_policy": "latest"` in JSON example and `resize_policy` row in field table.

---

## Conclusion

**All 12 checklist items PASS. All 3 prior round fixes confirmed. No new issues found.**

The v0.7 protocol documents are cross-document consistent and ready for the next phase.
