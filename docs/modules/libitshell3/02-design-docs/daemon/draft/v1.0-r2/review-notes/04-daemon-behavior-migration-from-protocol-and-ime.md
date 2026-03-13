# Daemon Behavior Migration from Protocol and IME Documents

**Date**: 2026-03-10
**Raised by**: owner
**Severity**: HIGH
**Affected docs**: All daemon v0.2 docs (01, 02, 03) + potentially new docs
**Status**: open

---

## Problem

When the protocol and IME contract documents were written, no daemon design documents existed. As a result, daemon-side behavior — process management, IME integration, flow control policies, multi-client management — was described in protocol and IME contract docs by necessity. Now that daemon design docs exist (v0.2: 01-internal-architecture, 02-integration-boundaries, 03-lifecycle-and-connections), this content should be migrated to daemon docs. The protocol and IME contract docs should retain only wire format definitions, error codes, message types, and API contracts.

This is a large cross-team effort. The daemon team must absorb content from 6 protocol docs and 5 IME contract docs, deduplicate overlapping descriptions, and integrate them into the daemon design document set. Corresponding cross-team requests have been filed for protocol (v0.11) and IME contract (v0.7) to remove or reduce the migrated content from their docs.

## Analysis

### Scale of Migration

- **Protocol → Daemon**: 20 topics across all 6 protocol docs
- **IME Contract → Daemon**: 9 topics across 5 IME contract docs
- **AGENTS.md → Daemon**: 2 topics (version conflict handling)
- **Deduplication**: 8 topics are described in 2-3 sources and must be consolidated

### Content to Migrate from Protocol Docs

#### Process Management & Lifecycle

| ID | Source | Content |
|----|--------|---------|
| P1 | doc 01 §2.1 | **Daemon auto-start**: launchd socket activation (macOS), fork/exec (Linux), stale socket cleanup, exponential backoff reconnection (100ms, 200ms, 400ms...10s max, 5 failures → user notification) |
| P2 | doc 01 §2.1 | **Crash recovery**: PTY master FD passing via `sendmsg(2)`/`SCM_RIGHTS` from surviving daemon to reconnecting client |
| P3 | doc 01 §5.5.3 | **Connection limits**: daemon MAY impose limits, SHOULD support ≥256 concurrent connections, reject with ERR_RESOURCE_EXHAUSTED |
| P5 | doc 01 §12.1 | **Unix socket auth**: `getpeereid()`/`SO_PEERCRED` UID check, socket permissions 0600, directory 0700 |
| P6 | doc 02 §11.2 | **Reconnection procedure**: full state resync via I-frame, no incremental replay, new client_id on each connect |
| P19 | doc 01 §3.4 | **Heartbeat policy**: server-initiated, keep-alive interval |

#### Multi-Client Management

| ID | Source | Content |
|----|--------|---------|
| P4 | doc 01 §5.6, doc 02 §9.6, §9.9 | **Resize policy**: latest vs smallest, `latest_client_id` tracking (updated on KeyEvent/WindowResize), fallback on detach, stale re-inclusion 5s hysteresis, viewport clipping under latest policy |
| P7 | doc 01 §5.5, doc 06 §2.8-2.9 | **Health escalation timeline**: T=0s PausePane → T=5s resize exclusion → T=60s stale (local) / T=120s stale (SSH) → T=300s eviction via `Disconnect("stale_client")`. Stale triggers: cursor stagnation >90%, reset conditions (ContinuePane, FrameUpdate, request messages — NOT HeartbeatAck) |

#### Flow Control & Ring Buffer

| ID | Source | Content |
|----|--------|---------|
| P8 | doc 06 §2.4-2.7 | **Flow control**: PausePane as advisory signal (ring writes unconditionally), ContinuePane recovery (cursor advance to latest I-frame), FlowControlConfig parameters (max_queue_age_ms, auto_continue, stale_timeout_ms, eviction_timeout_ms), transport-aware server defaults |
| P9 | doc 06 §2.1, §2.3 | **Ring buffer architecture**: per-pane shared ring (2MB), per-client read cursors, I/P-frame storage, keyframe interval 1s, single serialization per pane per frame interval |

