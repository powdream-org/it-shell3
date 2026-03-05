# Verification Round 2 Results

**Date**: 2026-03-05
**Reviewer**: verification team (round 2, fresh agent with no prior context)
**Scope**: All 6 protocol v0.7 documents cross-checked against each other and against v0.7 design resolutions
**Verdict**: 1 issue found (MEDIUM severity). Round 1 fix confirmed applied. 1 new cross-doc inconsistency discovered.

---

## Round 1 Fix Verification

### Checklist Item 13: Round 1 fix confirmed

**PASS.** Doc 03 line 868 now reads:

> **Always-sent**: No subscription required. Follows the same always-sent convention as 0x0180-0x0185. See the introductory note in Section 4.

The fix has been correctly applied. The range now includes ClientHealthChanged (0x0185).

### Checklist Item 14: All notification range references

**PASS.** All occurrences of `0x0180-0x018x` ranges in normative text across docs 01-06 use `0x0185` as the upper bound. The remaining `0x0180-0x0184` occurrences are exclusively in:
- Review note files (quoting old text)
- Historical v0.6 changelog entries (correctly describing pre-ClientHealthChanged state)

---

## Full Checklist Results

### 1. Message type registry (doc 01) completeness

**PASS.** Doc 01 Section 4.2 lists every message type defined in docs 02-06. All ranges verified:

- Handshake (0x0001-0x0005, 0x00FF): present
- Session/Pane (0x0100-0x0153, 0x0180-0x0185, 0x0190-0x0191): present, including ClientHealthChanged
- Input (0x0200-0x0206): present
- Render State (0x0300-0x0305): present
- CJK/IME (0x0400-0x0406, 0x04FF): present
- Flow Control (0x0500-0x0506): present
- Clipboard (0x0600-0x0604): present
- Persistence (0x0700-0x0707): present
- Notifications (0x0800-0x0806, 0x0810-0x0813): present
- Extensions (0x0A00-0x0A02): present

### 2. ClientHealthChanged (0x0185) consistency

**PASS.** Verified in: doc 01 Section 4.2 registry, doc 01 Section 13.2 overview, doc 03 message type table, doc 03 Section 4.6 full spec, doc 03 Section 4 intro note (0x0180-0x0185), doc 03 Section 7 (0x0180-0x0185), doc 03 Section 9 readonly receives, doc 06 Section 2.6 escalation timeline, doc 06 Section 6 default subscriptions.

### 3. Field name consistency

**PASS (with caveat -- see Issue 1).** Key fields verified across documents:

- `health` / `previous_health`: consistent (doc 01 Section 13.2, doc 03 Section 4.6)
- `excluded_from_resize`: consistent (doc 01, doc 03)
- `active_input_method` / `active_keyboard_layout`: consistent (doc 03 Section 3, doc 03 Section 1.6, doc 05)
- `pane_input_methods`: present in doc 03 AttachSessionResponse and AttachOrCreateResponse
- `resize_policy`: present in doc 03 Section 1.6 AttachSessionResponse; **absent** from doc 02 Section 9.2 and doc 03 Section 1.14 (see Issue 1)

### 4. Health state terminology

**PASS.** Only `"healthy"` and `"stale"` appear as protocol-visible health state values across all six documents. No spurious `"degraded"` or `"paused"` health states found in normative text.

### 5. Resize policy terminology

**PASS.** `"latest"` and `"smallest"` are used consistently in doc 01 Section 13.1, doc 03 Sections 1.6, 5.1, and 8. `latest` is consistently documented as the default.

**Caveat**: Doc 02 does not reference the dual-policy model at all (see Issue 1).

### 6. Disconnect reason `"stale_client"`

**PASS.** Consistent across doc 02 Section 11.1 (reason enum), doc 01 Section 13.2 (escalation timeline), doc 06 Section 2.6 (escalation timeline), doc 06 Section 2.7 (eviction sequence), doc 06 Section 10 (timeout table).

### 7. PreeditEnd reason `"client_evicted"`

**PASS.** Consistent across doc 05 Section 2.3 (reason enum with description), doc 06 Section 2.6 (escalation timeline reference), doc 06 Section 2.7 (eviction sequence with cross-reference to doc 05 Section 2.3).

### 8. Cross-references

**PASS.** All cross-references verified:

