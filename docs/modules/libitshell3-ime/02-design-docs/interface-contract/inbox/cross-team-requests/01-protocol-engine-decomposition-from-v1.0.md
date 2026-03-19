# Engine Decomposition Responsibility Boundary

- **Date**: 2026-03-18
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: IME interface contract (engine constructor, input_method
  handling)
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 04 §2.1 contained a
paragraph describing how the `input_method` string flows through the system and
where engine-specific decomposition occurs. This text was identified as IME
architecture documentation rather than a wire protocol concern, and was removed
from the protocol spec.

The key design invariant is: the `input_method` string is the canonical
identifier throughout the system (client, server, and IME engine constructor).
Only the engine constructor is permitted to decompose it into engine-specific
types (e.g., libhangul keyboard IDs). No other code outside the engine
constructor performs this decomposition. The interface contract should document
this boundary explicitly so that both the daemon team and future IME
implementors know where decomposition happens and where it must not happen.

Additionally, Doc 05 §1.1 described the preedit exclusivity invariant, which is
directly tied to the single-engine-instance-per-session architecture that the
interface contract governs. This content also belongs in the interface contract.

## Required Changes

1. **Engine constructor — decomposition responsibility**: In the engine
   constructor section (currently `03-engine-interface.md`), add an explicit
   statement that the engine constructor is the sole location where the
   `input_method` string is decomposed into engine-specific types (e.g., a
   libhangul keyboard ID constant). Document that:
   - The `input_method` string flows unchanged from client to server to the
     engine constructor call site.
   - No code outside the engine constructor examines or transforms the
     `input_method` string for engine routing purposes.
   - The canonical registry of valid `input_method` strings lives in the
     interface contract itself (Section 3.7), which the engine constructor must
     validate against.

2. **Per-session engine model — preedit exclusivity**: In the per-session engine
   architecture section, add documentation of the preedit exclusivity invariant
   that follows from the single-engine-per-session design. Specifically: at most
   one pane in a session can have active preedit at any time, because the engine
   has one `HangulInputContext` with one jamo stack. A correct implementation
   MUST NOT allow simultaneous active preedit across two panes in the same
   session.

## Summary Table

| Target Doc               | Section/Message                         | Change Type | Source Resolution             |
| ------------------------ | --------------------------------------- | ----------- | ----------------------------- |
| `03-engine-interface.md` | Engine constructor, input_method param  | Add         | Protocol v1.0-r12 Doc 04 §2.1 |
| `03-engine-interface.md` | Per-session engine, preedit exclusivity | Add         | Protocol v1.0-r12 Doc 05 §1.1 |

## Reference: Original Protocol Text (removed from Doc 04 §2.1 and Doc 05 §1.1)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the IME interface-contract team — adapt as
needed.

### Engine decomposition (removed from Doc 04 §2.1)

> The `input_method` string is the **canonical identifier** for input methods.
> It flows unchanged from client to server to IME engine constructor. Inside the
> engine, it is decomposed into engine-specific types (e.g., libhangul keyboard
> IDs). No code outside the engine constructor performs this decomposition. The
> canonical registry of valid `input_method` strings is defined in the IME
> Interface Contract, Section 3.7.

### Preedit exclusivity invariant (removed from Doc 05 §1.1)

> **Preedit exclusivity invariant**: At most one pane in a session can have
> active preedit at any time. This is naturally enforced by the single engine
> instance per session — the engine has one `HangulInputContext` with one jamo
> stack. A server that correctly implements the per-session engine model MUST
> NOT produce simultaneous PreeditUpdate messages for two different panes within
> the same session. Clients MAY rely on this invariant for rendering
> optimization: when a PreeditStart arrives for pane B, any active preedit on
> pane A within the same session has already been cleared via PreeditEnd.
