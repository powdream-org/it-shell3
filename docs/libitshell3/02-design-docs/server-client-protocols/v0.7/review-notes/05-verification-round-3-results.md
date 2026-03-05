# Verification Round 3 Results

**Date**: 2026-03-05
**Verifier**: systems-engineer (fresh context, no prior round participation)
**Scope**: All six protocol documents (docs 01-06, v0.7)

---

## Prior Fix Verification

### Round 1 fix: Doc 03 line 868 `0x0180-0x0184` -> `0x0180-0x0185`

**PASS.** Line 868 now reads:

> **Always-sent**: No subscription required. Follows the same always-sent convention as 0x0180-0x0185. See the introductory note in Section 4.

Consistent with Section 4 introductory note (line 738) and Section 7 (line 1005).

### Round 2 fix: Doc 02 Sections 9.2, 9.6, 9.9 resize policy

**PASS.** All three sections correctly updated:

- **Section 9.2** (line 697): `resize_policy` present in JSON example and field table (line 711).
- **Section 9.6** (line 836): References dual-policy model with `latest`/`smallest` and cross-references doc 03 Section 5.1.
- **Section 9.9** (line 862): Algorithm replaced with summary and cross-reference to doc 03 Section 5.1. No duplicated algorithm text.

---

## Full Checklist Verification

### 1. Message type registry (doc 01) complete

**PASS.** All message types across docs 01-06 are present in the doc 01 Section 4.2 registry:

- Handshake (0x0001-0x0005, 0x00FF): present
- Session/Pane (0x0100-0x0153, 0x0180-0x0185, 0x0190-0x0191): present, including ClientHealthChanged at 0x0185
- Input (0x0200-0x0206): present
- Render State (0x0300-0x0305): present
- CJK/IME (0x0400-0x0406, 0x04FF): present
- Flow Control (0x0500-0x0506): present
- Clipboard (0x0600-0x0604): present
- Persistence (0x0700-0x0707): present
- Notifications (0x0800-0x0806, 0x0810-0x0813): present
- Extensions (0x0A00-0x0A02): present

### 2. 0x0185 ClientHealthChanged consistent everywhere

**PASS.** Verified in: doc 01 Section 4.2 registry, doc 01 Section 13.2 overview, doc 03 message type table, doc 03 Section 4.6 full spec, doc 03 Section 4 intro note, doc 03 Section 7, doc 03 Section 9 readonly receives, doc 06 Section 2.6 escalation timeline, doc 06 Section 6 default subscriptions.

### 3. Field names consistent

**PASS** (with one issue). Fields checked across all documents:

- `session_id`, `client_id`, `client_name`: consistent
- `health`, `previous_health`: consistent (doc 01 Section 13.2, doc 03 Section 4.6)
- `excluded_from_resize`: consistent (doc 01 Section 13.2, doc 03 Section 4.6)
- `resize_policy`: present in doc 01 Section 13.1, doc 02 Section 9.2, doc 03 Section 1.6, doc 03 Section 5.1, doc 03 Section 8. **Missing from doc 03 Section 1.14 (AttachOrCreateResponse)** -- see Issue 1 below.
- `active_input_method`, `active_keyboard_layout`: consistent (doc 03 Sections 1.6, 1.14, 3; doc 05)
- `preedit_session_id`: consistent (doc 05 Sections 2.1-2.4)
- `display_width`: present in doc 04 Section 4.2 as documented in changelog

### 4. Health states `"healthy"`/`"stale"` uniform

**PASS.** Only `"healthy"` and `"stale"` appear as protocol-visible health state values. No spurious `"degraded"` or `"paused"` health states in normative text.

### 5. Resize policy `"latest"`/`"smallest"` consistent, `latest` default

**PASS.** `"latest"` consistently documented as default across doc 01 Section 13.1, doc 02 Sections 9.2/9.6/9.9, doc 03 Sections 1.6/5.1/8.

### 6. Disconnect reason `"stale_client"` consistent

**PASS.** Present in: doc 02 Section 11.1 enum, doc 01 Section 13.2 timeline, doc 06 Section 2.6 timeline, doc 06 Section 2.7 eviction sequence, doc 06 Section 10 timeout table.

### 7. PreeditEnd reason `"client_evicted"` consistent