#### Frame Generation & Coalescing

| ID | Source | Content |
|----|--------|---------|
| P10 | doc 01 §10, doc 04 §8.3 | **Event-driven coalescing**: 16ms minimum interval, triggered by PTY output or preedit changes (not fixed timer), idle suppression (0-30 updates/sec typical), preedit tier = immediate (0ms), WAN adaptation based on transport_type/bandwidth_hint, preedit bypasses power throttling |
| P15 | doc 04 §3.2 | **Frame suppression**: when cols<2 or rows<1, suppress FrameUpdate but PTY continues (TIOCSWINSZ reflects actual size, I/O uninterrupted) |

#### IME/Preedit (Server-Side Behavior)

| ID | Source | Content |
|----|--------|---------|
| P11 | doc 02 §9.6, doc 05 §6.1-6.4 | **Preedit ownership**: single-owner per session, concurrent attempt → commit first client's preedit + `PreeditEnd(reason=replaced_by_other_client)` + start new session for second client, 30s inactivity timeout → commit |
| P12 | doc 05 §7.4, §7.7, doc 03 §2.7 | **Preedit lifecycle on state changes**: focus change → flush/commit before processing, alternate screen switch → commit before switch, pane close → cancel (do NOT commit), owner disconnect → commit |
| P13 | doc 05 cross-ref | **Preedit on eviction**: commit active preedit, `PreeditEnd(reason=client_evicted)` to peer clients |

#### PTY & Layout

| ID | Source | Content |
|----|--------|---------|
| P14 | doc 03 §2.5, §5.4 | **PTY lifecycle**: auto-close on process exit (SIGHUP), TIOCSWINSZ resize + debounce, parent split node replaced by sibling on close |
| P16 | doc 03 §3 | **Layout enforcement**: tree depth limit 16, server-side validation |
| P20 | doc 03 §4.2 | **Pane metadata tracking**: OSC title sequences, shell integration CWD, foreground process changes, process exit detection |

#### Session Persistence & Notifications

| ID | Source | Content |
|----|--------|---------|
| P17 | doc 06 §4.4-4.5 | **Session persistence**: snapshot management, IME engine restore (create per-session engine from saved `input_method` string), composition state NOT restored (flushed on shutdown), `input_method` + `keyboard_layout` persisted at session level |
| P18 | doc 06 §6 | **Notification defaults**: after AttachSession, client auto-receives LayoutChanged, SessionListChanged, ClientAttached/Detached/HealthChanged without subscription; Section 5 notifications require explicit subscription |

### Content to Migrate from IME Contract Docs

#### Key Routing Architecture

| ID | Source | Content |
|----|--------|---------|
| I1 | 01-overview §53-104 | **3-phase key pipeline**: Phase 0 (global shortcuts, CapsLock language toggle) → Phase 1 (IME processKey) → Phase 2 (ghostty integration: PTY write, key encode, preedit overlay) |
| I2 | 01-overview §106-114 | **IME-before-keybindings rationale**: why daemon calls IME before ghostty keybinding check |
| I3 | 01-overview §142-178 | **Responsibility matrix (daemon side)**: active input method switching, keybinding interception, ghostty API calls, terminal escape encoding, PTY writes, FrameUpdate sending, remote client preedit delivery, per-session engine lifecycle, routing ImeResult to correct pane, new pane input method inheritance, language indicator |

#### ghostty Integration

| ID | Source | Content |
|----|--------|---------|
| I4 | 04-ghostty §7-313 | **ImeResult → ghostty API mapping**: `handleKeyEvent()` pseudocode, key encoder integration, press+release pairs, HID→platform keycode mapping (Layer 1), macOS/iOS IME suppression (client-side) |
| I4a | 04-ghostty §183-187 | **Critical rule**: daemon MUST call `ghostty_surface_preedit(null, 0)` when preedit ends |
| I4b | 04-ghostty §236-248 | **Critical rule**: NEVER use `ghostty_surface_text()` for IME output (bracketed paste bug from it-shell v1) |

