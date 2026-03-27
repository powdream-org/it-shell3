# Revise Connection Limits for Static Allocation

- **Date**: 2026-03-27
- **Source team**: impl (Plan 5.5 Spec Alignment Audit)
- **Source version**: libitshell3 implementation Plans 1-5
- **Source resolution**: ADR 00052 (static SessionManager allocation)
- **Target docs**: `03-policies-and-procedures.md` Section 1 (Connection Limits)
- **Status**: open

---

## Context

ADR 00052 established static allocation as the memory strategy for all daemon
state — `SessionManager` uses `[MAX_SESSIONS]?SessionEntry`, and `EventLoop`
uses `[MAX_CLIENTS]?ClientEntry`. Both are fixed-size arrays with compile-time
upper bounds.

The current spec Section 1 (Connection Limits) contains the invariant:

> "The daemon MUST NOT impose a protocol-level connection limit. The limit is an
> implementation guard using OS resource limits."

This invariant is incompatible with static allocation. A fixed-size array IS a
protocol-level connection limit — when all slots are full, new connections are
rejected regardless of OS resource availability. The invariant must be revised
to reflect the ADR 00052 decision.

## Required Changes

1. **Remove the "MUST NOT impose" invariant.** Replace with: "The daemon
   enforces a compile-time connection capacity (`MAX_CLIENTS`). When all client
   slots are occupied, new connections are rejected with
   `ERR_RESOURCE_EXHAUSTED`." This aligns with the static allocation model where
   capacity is determined at compile time, not by OS limits.

2. **Revise the "Minimum concurrent" parameter.** The current minimum of 256 was
   set assuming dynamic allocation with no fixed limit. With static allocation,
   the `MAX_CLIENTS` constant defines the capacity. The spec should state the
   minimum value for `MAX_CLIENTS` rather than framing it as "minimum concurrent
   connections." The actual value (currently 64 in code) needs owner review — it
   may remain at 64 or be raised, but the spec should specify the normative
   minimum.

3. **Keep RLIMIT_NOFILE guidance as SHOULD.** Raising the soft limit is still
   good practice (each connection + pane consumes fds), but it is no longer the
   primary connection limiter. The fixed array is.

4. **Update the resource budget note.** The "typical deployment" example (50
   sessions, 5 panes each = 300 fds) should note that `MAX_SESSIONS` and
   `MAX_CLIENTS` also constrain the deployment ceiling independently of fd
   availability.

## Summary Table

| Target Doc                      | Section/Message           | Change Type       | Source Resolution |
| ------------------------------- | ------------------------- | ----------------- | ----------------- |
| `03-policies-and-procedures.md` | Section 1 invariant       | Revise            | ADR 00052         |
| `03-policies-and-procedures.md` | Section 1 parameters      | Revise            | ADR 00052         |
| `03-policies-and-procedures.md` | Section 1 RLIMIT note     | Keep (minor edit) | ADR 00052         |
| `03-policies-and-procedures.md` | Section 1 resource budget | Update            | ADR 00052         |