**PASS.** Present in: doc 05 Section 2.3 reason enum (with full description), doc 06 Section 2.7 eviction sequence (with cross-reference to doc 05 Section 2.3), doc 06 Section 2.6 timeline.

### 8. Cross-references correct

**PASS.** All verified cross-references resolve to existing sections with expected content:

- Doc 01 Section 13.1 -> doc 03 Section 1.6 (AttachSessionResponse, has `resize_policy`)
- Doc 01 Section 13.2 -> doc 03 Section 4 (ClientHealthChanged full spec)
- Doc 02 Section 9.2 -> doc 03 Section 5.1 (resize algorithm)
- Doc 02 Section 9.6 -> doc 03 Section 5.1 (resize algorithm)
- Doc 02 Section 9.6 -> doc 05 Section 6.3 (preedit ownership rules)
- Doc 02 Section 9.9 -> doc 03 Section 5.1 (resize algorithm)
- Doc 04 Section 2.8 -> doc 03 Section 9 (readonly permissions)
- Doc 05 Section 1 -> doc 03 Section 9 (readonly permissions)
- Doc 06 Section 1.6 -> doc 03 Section 5.1 (resize debounce interaction)
- Doc 06 Section 2.7 -> doc 05 Section 2.3 (PreeditEnd `"client_evicted"`)

### 9. Timeout values 5s/60s/120s/300s consistent

**PASS.** Verified across all documents:

| Timeout | Doc 01 | Doc 02 | Doc 03 | Doc 06 |
|---------|--------|--------|--------|--------|
| Resize exclusion | 5s | -- | 5s (Section 5.1) | 5s / 5000ms |
| Stale (local) | 60s | -- | 60s (Section 4.6) | 60s / 60000ms |
| Stale (SSH) | 120s | -- | -- | 120s / 120000ms |
| Eviction | 300s | 300s (Section 11.1) | -- | 300s / 300000ms |
| Handshake | -- | 5s/5s/60s (Section 12.3) | -- | -- |
| Heartbeat | 90s (Section 5.4) | -- | -- | 90s (Section 7) |

### 10. Version headers all v0.7

**PASS.** All six documents have v0.7 version headers:

- Doc 01: `**Status**: Draft v0.7`
- Doc 02: `**Status**: Draft v0.7`
- Doc 03: `**Version**: v0.7` + `**Status**: Draft`
- Doc 04: `**Status**: Draft v0.7`
- Doc 05: `**Status**: Draft v0.7`
- Doc 06: `**Version**: v0.7` + `**Status**: Draft`

(Docs 03/06 use a different header format but carry the same version.)

### 11. Changelogs accurate

**PASS.** All v0.7 changelog entries verified against actual document content. Each claimed change is present in the document.

### 12. Deferred items not applied (buffer limit 1MB in doc 06)

**PASS.** Doc 06 Section 2 output queue table (line 312) still shows "1 MB" as the per-pane per-client buffer limit. The deferred item (Issue 13, reduce to 512 KB) is explicitly noted in the v0.7 changelog (line 1170) as deferred to Phase 3.

### 13. Doc 02 Section 9.2 has `resize_policy` field

**PASS.** Present in both JSON example (line 697) and field table (line 711).

### 14. Doc 02 Section 9.9 references doc 03 Section 5.1 (not duplicated algorithm)

**PASS.** Section 9.9 (line 862) contains a one-paragraph summary with cross-reference, not a duplicated algorithm.

### 15. Doc 03 `0x0180-0x0185` range correct everywhere

**PASS.** All normative text uses `0x0180-0x0185`. The only `0x0180-0x0184` occurrences are in historical changelog entries (v0.6, line 1114) describing pre-ClientHealthChanged state, which is correct.

---

## New Issues Found

| # | Severity | Doc | Location | Issue | Review note |
|---|----------|-----|----------|-------|-------------|
| 1 | MEDIUM | Doc 03 | Section 1.14 (lines 351-372) | `AttachOrCreateResponse` missing `resize_policy` field. Present in `AttachSessionResponse` (Section 1.6) but not in the parallel `AttachOrCreate` response. | `04-attach-or-create-response-missing-resize-policy.md` |

---

## Verdict

**Not clean.** One MEDIUM issue found. All prior fixes verified. Recommend applying the fix and running a targeted Round 4 verification on `AttachOrCreateResponse` only.