#### Engine Lifecycle & Session Integration

| ID | Source | Content |
|----|--------|---------|
| I5 | 03-engine §24-48, design-resolutions R1-R8 | **Per-session engine lifecycle**: one engine per session, activate on session focus, deactivate on unfocus (MUST flush), flush on intra-session pane focus change, shared engine memory ownership, engine is pane-agnostic, new pane inherits session's input method |
| I6 | 04-ghostty §122-157 | **Focus change handling**: intra-session pane focus change → flush engine → preserve language state → continue with same engine |

#### Persistence & API

| ID | Source | Content |
|----|--------|---------|
| I7 | 05-extensibility §125-160 | **Session persistence (IME)**: save `input_method` + `keyboard_layout`, preedit flush-on-save, engine reconstruction on restore from canonical string |
| I8 | 05-extensibility §72-122 | **C API boundary**: libitshell3-ime has no public C API, only `libitshell3.h` is public, clients receive preedit via protocol callbacks |
| I9 | 02-types §69-71 | **Wire-to-KeyEvent decomposition**: protocol modifier bitmask → KeyEvent fields, CapsLock/NumLock omitted (Phase 0 handles CapsLock as language toggle) |

### Content to Migrate from AGENTS.md

| ID | Source | Content |
|----|--------|---------|
| A1 | line 54 | **Local version conflict**: `server_version` differs from bundled binary → client kills daemon and restarts with bundled version |
| A2 | line 54 | **Remote version conflict**: `protocol_version` min/max negotiation fails → client exits with error |

### Deduplication Map

These topics appear in multiple sources and must be consolidated into a single daemon description:

| Topic | Sources | Notes |
|-------|---------|-------|
| Preedit flush on focus change | P12 + I6 | doc 03 §2.7, doc 05 §7.7, IME 04-ghostty §122-157 — three descriptions of same behavior |
| Per-session IME engine lifecycle | P11/P12 + I5 | doc 05 §6/§9.2, IME design-resolutions R1-R8 — ownership model + lifecycle |
| Session persistence (IME state) | P17 + I7 | doc 06 §4.4, IME 05-extensibility §125-160 — same save/restore flow |
| Preedit on pane close | P12 + I5/I6 | doc 05 §6.5, relates to engine lifecycle |
| Version conflict handling | P6 + A1/A2 | doc 02 §11.2, AGENTS.md — reconnection + version mismatch recovery |
| Multi-client preedit ownership | P11 (two sources) | doc 02 §9.6 + doc 05 §6.1-6.4 — same ownership model in two protocol docs |
| Stale eviction + preedit cleanup | P7 + P13 | doc 06 §2.8 + doc 05 cross-ref — health escalation + preedit commit on eviction |
| Coalescing + preedit immediate | P10 (two sources) | doc 01 §10, doc 04 §8.3, doc 05 §8 — same immediate-flush rule in three places |

## Proposed Change

The daemon v0.3 revision should:

1. **Absorb** all P1-P20, I1-I9, A1-A2 content into daemon design docs (existing or new)
2. **Deduplicate** the 8 overlapping topics into single authoritative descriptions
3. **Update AGENTS.md** line 54 to remove version conflict procedures, keep high-level summary only
4. **Coordinate** with protocol team (cross-team request filed at `protocol/draft/v1.0-r11/cross-team-requests/`) and IME team (cross-team request filed at `ime-contract/draft/v1.0-r7/cross-team-requests/`) to reduce their docs to wire format / API contract only

Daemon docs may need new sections or a new document (e.g., doc 04) to accommodate flow control, multi-client management, and IME integration topics that don't fit cleanly into the current three docs.

## Owner Decision

Proceed as described. This will be a full-team revision cycle for daemon v0.3, with parallel cross-team coordination for protocol v0.11 and IME contract v0.7.

## Resolution

