# Merge AttachSession and AttachOrCreate into Single Message Type

- **Date**: 2026-03-15
- **Raised by**: owner
- **Severity**: MEDIUM
- **Affected docs**: Doc 01 (message type registry), Doc 02 (handshake
  references), Doc 03 (session management — primary)
- **Status**: deferred to next revision

---

## Problem

`AttachSessionRequest` (0x0104) and `AttachOrCreateRequest` (0x010C) are two
separate message pairs with overlapping semantics. They differ only in lookup
strategy (`session_id` vs `session_name`) and create-if-missing behavior. Their
post-attach response sequences are identical.

This split causes a field parity gap (verification issue S4-02):
`AttachOrCreateRequest` is missing `readonly` and `detach_others` fields present
in `AttachSessionRequest`. A client needing exclusive or read-only
attach-or-create must fall back to a multi-step sequence (check existence, then
call the appropriate message), defeating the purpose of the convenience message.

## Analysis

Both fields (`readonly`, `detach_others`) originate from tmux patterns
(`attach-session -r` and `attach-session -d`). `AttachOrCreate` itself is
equivalent to tmux's `new-session -A`. Since both messages serve the same
logical goal (end up attached to a session), maintaining two message pairs with
divergent field sets creates unnecessary protocol surface and implementation
burden.

No implementation exists yet (design phase only), so there is no
backward-compatibility cost.

## Proposed Change

Merge `AttachOrCreateRequest` into `AttachSessionRequest` (0x0104/0x0105).
Remove the 0x010C/0x010D message type pair entirely. The unified message absorbs
both lookup strategies, all flags, and create-if-missing semantics. The exact
field set — in particular, whether `session_id` is needed alongside
`session_name` — is an open question to be resolved during the next revision.

See ADR 00003 for the full decision record.

## Owner Decision

Merge approved. Deferred to next revision for implementation. S4-02 is closed by
this decision.

## Resolution

Recorded as ADR 00003. To be applied in the next protocol revision cycle.