- Doc 01 Section 13.1 -> doc 03 Section 1.6: correct (AttachSessionResponse has `resize_policy`)
- Doc 01 Section 13.2 -> doc 03 Section 4: correct (ClientHealthChanged spec)
- Doc 01 Section 13.2 -> doc 06 Section 2: correct (smooth degradation)
- Doc 01 Section 13.2 -> doc 06 Section 2.3: correct (FlowControlConfig timeout fields)
- Doc 03 Section 4.6 -> doc 06 Section 2: correct (PausePane escalation at Section 2.6)
- Doc 03 Section 5.1 -> doc 06: correct (Idle suppression at Section 1.7)
- Doc 03 Section 8 -> doc 06 Section 4.4: correct (RestoreSessionResponse)
- Doc 06 Section 2.7 -> doc 05 Section 2.3: correct (PreeditEnd reason `"client_evicted"`)

### 9. Timeout values

**PASS.** Consistent across all documents:

| Timeout | Doc 01 S13.2 | Doc 03 S4.6 | Doc 06 S2.3 | Doc 06 S2.6 | Doc 06 S10 |
|---------|-------------|-------------|-------------|-------------|------------|
| Resize exclusion | 5s | 5s grace | 5000 ms | 5s | 5s |
| Stale (local) | 60s | -- | 60000 ms | 60s | 60s |
| Stale (SSH) | 120s | -- | 120000 ms | 120s | 120s |
| Eviction | 300s | -- | 300000 ms | 300s | 300s |
| Heartbeat timeout | 90s | -- | -- | -- | 90s |
| Handshake timeouts | 5s/5s/60s | -- | -- | -- | -- |

Doc 01 Section 12.3 and doc 02 Section 12.3 also match: Transport=5s, ClientHello=5s, READY->Attach=60s, Heartbeat=90s.

### 10. Version headers

**PASS.** All 6 documents have v0.7:

- Doc 01: `**Status**: Draft v0.7`
- Doc 02: `**Status**: Draft v0.7`
- Doc 03: `**Version**: v0.7`
- Doc 04: `**Status**: Draft v0.7`
- Doc 05: `**Status**: Draft v0.7`
- Doc 06: `**Version**: v0.7`

### 11. Changelog entries

**PASS.** All changelog entries verified against actual document content. Doc 01 (ClientHealthChanged registry + Section 13), doc 02 (`"stale_client"`), doc 03 (ClientHealthChanged Section 4.6, resize policy, Section 5.1 rewrite, etc.), doc 04 (no substantive changes), doc 05 (`"client_evicted"`, residual empty->null), doc 06 (FlowControlConfig timeouts, escalation timeline, Idle suppression, preedit eviction, default subscriptions). All present and accurate.

### 12. Deferred items not accidentally applied

**PASS.**

- Issue 13 (buffer limit 1 MB -> 512 KB): Doc 06 Server Output Queue Management table correctly still says "1 MB". Changelog explicitly notes deferral.
- Issue 15 (discard-and-resync): Not present in doc 06. Correctly deferred.
- Issue 14 (discard-and-resync part): Not present. Correctly deferred.

---

## Issues Found

| # | Severity | Doc | Section | Description | Review note |
|---|----------|-----|---------|-------------|-------------|
| 1 | MEDIUM | Doc 02 | 9.6, 9.9, 9.2 | Multi-client resize description uses only `min()` semantics without acknowledging the dual-policy model (`latest` default / `smallest` opt-in) added in v0.7. AttachSessionResponse payload also missing `resize_policy` field. | `03-doc02-resize-policy-inconsistency.md` |

---

## Additional Observations (not issues)

1. **AttachOrCreateResponse missing `resize_policy`**: Doc 03 Section 1.14 (`AttachOrCreateResponse`) does not include a `resize_policy` field, while `AttachSessionResponse` (Section 1.6) does. Since Section 1.14 states "the same post-attach sequence applies as for AttachSessionResponse," the field should arguably be present here too. However, since doc 03 Section 1.6 is the authoritative attach response spec and `resize_policy` is informational, this is a cosmetic gap rather than a protocol error. Flagged for consideration but not filed as a separate issue.

2. **Doc 02 Section 9.9 resize algorithm vs doc 03 Section 5.1**: Doc 03 Section 5.1 is clearly the authoritative source with the full dual-policy algorithm, debounce, stale exclusion, and re-inclusion hysteresis. Doc 02 Section 9.9 predates these additions. The fix could be either (a) updating doc 02 to match doc 03, or (b) replacing doc 02 Section 9.9 with a cross-reference to doc 03 Section 5.1.

3. **Round 1 observations still apply**: Formatting variation between docs (Status vs Version headers) and changelog location variation (header vs dedicated section) remain as cosmetic differences.
