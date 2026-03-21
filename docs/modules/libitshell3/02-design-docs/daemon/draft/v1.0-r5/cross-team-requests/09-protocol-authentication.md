# Move Authentication Implementation from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 01 was identified as
containing daemon implementation details across multiple sections:

- §2.2 (lines 131-135): `getpeereid()` trust model for SSH tunnel connections
- §12.1 (lines 1108-1116): Unix socket authentication implementation (syscall
  selection, socket/directory permissions)
- §12.2 (lines 1119-1134): SSH tunnel authentication (sshd UID trust chain)
- §12.3 (lines 1136-1143): Handshake timeout values (5s/60s/90s)

The protocol spec defines the security model at a conceptual level (UID
verification, SSH transport-layer auth, no protocol-level auth). However, the
implementation details — syscall selection, socket file permissions, directory
permissions, and concrete timeout values — are daemon lifecycle and connection
management concerns.

## Required Changes

1. **Unix socket authentication**: Add UID verification implementation details —
   `getpeereid()` syscall (or platform equivalent), socket file permissions,
   socket directory permissions.
2. **SSH tunnel trust model**: Add the `getpeereid()` → sshd UID trust chain
   documentation and the rationale for accepting sshd's UID as proxy for the
   authenticated remote user.
3. **Handshake timeouts**: Add concrete timeout values — transport connection
   (5s), ClientHello→ServerHello (5s), READY→session request (60s), heartbeat
   response (90s) — and the corresponding actions on timeout.
4. **Auth implementation scope note (from Doc 02 §11.1)**: Document that
   authentication implementation details — syscall selection, socket file
   permissions, and directory permissions — are the daemon's responsibility to
   define (the protocol spec defers these to daemon design docs).
5. **Handshake timeout table (from Doc 02 §11.3)**: Confirm the four concrete
   timeout values also appear in Doc 02 §11.3 and ensure the daemon docs align
   with this authoritative table: transport connection (5s, close socket),
   ClientHello→ServerHello (5s, send `Error(ERR_INVALID_STATE)` and close),
   READY→session request (60s, send `Disconnect(TIMEOUT)` and close), heartbeat
   response (90s, send `Disconnect(TIMEOUT)` and close).

## Summary Table

| Target Doc              | Section/Message              | Change Type | Source Resolution                    |
| ----------------------- | ---------------------------- | ----------- | ------------------------------------ |
| Lifecycle & connections | Unix socket auth             | Add         | Protocol v1.0-r12 Doc 01 §12.1       |
| Lifecycle & connections | SSH tunnel trust model       | Add         | Protocol v1.0-r12 Doc 01 §2.2, §12.2 |
| Lifecycle & connections | Handshake timeouts           | Add         | Protocol v1.0-r12 Doc 01 §12.3       |
| Lifecycle & connections | Auth implementation scope    | Add         | Protocol v1.0-r12 Doc 02 §11.1       |
| Lifecycle & connections | Handshake timeout table (02) | Add         | Protocol v1.0-r12 Doc 02 §11.3       |

## Reference: Original Protocol Text

### From Doc 01 §2.2, §12 — Authentication (removed)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

#### From §2.2 — SSH Tunnel Security Trust Model

**Security trust model:** When a client connects through an SSH tunnel,
`getpeereid()` returns sshd's UID. The daemon accepts this because SSH has
already authenticated the user at the transport layer. The trust chain is: SSH
authentication → sshd process → Unix socket → daemon. The daemon trusts sshd's
UID as a proxy for the authenticated remote user's identity.

#### 12.1 Unix Socket Authentication

Unix socket connections are authenticated by kernel-level UID verification. Only
connections from the same UID as the daemon process are accepted. No additional
authentication is needed for Unix socket transport because the OS kernel
guarantees the peer identity.

Authentication implementation details (syscall selection, socket file
permissions, directory permissions) are defined in daemon design docs.

#### 12.2 SSH Tunnel Authentication

For remote access, authentication is handled entirely by SSH:

1. **SSH key authentication**: Standard public key auth, agent forwarding, or
   password auth — handled by the SSH transport before any protocol messages are
   exchanged.
2. **sshd UID trust**: When a client connects through an SSH tunnel,
   `getpeereid()` returns sshd's UID. The daemon accepts this because SSH has
   already authenticated the user at the transport layer. The trust chain is:
   SSH authentication → sshd process → Unix socket → daemon.
3. **No protocol-level auth**: The `ClientHello`/`ServerHello` handshake is the
   same for local and tunneled connections. Authentication is transport-layer,
   not application-layer.

This approach avoids the security audit risk of a custom mTLS/SRP implementation
and leverages SSH's decades of hardening.

#### 12.3 Handshake Timeouts

| Timeout                                                                          | Duration   | Action                                  |
| -------------------------------------------------------------------------------- | ---------- | --------------------------------------- |
| Transport connection                                                             | 5 seconds  | Close socket, report connection failure |
| `ClientHello` -> `ServerHello`                                                   | 5 seconds  | Send `Error(ERR_INVALID_STATE)`, close  |
| `READY` -> `AttachSessionRequest`/`CreateSessionRequest`/`AttachOrCreateRequest` | 60 seconds | Send `Disconnect(TIMEOUT)`, close       |
| Heartbeat response                                                               | 90 seconds | Send `Disconnect(TIMEOUT)`, close       |

### From Doc 02 §11.1 — Unix Socket Authentication (impl scope note)

The following is the original text from Doc 02 §11.1 (Unix Socket
Authentication) that defers implementation details to daemon design docs.
Provided as reference for the daemon team — adapt as needed.

Unix socket connections are authenticated by kernel-level UID verification. Only
connections from the same UID as the daemon process are accepted. No additional
authentication is needed for Unix socket transport because the OS kernel
guarantees the peer identity.

Authentication implementation details (syscall selection, socket file
permissions, directory permissions) are defined in daemon design docs.

### From Doc 02 §11.3 — Handshake Timeouts

The following is the original text from Doc 02 §11.3 (Handshake Timeouts). This
table also appears in Doc 01 §12.3 (already in CTR-09 Required Change 3) but is
reproduced here verbatim from Doc 02 as an additional source. Provided as
reference for the daemon team — adapt as needed.

| Timeout                                                                          | Duration   | Action                                  |
| -------------------------------------------------------------------------------- | ---------- | --------------------------------------- |
| Transport connection                                                             | 5 seconds  | Close socket, report connection failure |
| `ClientHello` -> `ServerHello`                                                   | 5 seconds  | Send `Error(ERR_INVALID_STATE)`, close  |
| `READY` -> `AttachSessionRequest`/`CreateSessionRequest`/`AttachOrCreateRequest` | 60 seconds | Send `Disconnect(TIMEOUT)`, close       |
| Heartbeat response                                                               | 90 seconds | Send `Disconnect(TIMEOUT)`, close       |
