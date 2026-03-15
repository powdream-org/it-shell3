# 00018. Multiplexed Input Channel

- Date: 2026-03-16
- Status: Accepted

## Context

Input messages (KeyEvent, MouseButton, etc.) could use a dedicated socket
connection separate from control/rendering messages, or share the same Unix
domain socket connection.

## Decision

Multiplexed: all input messages share the same Unix domain socket connection as
other protocol messages. A separate input channel adds connection management
complexity (two sockets per client) for no practical benefit — Unix domain
sockets provide >1 GB/s throughput with <0.1ms latency, making congestion
unrealistic for input traffic.

## Consequences

- Single connection per client — simpler connection lifecycle.
- No dedicated low-latency path for input. Not needed given Unix socket
  performance characteristics.
- Server-side input processing priority is an implementation concern (not
  protocol-visible).
