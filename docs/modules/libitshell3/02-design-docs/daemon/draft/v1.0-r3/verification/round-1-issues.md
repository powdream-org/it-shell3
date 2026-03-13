# Verification Round 1 Issues

**Date**: 2026-03-10
**Team**: history-guardian (opus), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Scope**: daemon v0.3, protocol v0.11, IME v0.8, AGENTS.md
**Result**: 9 confirmed issues, 2 dismissed

## Confirmed Issues

### V1-01 [HIGH] Headless API violation in daemon doc 02

**Location**: daemon/draft/v1.0-r3/02-integration-boundaries.md §§4.2, 4.3, 4.4, 4.9
**Confirmed by**: All 4 verifiers (unanimous)
**Description**: Multiple sections use `ghostty_surface_key()` and `ghostty_surface_preedit(null, 0)` as implementation calls, contradicting the headless architecture established in daemon doc 01 §§4.3, 4.4, 4.6. The daemon has no Surface and cannot call these APIs.
**Fix**: Replace `ghostty_surface_key()` with `key_encode.encode()` + `write(pty_fd, text)`. Replace `ghostty_surface_preedit(null, 0)` with `session.current_preedit = null` + dirty marking. Update responsibility matrix in §4.9 accordingly.

### V1-02 [HIGH] Headless API violation in daemon doc 04 §5.3

**Location**: daemon/draft/v1.0-r3/04-runtime-policies.md §5.3
**Confirmed by**: 3 verifiers (HG, TV, SV confirm; CRV partial — says conceptual)
**Description**: §5.3 step 2 says "the daemon calls `ghostty_surface_preedit()` to inject preedit cells." Should use `overlayPreedit()` consistent with daemon doc 01 §4.4.
**Fix**: Replace with `overlayPreedit()` reference.

### V1-03 [HIGH] Wrong message type IDs in daemon doc 04 §4.3

**Location**: daemon/draft/v1.0-r3/04-runtime-policies.md §4.3
**Confirmed by**: TV, CRV (double-confirmed); SV, HG also confirm
**Description**: Doc 04 §4.3 says `FlowControlConfig (0x0506)` and `FlowControlConfigAck (0x0507)`. Protocol docs define `FlowControlConfig = 0x0502` and `FlowControlConfigAck = 0x0503`. IDs are wrong by 4 slots.
**Fix**: Change to `FlowControlConfig (0x0502)` and `FlowControlConfigAck (0x0503)`.

### V1-04 [HIGH] AGENTS.md hierarchy stale

**Location**: AGENTS.md line 51
**Confirmed by**: All 4 verifiers (unanimous)
**Description**: Says "Session hierarchy: Session > Tab > Pane (binary split tree, JSON-serializable)". All current design docs establish no Tab entity — hierarchy is Session > Pane.
**Fix**: Change to "Session hierarchy: Session > Pane (binary split tree, JSON-serializable)".

### V1-05 [MEDIUM] Stale normative IME contract version references

**Location**: daemon/draft/v1.0-r3/01-internal-architecture.md (lines 424, 476, 763) and daemon/draft/v1.0-r3/02-integration-boundaries.md (line 370)
**Confirmed by**: HG (partial — normative refs only), TV, CRV confirm normative
**Description**: 4 normative cross-references say "IME contract v0.7" but should reference v0.8 (current). Historical/explanatory references to v0.7 (e.g., doc 01 lines 622-623 describing pre-headless decisions) should remain as v0.7.
**Fix**: Update 4 normative references from "v0.7" to "v0.8". Keep historical references unchanged.

### V1-06 [MEDIUM] RLIMIT_NOFILE residual in protocol doc 01

**Location**: protocol/v0.11/01-protocol-overview.md §5.5.4
**Confirmed by**: HG, SV, CRV confirm (3-1; TV dismisses as out of scope for P3)
**Description**: §5.5.4 still contains RLIMIT_NOFILE implementation note with "256" and "SHOULD" language. Same content correctly exists in daemon doc 04 §1. Cross-team request P3 targeted removal of this content.
**Fix**: Remove the RLIMIT_NOFILE implementation note from §5.5.4; replace with brief daemon docs reference.

### V1-07 [LOW] ERR_RESOURCE_EXHAUSTED lifecycle ambiguity

**Location**: daemon/draft/v1.0-r3/04-runtime-policies.md §1 vs protocol/v0.11/01-protocol-overview.md §5.5.3
**Confirmed by**: HG, SV confirm (2-1; TV out of scope, CRV no opinion)
**Description**: Daemon doc 04 §1 says error is sent when `CreateSessionRequest` is rejected (post-handshake). Protocol doc 01 §5.5.3 says "rejects a connection" (pre-handshake). Ambiguity about lifecycle stage.
**Fix**: Clarify in daemon doc 04 §1 and/or protocol doc 01 §5.5.3 at which stage the error is sent.

### V1-08 [LOW] IME v0.8 doc 04 reference text API names

**Location**: IME/v0.8/04-ghostty-integration.md §5 (reference text)
**Confirmed by**: HG, TV, SV confirm (3-1; CRV dismisses as topic description)
**Description**: Reference text says "drive ghostty APIs (`ghostty_surface_key()`, `ghostty_surface_preedit()`, `key_encode.encode()`)" — names APIs the daemon doesn't use per headless architecture.
**Fix**: Update API names to match daemon doc 01's headless equivalents when V1-01/V1-02 are fixed.

### V1-09 [LOW] Section numbering gap in protocol doc 03

**Location**: protocol/v0.11/03-session-pane-management.md §5
**Confirmed by**: TV, CRV confirm (HG, SV no opinion)
**Description**: Section 5 jumps from 5.6 to 5.8 — section 5.7 is missing.
**Fix**: Renumber 5.8 to 5.7 (or insert missing section).

## Dismissed Issues

### G — design-resolutions-per-tab-engine.md missing from v0.7/v0.8

**Dismissed by**: HG, TV, CRV (3-1; SV maintains)
**Reason**: File is a v0.6 historical discussion record. IME v0.8 TODO explicitly states it is NOT a migration target and MUST NOT be modified. File correctly lives only in v0.6. Daemon doc 02 correctly references the v0.6 path. I9 in the IME v0.8 TODO tracks the wire-to-KeyEvent decomposition change in 02-types.md, not the design-resolutions file.

### J — Protocol docs use ghostty_surface_preedit()

**Dismissed by**: CRV (1-3; HG, TV, SV confirm)
**Reason**: Daemon doc 01 §6.4 explicitly states: "The injection mechanism (`overlayPreedit` vs `ghostty_surface_preedit`) is a server-side implementation detail invisible to the wire." Protocol docs describe wire-observable behavior using the conceptual term, which is by design. Team-lead agrees with CRV's analysis and daemon doc 01's explicit guidance.
