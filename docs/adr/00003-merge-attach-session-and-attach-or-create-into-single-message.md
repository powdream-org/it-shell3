# 00003. Merge AttachSession and AttachOrCreate into Single Message Type

- Date: 2026-03-15
- Status: Proposed

## Context

The server-client protocol defines two separate message pairs for session
attachment:

- **AttachSessionRequest/Response** (0x0104/0x0105): Attach to an existing
  session by `session_id`. Supports `readonly` and `detach_others` flags.
- **AttachOrCreateRequest/Response** (0x010C/0x010D): Attach by `session_name`
  if the session exists, or create a new one if it does not. Equivalent to
  tmux's `new-session -A`. Does NOT support `readonly` or `detach_others`.

This split creates a field parity problem (verification issue S4-02): a client
needing exclusive attach (`detach_others: true`) or observer mode
(`readonly: true`) cannot use AttachOrCreate — it must first check session
existence, then call AttachSession or CreateSession separately, defeating the
purpose of the convenience message.

The two messages differ only in lookup strategy (`session_id` vs `session_name`)
and create-if-missing semantics. Their post-attach response sequences are
identical (LayoutChanged, PreeditSync, I-frame, ClientAttached).

Since no implementation exists yet (the project is in design phase), there is no
backward-compatibility cost to merging.

## Decision

Merge AttachOrCreateRequest into AttachSessionRequest (0x0104/0x0105). Remove
the 0x010C/0x010D message type pair entirely.

The unified message absorbs both lookup strategies and all flags from both
original messages. The exact field set — in particular, whether `session_id` is
needed alongside `session_name` or `session_name` alone is sufficient — is an
open question to be resolved during the next revision.

The unified AttachSessionResponse (0x0105) adds `action_taken` (`"attached"` |
`"created"`) to indicate which path was taken.

This decision is recorded as a review note during the v1.0-r12 verification
cycle and will be applied in the next protocol revision.

## Consequences

- **S4-02 is resolved by elimination**: the field parity problem disappears
  because there is only one attach message.
- **One fewer message type pair**: 0x010C/0x010D are freed. Protocol surface
  shrinks.
- **Simpler client implementation**: clients only need one attach code path
  instead of choosing between two messages with overlapping semantics.
- **Slightly larger payload**: AttachSessionRequest gains optional fields
  (`session_name`, `create_if_missing`, `shell`, `cwd`) that were previously
  only in AttachOrCreate. JSON optional field convention (omit when absent)
  keeps the common case compact.
- **Docs affected**: Doc 01 (message type registry, state machine references),
  Doc 02 (handshake references to AttachOrCreate), Doc 03 (session management —
  primary change), and any changelog/cross-reference mentioning 0x010C/0x010D.
