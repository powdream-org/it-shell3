# Verification Round 2 — Issues

## Round Metadata

- **Round**: 2
- **Date**: 2026-03-09
- **Verifiers**: cross-reference-verifier, terminology-verifier, semantic-verifier, history-guardian
- **Note**: All 5 Round 1 issues (V1-01 through V1-05) confirmed fixed by all 4 verifiers.

## Confirmed Issues

### V2-01: "protocol specification (Section 5.2)" Missing Document Qualifier

| Field | Value |
|-------|-------|
| **Severity** | minor |
| **Source documents** | `03-lifecycle-and-connections.md` Section 4.1 (line 345) |
| **Description** | Uses "protocol specification (Section 5.2)" without a document number qualifier. The resolution doc R9 (line 423) and Doc 02 (line 54) both use the qualified form "protocol doc 01 Section 5.2". Same pattern as V1-04. |
| **Expected correction** | Change to "protocol doc 01 (Section 5.2)". |
| **Consensus note** | Unanimous 4/4. Same V1-04 pattern — unqualified "protocol spec" is ambiguous in a family of six protocol docs. |

### V2-02: "protocol spec Section 2.2" Missing Document Qualifier

| Field | Value |
|-------|-------|
| **Severity** | minor |
| **Source documents** | `03-lifecycle-and-connections.md` Section 8 (line 647, inside code block comment) |
| **Description** | Uses "protocol spec Section 2.2" without a document number qualifier. The resolution doc R9 (lines 478, 499) and Doc 02 (line 202) both use the qualified form "protocol doc 01 Section 2.2". Doc 03 is the only document with the unqualified form. |
| **Expected correction** | Change to "protocol doc 01 Section 2.2". |
| **Consensus note** | Unanimous 4/4. Same V1-04 pattern. |

### V2-03: Resolution Doc R8 Graceful Shutdown Header Omits SIGHUP

| Field | Value |
|-------|-------|
| **Severity** | minor |
| **Source documents** | `design-resolutions/01-daemon-architecture.md` R8 (line 403) |
| **Description** | Header reads "Graceful shutdown (on SIGTERM/SIGINT or last-session-close)" — omits SIGHUP. R8 step 3 (line 397) explicitly registers SIGHUP as a signal filter alongside SIGTERM and SIGINT. All three spec documents correctly include SIGHUP as a graceful shutdown trigger. The header's enumeration is incomplete relative to its own body. |
| **Expected correction** | Change header to "Graceful shutdown (on SIGTERM/SIGINT/SIGHUP or last-session-close)". |
| **Consensus note** | Unanimous 4/4. Internal contradiction within the resolution doc — header omits a signal registered in its own body. |

## Dismissed Issues

| Issue | Reason |
|-------|--------|
| Doc 02 "protocol spec Section 2.1" (line 84) | Resolution doc R5 (line 167) uses the identical unqualified form. Doc 02 faithfully reproduces its source. No cross-document inconsistency. |
| Doc 02 "per protocol spec" (line 163) | Resolution doc R5 (line 182) uses the identical phrase. Doc 02 faithfully reproduces its source. No cross-document inconsistency. |
