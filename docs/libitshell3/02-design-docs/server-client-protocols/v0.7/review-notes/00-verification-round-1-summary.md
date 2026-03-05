# Verification Round 1 Summary

**Date**: 2026-03-05
**Reviewer**: verification team (round 1, fresh agent with no prior context)
**Scope**: All 6 protocol v0.7 documents cross-checked against each other and against the v0.6 design resolutions and review notes
**Verdict**: 1 issue found (LOW severity). All checklist items pass except one minor residual reference.

---

## Checklist Results

### 1. Message type registry (doc 01) completeness

**PASS.** Doc 01 Section 4.2 lists every message type defined in docs 02-06. Verified all ranges:

- Handshake (0x0001-0x0005, 0x00FF): all present
- Session/Pane (0x0100-0x0153, 0x0180-0x0185, 0x0190-0x0191): all present, including ClientHealthChanged at 0x0185
- Input (0x0200-0x0206): all present
- Render State (0x0300-0x0305): all present
- CJK/IME (0x0400-0x0406, 0x04FF): all present
- Flow Control (0x0500-0x0506): all present
- Clipboard (0x0600-0x0604): all present
- Persistence (0x0700-0x0707): all present
- Notifications (0x0800-0x0806, 0x0810-0x0813): all present
- Extensions (0x0A00-0x0A02): all present

No missing entries. No stale entries.

### 2. ClientHealthChanged (0x0185) consistency

**PASS.** Verified across all documents:

- Doc 01 Section 4.2: registry entry present (S->C, JSON)
- Doc 01 Section 13.2: referenced with correct field list
- Doc 03 message type table: present (0x0185, S->C)
- Doc 03 Section 4.6: full specification with JSON payload, field table, reason values
- Doc 03 Section 4 intro: included in always-sent range (0x0180-0x0185)
- Doc 03 Section 7: notification range updated to 0x0180-0x0185
- Doc 03 Section 9: listed in readonly receives
- Doc 06 Section 2.6: referenced in PausePane escalation timeline
- Doc 06 Section 6 (default subscriptions): listed as always-sent

### 3. Field name consistency

**PASS.** Key fields verified:

- `resize_policy`: consistent in doc 01 Section 13.1, doc 03 Section 1.6 (AttachSessionResponse), doc 03 Section 5.1, doc 03 Section 8
- `health` / `previous_health`: consistent in doc 01 Section 13.2, doc 03 Section 4.6
- `excluded_from_resize`: consistent in doc 01, doc 03
- `active_input_method` / `active_keyboard_layout`: consistent across doc 03 Section 3 (layout tree), doc 03 Section 1.6 (AttachSessionResponse), doc 05 (PreeditSync, InputMethodAck)
- `pane_input_methods`: present in doc 03 AttachSessionResponse and AttachOrCreateResponse

### 4. Health state terminology

**PASS.** Only `"healthy"` and `"stale"` appear as health state values. No instances of `"degraded"` or `"paused_as_health_state"` found in any normative text. The word "degraded" appears once in doc 05 as an English adjective ("must never be degraded") unrelated to health states.

### 5. Resize policy terminology

**PASS.** `"latest"` and `"smallest"` are used consistently everywhere. `latest` is consistently documented as the default.

### 6. Disconnect reason `"stale_client"`

**PASS.** Doc 02 Section 11.1 includes `"stale_client"` in the Disconnect reason enum. Doc 06 Section 2.6 describes eviction at T=300s with `Disconnect { reason: "stale_client" }`. Doc 06 Section 2.7 confirms the same. All consistent.

### 7. PreeditEnd reason `"client_evicted"`

**PASS.** Doc 05 Section 2.3 defines `"client_evicted"` in the PreeditEnd reason enum with description matching doc 06 Section 2.7 eviction flow. Doc 06 Section 2.7 references "doc 05 Section 2.3" correctly. Doc 05 changelog entry confirms this was added in v0.7.

### 8. Cross-references

**PASS.** All cross-references verified:

