# IME Module Naming Confusion

**Date**: 2026-03-09
**Raised by**: owner
**Severity**: MEDIUM
**Affected docs**: 01-internal-architecture.md (Sections 1.2, 1.6), design-resolutions/01-daemon-architecture.md (R1)
**Status**: open

---

## Problem

The inter-library dependency diagram in Section 1.6 has two issues:

### Issue 1: `libitshell3-ime` missing from diagram

`libitshell3-protocol` is correctly shown as a separate top-level library entry:

```
libitshell3-protocol  (standalone — depends only on Zig std; libssh2 added in Phase 5)
```

But `libitshell3-ime` — also a separate library — is absent. It appears only parenthetically in `server/`'s dependency list. This is inconsistent: both are project-level libraries at the same level, but only one is shown.

### Issue 2: Internal module `libitshell3/ime/` vs library `libitshell3-ime`

The diagram lists:

```
libitshell3/ime/      (depends on core/)
```

This is an internal module (Phase 0+1 key routing orchestration). But its name `libitshell3/ime/` is nearly identical to the separate library `libitshell3-ime` (HangulImeEngine, wraps libhangul). Reading the diagram, it is easy to mistake the internal module for the external library, or to miss that they are two different things.

## Analysis

The project has three separate libraries as defined in CLAUDE.md:

| Library | Role |
|---------|------|
| `libitshell3` | Daemon core (internal modules: core/, ghostty/, ime/, server/) |
| `libitshell3-protocol` | Wire protocol (codec, framing, state machine, transport) |
| `libitshell3-ime` | IME engine (HangulImeEngine, wraps libhangul) |

The dependency diagram should show all three at the top level for consistency. The internal module naming should not collide with a separate library name.

## Proposed Change

1. **Add `libitshell3-ime` to the diagram** as a top-level entry alongside `libitshell3-protocol`:

   ```
   libitshell3-protocol  (standalone — depends only on Zig std; libssh2 added in Phase 5)
   libitshell3-ime       (standalone — depends on libhangul)
   libitshell3/core/     (standalone — no external deps)
   libitshell3/ghostty/  (depends on core/, vendored ghostty)
   libitshell3/ime/      (depends on core/)          ← rename this
   libitshell3/server/   (depends on core/, ghostty/, ime/, libitshell3-ime, libitshell3-protocol)
   ```

2. **Rename internal module `libitshell3/ime/`** to avoid confusion with `libitshell3-ime`. Candidates:

   - `input/` — short, describes what it does (input routing)
   - `key_routing/` — explicit about Phase 0+1 key routing responsibility
   - `ime_routing/` — preserves "ime" context but distinguishes from the library

   Left to designers for final naming choice.

## Owner Decision

Both issues confirmed. Add `libitshell3-ime` to diagram. Rename internal module to disambiguate from the library.

## Resolution

(open)
