# Extract Daemon Behavior from Protocol Docs

**Date**: 2026-03-10
**Source team**: daemon
**Source version**: daemon v0.2
**Source resolution**: daemon v0.2 review note 04 (daemon-behavior-migration-from-protocol-and-ime)
**Target docs**: 01-protocol-overview, 02-handshake-capability-negotiation, 03-session-pane-management, 04-input-and-renderstate, 05-cjk-preedit-protocol, 06-flow-control-and-auxiliary
**Status**: open

---

## Context

The daemon design documents now exist (v0.2). Content describing daemon-side behavior (process management, IME integration, flow control policies, multi-client management) was placed in protocol docs when there was no daemon doc to hold it. The daemon team is absorbing this content into daemon v0.3. The protocol docs should be reduced to wire format definitions, error codes, message types, and state machine transitions only.

This does NOT mean deleting content — it means replacing behavioral descriptions with references to daemon docs where appropriate, and ensuring protocol docs focus on "what goes on the wire" rather than "what the server does internally."

**Coordination requirement**: The changes requested here MUST be applied simultaneously and consistently with the corresponding content being added to `libitshell3/02-design-docs/daemon/draft/v1.0-r3` documents. Removing behavioral descriptions from protocol docs without the daemon docs being ready to receive them would create a gap in the design documentation.

## Required Changes

### 1. doc 01 §2.1 — Remove daemon auto-start procedure

- **Current**: Describes launchd socket activation, fork/exec, stale socket cleanup, exponential backoff (100ms→10s), 5-failure notification
- **After**: Keep Unix domain socket transport definition. Replace auto-start procedure with: "Daemon lifecycle management (auto-start, restart, stale socket cleanup) is defined in daemon design docs."
- **Rationale**: Auto-start is daemon process management, not wire protocol

### 2. doc 01 §2.1 — Remove FD passing for crash recovery

- **Current**: Describes PTY master FD passing via `sendmsg(2)`/`SCM_RIGHTS`
- **After**: Remove. This is a daemon-internal recovery mechanism with no wire protocol impact
- **Rationale**: OS-level IPC mechanism, not protocol definition

### 3. doc 01 §5.5.3 — Remove connection limit policy

- **Current**: "daemon MAY impose implementation-level limits and SHOULD support at least 256 concurrent connections"
- **After**: Keep only the error code reference: "If server rejects a connection for resource reasons, it sends ERR_RESOURCE_EXHAUSTED." Remove the 256 number and SHOULD language
- **Rationale**: Connection limits are daemon configuration, not protocol specification

### 4. doc 01 §5.5 — Remove timeout values from eviction description

- **Current**: "T=300s: Eviction. Server sends Disconnect("stale_client")"
- **After**: Keep only: "Server MAY send Disconnect with reason `stale_client` to evict unresponsive clients." Remove specific timeout values
- **Rationale**: Protocol defines the disconnect reason enum; daemon defines when to use it

### 5. doc 01 §5.6 — Reduce multi-client resize to wire behavior only

- **Current**: Describes latest/smallest policy selection, `latest_client_id` tracking, fallback behavior
- **After**: Keep: resize policy is communicated via capability negotiation (if applicable) and WindowResize messages. Remove server-internal tracking logic (latest_client_id, fallback rules)
- **Rationale**: Wire messages for resize are protocol; policy selection and internal tracking are daemon

### 6. doc 01 §10 — Reduce coalescing to wire-observable behavior

- **Current**: Describes event-driven coalescing with 16ms ceiling, preedit immediate flush, WAN adaptation, power throttle bypass
- **After**: Keep: "FrameUpdates are not sent at a fixed rate. The server sends them in response to terminal state changes." Remove internal coalescing tiers, timing values, power state logic
- **Rationale**: Coalescing is server-internal optimization; the wire just sees FrameUpdate messages

### 7. doc 01 §12.1 — Remove auth implementation details

- **Current**: Describes `getpeereid()`/`SO_PEERCRED`, socket file permissions 0600, directory 0700
- **After**: Keep: "Unix socket connections are authenticated by kernel-level UID verification." Remove syscall names and permission values
- **Rationale**: Protocol defines auth at handshake level; OS-level mechanism is daemon implementation

