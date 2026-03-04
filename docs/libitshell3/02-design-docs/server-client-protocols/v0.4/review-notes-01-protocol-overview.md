# Review Notes: 01-protocol-overview.md (v0.4)

**Reviewer**: heejoon.kang
**Date**: 2026-03-04

---

## Issue 1: Multi-tab scenario requires multi-connection model, but spec does not document it

**Severity**: High (architectural gap — affects multi-tab UX)

### Problem

Section 5.2 states:

> **Single-session-per-connection rule:** A client connection is attached to at most
> one session at a time. To switch sessions, the client must first detach
> (`DetachSessionRequest`) then attach to the new session.

This rule is correct at the protocol level, but the spec **never documents how a
client with multiple tabs maintains simultaneous access to multiple sessions.**

it-shell3 is a native macOS/iOS terminal app with multiple tabs. Each tab maps to
a Session (doc 03 confirms this: "mapping each libitshell3 Session to one host tab").
The user expects:

- All tabs rendering simultaneously (not just the foreground tab)
- Input to any tab without detach/attach ceremony
- FrameUpdate delivery for all visible sessions, not just the attached one

With single-session-per-connection, the only viable model is **one Unix socket
connection per session (tab)**:

```
Client app
├── Connection 1 → Unix socket → daemon → Session A (tab 1)
├── Connection 2 → Unix socket → daemon → Session B (tab 2)
└── Connection 3 → Unix socket → daemon → Session C (tab 3)
```

This is architecturally sound — each connection has independent state, independent
FrameUpdate streams, and no detach/attach overhead when switching tabs. But the
spec says nothing about it.

### Additional concern: SSH tunneling with multiple connections

For Phase 6 (iOS-to-macOS over SSH), the client needs multiple Unix socket
connections over a single SSH tunnel. This is supported — SSH natively multiplexes
channels:

```
SSH TCP connection (1 connection)
├── Channel 1 → forwarded Unix socket → Session A
├── Channel 2 → forwarded Unix socket → Session B
└── Channel 3 → forwarded Unix socket → Session C
```

Each SSH channel acts as an independent socket connection from the daemon's
perspective. No protocol changes needed — SSH handles mux/demux transparently.

However, this interaction between multi-connection and SSH tunneling is not
documented anywhere.

### What is missing from the spec

1. **Multi-connection model**: Explicit statement that a client SHOULD open one
   connection per session for multi-tab scenarios. The single-session-per-connection
   rule implicitly requires this, but it should be stated as the canonical pattern.

2. **Connection lifecycle for tabs**: When the user opens a new tab, the client
   opens a new connection, performs handshake, and creates/attaches a session.
   When a tab is closed, the client destroys the session and closes the connection.
   This workflow is not documented.

3. **Max connections per client**: No limit is specified. Should the daemon enforce
   a maximum number of simultaneous connections? (e.g., 256 connections = 256 tabs).

4. **SSH tunnel interaction**: Document that multiple connections over a single SSH
   tunnel works via SSH channel multiplexing. No special protocol support needed.

5. **Handshake overhead**: Each connection requires a full ClientHello/ServerHello
   exchange. For a user rapidly opening 10 tabs, that's 10 handshakes. Is this
   acceptable, or should the spec consider a lightweight "additional connection"
   handshake for already-authenticated clients?

### Recommendation

Add a new subsection (e.g., Section 5.5 "Multi-Session Client Model") documenting:

1. One connection per session as the canonical multi-tab pattern
2. Connection lifecycle aligned with tab lifecycle
3. SSH tunnel multiplexing for remote clients
4. Maximum connection limit policy (or explicit "no limit, daemon discretion")
5. Whether handshake optimization for additional connections is needed or deferred

Reference investigation needed: check how tmux handles the multi-window/multi-pane
case — does `tmux` use multiple server connections, or a single connection with
multiplexed window switching? This would inform whether our multi-connection model
is aligned with or divergent from established patterns.
