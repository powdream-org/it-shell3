# Verification Round 1 — Issues

## Round Metadata

- **Round**: 1
- **Date**: 2026-03-09
- **Verifiers**: cross-reference-verifier, terminology-verifier, semantic-verifier, history-guardian

## Confirmed Issues

### V1-01: SessionDetach vs SessionDetachRequest

| Field | Value |
|-------|-------|
| **Severity** | critical |
| **Source documents** | Resolution doc R9 diagram + `03-lifecycle-and-connections.md` Section 4.1 diagram vs Section 4.2 transitions table |
| **Description** | State machine diagrams in both the resolution doc and doc 03 use `SessionDetach` (short form). Transitions tables in both documents use `SessionDetachRequest` (full message name). The inconsistency originates in the resolution doc and was faithfully reproduced in the spec. Diagrams and tables disagree within each document. |
| **Expected correction** | Diagrams should use the full message name `SessionDetachRequest` to match the transitions tables. |
| **Consensus note** | All 4 verifiers agreed: same event must have one canonical name; the transitions table form (`SessionDetachRequest`) is more precise. |

### V1-02: AttachSession vs AttachSessionRequest

| Field | Value |
|-------|-------|
| **Severity** | critical |
| **Source documents** | `03-lifecycle-and-connections.md` Section 4.1 diagram vs Section 4.2 transitions table |
| **Description** | The state machine diagram in Section 4.1 uses `AttachSession` while the transitions table in Section 4.2 uses `AttachSessionRequest`. Same inconsistency pattern as V1-01. |
| **Expected correction** | Diagram should use `AttachSessionRequest` to match the transitions table. |
| **Consensus note** | All 4 verifiers agreed: same pattern as V1-01; the `*Request` suffix is the canonical form. |

### V1-03: server/ Missing libitshell3-ime Dependency

| Field | Value |
|-------|-------|
| **Severity** | critical |
| **Source documents** | Resolution doc R1 (module decomposition) vs Resolution doc R8 Step 6 + `03-lifecycle-and-connections.md` Section 1.1 Step 6 |
| **Description** | R1 lists `server/`'s dependencies as `core/`, `ghostty/`, `ime/`, and `libitshell3-protocol`. However, startup Step 6 calls `HangulImeEngine.init()`, a concrete type from the external `libitshell3-ime` library, which is distinct from the local `ime/` module. The external `libitshell3-ime` library is an unlisted dependency of `server/`. |
| **Expected correction** | R1's dependency list for `server/` should include `libitshell3-ime`, or the inter-library dependency diagram in doc 01 Section 1.6 should document this explicitly. |
| **Consensus note** | All 4 verifiers agreed: `HangulImeEngine` is a concrete type from the external library, not from the internal `ime/` module. The dependency list is incomplete. |

### V1-04: "protocol spec Section 9" Missing Document Qualifier

| Field | Value |
|-------|-------|
| **Severity** | critical |
| **Source documents** | `03-lifecycle-and-connections.md` Section 4.5 |
| **Description** | The reference "Readonly attachment is a client-requested mode (per protocol spec Section 9)" is missing the document qualifier. "Protocol spec" most naturally resolves to `01-protocol-overview.md`, where Section 9 is "Bandwidth Analysis" — the wrong topic. The correct target is `03-session-pane-management.md` Section 9. The resolution doc R9 precisely says "per protocol doc 03 Section 9". |
| **Expected correction** | Should read "per protocol doc 03 Section 9". |
| **Consensus note** | All 4 verifiers agreed: ambiguous cross-reference in a family of six protocol docs; the doc qualifier is required. |

### V1-05: Unexpected Disconnect Bypasses DISCONNECTING State

| Field | Value |
|-------|-------|
| **Severity** | minor |
| **Source documents** | Resolution doc R9 diagram vs `03-lifecycle-and-connections.md` Sections 3.3 + 4.2 transitions table |
| **Description** | The R9 state machine diagram routes all exits from OPERATING through DISCONNECTING. However, `03-lifecycle-and-connections.md` Section 3.3 and the Section 4.2 transitions table both show unexpected client disconnects (`conn.recv()` returning `.peer_closed`) going directly to `[closed]`, bypassing DISCONNECTING entirely. The spec's behavior is semantically correct (nothing to drain on an unexpected disconnect), but the deviation from the resolution diagram is undocumented. |
| **Expected correction** | Either the R9 diagram should distinguish graceful vs. unexpected disconnect paths, or the spec should include an explicit note explaining why unexpected disconnects bypass DISCONNECTING. |
| **Consensus note** | All 4 verifiers agreed: the spec's behavior is correct but the resolution diagram is misleading. The fix should align either direction. |

## Dismissed Issues

| Issue | Reason |
|-------|--------|
| Multi-threaded event loop deferred item (Issue 6) | "Not planned" is a permanent non-goal, not a deferred feature. R2 body already establishes single-threaded as the positive decision. Additive documentation, not a contradiction. |
| ghostty_surface_preedit parentheses (Issue 7) | The parens form appears in the "Prior consensus" column of the Corrections table — a historical record. The no-parens form is current normative text. Comparing historical vs normative is expected to differ. History-guardian veto. |
| Arrow notation `→` vs `->` (Issue 8) | Both forms render identically in Mermaid output. Source-level cosmetic variation with no semantic impact. |