- Doc 01 Section 13.1 -> doc 03 Section 1.6 (AttachSessionResponse): exists, contains `resize_policy`
- Doc 01 Section 13.2 -> doc 03 Section 4 (ClientHealthChanged): exists, full spec
- Doc 01 Section 13.2 -> doc 06 Section 2 (smooth degradation): exists
- Doc 01 Section 13.2 -> doc 06 Section 2.3 (FlowControlConfig): exists, contains timeout fields
- Doc 03 Section 4.6 -> doc 06 Section 2 (PausePane escalation): exists as Section 2.6
- Doc 03 Section 5.1 -> doc 06 (Idle suppression during resize debounce): exists as Section 1.7
- Doc 03 Section 8 -> doc 06 Section 4.4 (RestoreSessionResponse): exists
- Doc 06 Section 2.7 -> doc 05 Section 2.3 (PreeditEnd reason): exists, contains `"client_evicted"`

### 9. Timeout values

**PASS.** Consistent across all documents:

| Timeout | Doc 01 Section 13.2 | Doc 03 Section 4.6 | Doc 06 Section 2.3 | Doc 06 Section 2.6 |
|---------|--------------------|--------------------|--------------------|--------------------|
| Resize exclusion | 5s | 5s grace | 5000 ms | 5s |
| Stale (local) | 60s | 60s | 60000 ms | 60s |
| Stale (SSH) | 120s | -- | 120000 ms | 120s |
| Eviction | 300s | -- | 300000 ms | 300s |

Doc 06 Section 10 timeout table also matches: "5s / 60s (local) or 120s (SSH) / 300s".

### 10. Version headers

**PASS.** All 6 docs have v0.7 version:

- Doc 01: `**Status**: Draft v0.7`
- Doc 02: `**Status**: Draft v0.7`
- Doc 03: `**Version**: v0.7`
- Doc 04: `**Status**: Draft v0.7`
- Doc 05: `**Status**: Draft v0.7`
- Doc 06: `**Version**: v0.7`

### 11. Changelog entries

**PASS.** Verified changelog entries match actual document content:

- Doc 01: ClientHealthChanged registry entry added; Section 13 (resize policy / health model) added. Both present.
- Doc 02: `"stale_client"` added to Disconnect reason. Present in Section 11.1.
- Doc 03: ClientHealthChanged Section 4.6 added; Section 4 range updated; AttachSessionResponse `resize_policy` added; Section 5.1 rewritten; viewport clipping added; Section 7 range updated; Section 8 Window Size updated; Section 9 readonly receives updated. All present.
- Doc 04: No substantive changes (version bump only). Confirmed -- no new content.
- Doc 05: `"client_evicted"` added to PreeditEnd reasons; residual `empty` replaced with `null`. Both present.
- Doc 06: FlowControlConfig timeout fields added; PausePane escalation timeline (Section 2.6) added; timeout table updated; heartbeat orthogonality note added; Idle suppression (Section 1.7) added; preedit commit on eviction (Section 2.7) added; ClientHealthChanged in default subscriptions added. All present. Deferred items (Issues 13, 15) noted.

### 12. Deferred items not accidentally applied

**PASS.**

- Issue 13 (buffer limit reduction from 1 MB to 512 KB): Doc 06 Server Output Queue Management table still says "Max size per pane per client: 1 MB". Correctly not changed. Changelog explicitly notes deferral.
- Issue 15 (discard-and-resync procedure): Not present in doc 06. Correctly deferred. Changelog notes deferral.
- Issue 14 (discard-and-resync part of escalation): Not present. Correctly deferred.

---

## Issues Found

| # | Severity | Doc | Description | Review note |
|---|----------|-----|-------------|-------------|
| 1 | LOW | Doc 03 | Residual `0x0180-0x0184` in Section 4.6 ClientHealthChanged "Always-sent" note; should be `0x0180-0x0185` | `01-residual-notification-range-reference.md` |

---

## Additional Observations (not issues)

1. **Doc formatting variation**: Docs 01, 02, 04, 05 use `**Status**: Draft v0.7` as a combined header line; docs 03, 06 use separate `**Version**: v0.7` and `**Status**: Draft` lines. Not a content issue.

2. **Changelog location variation**: Docs 01, 02, 03, 06 have formal `## Changelog` sections at the end. Docs 04, 05 use `**Changes from v0.6**:` in the header metadata area instead of a separate changelog section. The information is equivalent; the format differs.

3. **Reserved range granularity**: Doc 01 Section 4.1 shows `0x0B00-0x0FFF` as a single "Reserved for future" block. Doc 06 Section 9 breaks this into speculative sub-ranges (File transfer, Plugin, Audio, Accessibility, Diagnostics). These are advisory/aspirational allocations, not a conflict -- doc 01 is the master allocation and doc 06's breakdown is non-normative.
