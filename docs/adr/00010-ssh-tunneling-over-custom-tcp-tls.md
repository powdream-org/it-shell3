# 00010. SSH Tunneling over Custom TCP+TLS

- Date: 2026-03-16
- Status: Accepted

## Context

Remote access requires a secure transport between client and daemon. Options:
custom TCP+TLS with mTLS certificate management, or SSH tunneling leveraging
existing infrastructure.

## Decision

SSH tunneling (not custom TCP+TLS). SSH reuses mature auth infrastructure (keys,
agent forwarding, 2FA). Eliminates mTLS cert management and custom port 7822.
Neither tmux nor zellij implements custom network transport. Single Unix socket
implementation — remote clients tunnel through SSH to the same socket.

## Consequences

- No custom TLS implementation to audit or maintain.
- Authentication delegated to SSH (decades of hardening).
- Remote latency includes SSH overhead, but heartbeat RTT only measures local
  socket hop to sshd (~0ms). Client self-reports transport latency via
  `ClientDisplayInfo.estimated_rtt_ms`.
- SSH's built-in compression covers WAN bandwidth concerns.
