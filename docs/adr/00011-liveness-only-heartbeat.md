# 00011. Liveness-Only Heartbeat

- Date: 2026-03-16
- Status: Accepted

## Context

The heartbeat mechanism could measure both connection liveness and round-trip
time (RTT). With SSH tunneling, the protocol-level heartbeat traverses only the
local Unix socket hop to sshd, not the full client-to-server path.

## Decision

Heartbeat is liveness-only (no RTT measurement). With SSH tunneling, heartbeat
RTT only measures local socket hop to sshd (~0ms), making it useless for latency
estimation. Client self-reports transport latency via
`ClientDisplayInfo.estimated_rtt_ms`. Neither tmux nor zellij measures RTT.

## Consequences

- Simpler heartbeat: ping_id echo only, no timestamp fields.
- Client-reported latency enables coalescing tier adaptation for WAN clients.
- No server-side RTT computation or smoothing logic.
