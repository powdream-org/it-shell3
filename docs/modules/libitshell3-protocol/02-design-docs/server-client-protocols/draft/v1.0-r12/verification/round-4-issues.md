# Round 4 Verification Issues — Server-Client Protocol v1.0-r12

- **Date**: 2026-03-15
- **Phase 1**: consistency-verifier, semantic-verifier (both via Gemini)
- **Phase 2**: issue-reviewer-fast (sonnet), issue-reviewer-deep (opus) (Gemini
  fallback — direct analysis)
- **Outcome**: 7 confirmed, 1 dismissed

---

## Dismissed

**C4-03** — Doc 02 v1.0-r12 changelog R9 entry: subsection names mismatch

- Dismissed by both Phase 2 reviewers: Category 1 — Historical record. The
  v1.0-r12 changelog records names as they were when the subsection numbers were
  added; changelogs are not expected to track subsequent renames.

---

## Confirmed Issues

### C4-01 — Wrong message type names in Doc 01 §5.6 and Doc 02 §9.9

**Severity**: minor **Location**: `01-protocol-overview.md` §5.6 (line ~621),
`02-handshake-capability-negotiation.md` §9.9 (line ~828) **Description**: Both
locations use non-existent message type names `WindowResizeRequest` and
`WindowResizeResponse`. The actual registered types are `WindowResize` (0x0190,
C→S) and `WindowResizeAck` (0x0191, S→C), defined in Doc 03 §5.1/§5.7 and the
registry.

- Doc 01 §5.6: `WindowResizeRequest`/`WindowResizeResponse` →
  `WindowResize`/`WindowResizeAck`
- Doc 02 §9.9: `WindowResizeRequest`/`WindowResizeResponse`/`WindowResizeAck` →
  `WindowResize` (C→S) and `WindowResizeAck` (S→C)

---

### C4-02 — Broken cross-reference in Doc 06 §10 Timeout table

**Severity**: minor **Location**: `06-flow-control-and-auxiliary.md` §10 Timeout
Handling table **Description**: PausePane escalation row says
`(see Section 2.10)`. Section 2.10 is `OutputQueueStatus`. The health escalation
timeline (5s/60s/300s) is in §2.8 Client Health Model. **Correction**: Change
`(see Section 2.10)` → `(see Section 2.8)`.

---

### S4-01 — Missing state machine transition: DestroySessionResponse

**Severity**: minor **Location**: `01-protocol-overview.md` §5.3 (lifecycle
state machine) vs. `03-session-pane-management.md` §1.9–§1.10 **Description**:
Doc 01 §5.3 defines `OPERATING → READY` only via `SessionDetach`. When a session
is destroyed, the requesting client receives `DestroySessionResponse` (not a
detach). The state machine has no defined transition for this path — a client
strictly following the state machine remains in `OPERATING` after its session is
destroyed.

---

### S4-02 — AttachOrCreateRequest missing detach_others and readonly fields — DEFERRED

**Severity**: minor **Location**: `03-session-pane-management.md` §1.13 vs. §1.5
**Description**: `AttachOrCreateRequest` (0x010C) omits `detach_others` and
`readonly` fields present in `AttachSessionRequest` (0x0104). A client needing
exclusive or read-only attach-or-create has no protocol mechanism to do so via
the combined message.

**Resolution**: Deferred to next revision. Owner decided to merge
AttachOrCreateRequest into AttachSessionRequest entirely (remove 0x010C/0x010D).
See ADR 00003 and review note `01-merge-attach-session-and-attach-or-create.md`.

---

### S4-03 — ClipboardWrite procedure contradicts message schema — DEFERRED

**Severity**: minor **Location**: `06-flow-control-and-auxiliary.md` §3.3
**Description**: OSC 52 procedure states: "1. Decode the base64 data. 2. Send a
ClipboardWrite with the decoded data." But `ClipboardWrite.data` is a JSON
string field (`encoding: "utf8"` or `"base64"`). Placing decoded binary bytes
into a UTF-8 JSON string corrupts binary clipboard content. The procedure must
either re-encode decoded binary to base64 (setting `encoding: "base64"`) or pass
the base64 string through unchanged.

**Resolution**: Deferred to next revision. Owner decided to fix OSC 52 procedure
(base64 pass-through) and add symmetric `encoding` field to
ClipboardWriteFromClient (0x0604). See ADR 00004 and review note
`02-symmetric-clipboard-encoding.md`.

---

### S4-04 — pane_remains: true contradicts v1 auto-close mandate

**Severity**: minor **Location**: `06-flow-control-and-auxiliary.md` §5.3 vs.
`03-session-pane-management.md` §2.5 **Description**: Doc 06 §5.3 defines
`ProcessExited` with a normative field `pane_remains: true` meaning "pane stays
open (remain-on-exit)." Doc 03 §2.5 mandates: "the server MUST automatically
close the pane … Remain-on-exit is deferred to post-v1." The field definition
and example in §5.3 directly contradict the v1 auto-close MUST requirement.

---

### S4-05 — Stale parenthetical in reserved handshake range annotation

**Severity**: minor **Location**: `01-protocol-overview.md` §4.2.1 (message type
registry) **Description**: Reserved range `0x0006–0x00FE` is annotated "(e.g.,
AttachOrCreate references)." `AttachOrCreateRequest` is allocated at `0x010C` in
the Session & Pane Management range — not the handshake range. The parenthetical
is a stale artifact from an earlier design iteration and incorrectly implies the
message belongs in the handshake range.

---

## Note for Owner Triage

All 7 confirmed issues are **pre-existing** — they were present in the base
documents before the v1.0-r12 revision and are not caused by or related to any
of the 10 v1.0-r12 resolutions. The v1.0-r12 revision addressed its 10
resolutions cleanly (verified across Rounds 1–3). These 7 issues represent
pre-existing design gaps discovered during the broader Round 4 verification
pass.

Owner options (per workflow §3.8):

1. **Proceed to Round 5**: Fix all 7 issues now.
2. **Declare clean**: Accept remaining issues as acceptable for v1.0-r12.
3. **Declare deferred**: Accept remaining issues as known, defer to next
   revision cycle.