### 8. doc 01 §3.4 — Remove heartbeat policy details

- **Current**: "Typically server initiates; client MAY also send"
- **After**: Keep message format definition. Remove "typically server initiates" — that's daemon policy
- **Rationale**: Heartbeat message type is protocol; who initiates is daemon behavior

### 9. doc 02 §11.2 — Remove reconnection procedure

- **Current**: 7-step reconnection procedure (establish connection, handshake, see sessions, send ClientDisplayInfo, attach, receive I-frame, resynchronized)
- **After**: Keep: "Reconnection uses the normal handshake flow. There is no incremental reconnection protocol." Remove the step-by-step procedure
- **Rationale**: Reconnection steps are daemon/client application behavior, not wire protocol additions

### 10. doc 02 §9.6 — Reduce preedit exclusivity to wire messages

- **Current**: Describes single-owner model, conflict resolution (commit first client's preedit, send PreeditEnd with `replaced_by_other_client`)
- **After**: Keep: PreeditEnd reason enum includes `replaced_by_other_client`. Remove server-side ownership logic and conflict resolution algorithm
- **Rationale**: Protocol defines the messages; daemon defines when/how to send them

### 11. doc 02 §9.9 — Remove stale re-inclusion hysteresis

- **Current**: "Must remain healthy for 5 seconds before re-inclusion in resize calculation"
- **After**: Remove. This is daemon-internal health state machine logic
- **Rationale**: Wire protocol has no concept of hysteresis; this is pure server policy

### 12. doc 03 §2.7 — Reduce preedit flush on focus to wire behavior

- **Current**: "server MUST flush (commit) current preedit to PTY and send PreeditEnd with reason 'focus_changed'"
- **After**: Keep: FocusPaneRequest may trigger PreeditEnd with `reason=focus_changed`. Remove "flush to PTY" detail (daemon internal)
- **Rationale**: Protocol defines the message; PTY write is daemon implementation

### 13. doc 03 §2.5, §1.9 — Reduce pane close to wire messages

- **Current**: Describes SIGHUP, PTY cleanup, layout reflow algorithm
- **After**: Keep: ClosePaneResponse, LayoutChanged notification. Remove SIGHUP, PTY details, reflow algorithm
- **Rationale**: Wire messages are protocol; OS signal and PTY cleanup are daemon

### 14. doc 03 §5.4 — Remove TIOCSWINSZ resize implementation

- **Current**: "ioctl(pane.pty_fd, TIOCSWINSZ, &new_size)" with debounce details
- **After**: Keep: WindowResizeRequest/Response messages. Remove ioctl details and debounce algorithm
- **Rationale**: Resize messages are protocol; PTY ioctl is daemon implementation

### 15. doc 03 §8 — Reduce input method state to wire fields

- **Current**: Describes per-session IME engine, pane sharing, detach preservation, session restore with engine creation
- **After**: Keep: `active_input_method` and `active_keyboard_layout` fields in AttachSessionResponse. Remove server-internal engine lifecycle
- **Rationale**: Wire fields are protocol; engine lifecycle is daemon

### 16. doc 04 §3.2 — Remove frame suppression implementation

- **Current**: "When server suppresses FrameUpdate due to undersized pane dimensions, PTY MUST continue operating normally"
- **After**: Keep: "Server MAY suppress FrameUpdate for undersized panes." Remove PTY independence guarantee (daemon internal)
- **Rationale**: Whether to send FrameUpdate is observable behavior; PTY handling is daemon

### 17. doc 04 §8.3 — Remove event-driven coalescing details

- **Current**: 16ms minimum interval, triggered by PTY output/preedit, idle suppression
- **After**: Reference doc 01's reduced coalescing description. Remove duplication
- **Rationale**: Same as change 6; also removes cross-doc duplication

### 18. doc 05 §6.1-6.4 — Reduce preedit ownership to wire messages

- **Current**: Full ownership model (single-owner, concurrent attempt handling, 30s timeout, owner disconnect)
- **After**: Keep: PreeditEnd reason enums (`replaced_by_other_client`, `timeout`, `client_disconnected`). Remove server-side ownership algorithm
- **Rationale**: Protocol defines reasons; daemon defines ownership policy

### 19. doc 05 §7.4, §7.7 — Reduce preedit state-change handling

- **Current**: Detailed server behavior for focus change, alternate screen, pane close
- **After**: Keep: PreeditEnd reasons (`focus_changed`, `committed`, `pane_closed`). Remove "server MUST commit to PTY" details
- **Rationale**: Protocol defines what messages appear; daemon defines internal handling

### 20. doc 05 §8 — Remove preedit latency rules

- **Current**: "Server MUST write frame to ring buffer immediately", "MUST deliver within 33ms", bypasses power throttling
- **After**: Keep: "Preedit state changes are delivered with minimal latency." Remove ring buffer, 33ms target, power state details
- **Rationale**: Observable behavior (low latency) vs implementation mechanism

### 21. doc 06 §2.1-2.9 — Reduce flow control to wire messages

- **Current**: Ring buffer architecture (2MB, per-client cursors), PausePane/ContinuePane semantics, health escalation timeline, stale triggers, FlowControlConfig parameters
- **After**: Keep: PausePane/ContinuePane/FlowControlConfig message definitions and field tables. Remove: ring buffer sizing, cursor management algorithm, health timeline (T=0→300s), stale trigger conditions
- **Rationale**: Message formats are protocol; ring buffer architecture and health state machine are daemon

### 22. doc 06 §4.4-4.5 — Reduce session persistence to wire messages

- **Current**: IME engine restoration from saved input_method, composition state not restored, snapshot management
- **After**: Keep: RestoreSessionResponse/SnapshotListRequest message fields. Remove engine reconstruction and persistence implementation
- **Rationale**: Message formats are protocol; persistence implementation is daemon

### 23. doc 06 §6 — Reduce notification defaults to protocol behavior

- **Current**: Lists which notifications are auto-subscribed vs explicit
- **After**: Keep this — it IS wire-observable protocol behavior (client receives these without subscribing). Add note: "Subscription management implementation is server-side"
- **Rationale**: This one is borderline; the auto-subscription list IS part of the protocol contract

## Summary Table

| Target Doc | Section | Change Type | Daemon Review Note Ref |
|-----------|---------|-------------|----------------------|
| doc 01 | §2.1 (auto-start) | Remove procedure, keep transport def | P1 |
| doc 01 | §2.1 (FD passing) | Remove entirely | P2 |
| doc 01 | §3.4 (heartbeat) | Remove policy, keep message def | P19 |
| doc 01 | §5.5 (eviction timeout) | Remove timing, keep disconnect reason | P7 |
| doc 01 | §5.5.3 (connection limits) | Remove number, keep error code ref | P3 |
| doc 01 | §5.6 (resize policy) | Remove internal tracking | P4 |
| doc 01 | §10 (coalescing) | Remove tiers/timing, keep observable | P10 |
| doc 01 | §12.1 (auth) | Remove syscalls/permissions | P5 |
| doc 02 | §9.6 (preedit exclusivity) | Remove ownership algorithm | P11 |
| doc 02 | §9.9 (hysteresis) | Remove entirely | P4 |
| doc 02 | §11.2 (reconnection) | Remove procedure | P6 |
| doc 03 | §1.9, §2.5 (pane close) | Remove SIGHUP/PTY/reflow | P14 |
| doc 03 | §2.7 (focus preedit) | Remove PTY flush detail | P12 |
| doc 03 | §5.4 (resize) | Remove ioctl/debounce | P14 |
| doc 03 | §8 (input method) | Remove engine lifecycle | P17 |
| doc 04 | §3.2 (suppression) | Remove PTY guarantee | P15 |
| doc 04 | §8.3 (coalescing) | Remove, reference doc 01 | P10 |
| doc 05 | §6.1-6.4 (ownership) | Remove algorithm, keep reasons | P11 |
| doc 05 | §7.4, §7.7 (state changes) | Remove PTY details, keep reasons | P12 |
| doc 05 | §8 (latency) | Remove timing/ring/power | P10 |
| doc 06 | §2.1-2.9 (flow control) | Remove ring/health/stale | P7, P8, P9 |
| doc 06 | §4.4-4.5 (persistence) | Remove engine/snapshot impl | P17 |
| doc 06 | §6 (notifications) | Keep (protocol behavior), add note | P18 |
