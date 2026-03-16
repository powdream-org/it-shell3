# Protocol v1.0-r12 Owner Review Cleanup TODO

- **Date**: 2026-03-16
- **Scope**: Systematic extraction of non-protocol content from Doc 01-06

---

## Guiding Principle

**Protocol docs define wire format, not server behavior.** The test: "Would a
protocol-only implementor (someone writing a compatible client without access to
our server source) need this information?" If no, it doesn't belong here.

Content types to extract:

- **Design decision / rationale** → ADR (new or existing)
- **Server/daemon internals** → Daemon docs (via CTR)
- **IME behavior / architecture** → IME docs (via CTR)
- **Already covered elsewhere** → Delete with optional cross-ref

After extraction, each removed paragraph is replaced by either nothing (if the
normative wire fact is already stated elsewhere in the same doc) or a single
cross-reference sentence.

### CTR Writing Convention

Every CTR (daemon or IME) MUST include a **"Reference: Original Protocol Text"**
section containing the verbatim text removed from the protocol spec. This
ensures the target team receives the full content for 100% lossless transfer.
Pattern: see existing CTRs at `daemon/draft/v1.0-r5/cross-team-requests/04-*.md`
and `05-*.md`.

Required CTR structure:

```markdown
# <Title>

- **Date**: YYYY-MM-DD
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: <daemon design docs | IME behavior docs | IME interface
  contract>
- **Status**: open

## Context

<Why this content is being moved; what gap or duplication existed>

## Required Changes

<Numbered list of what the target team should add/update>

## Summary Table

<Target Doc | Section/Message | Change Type | Source Resolution>

## Reference: Original Protocol Text (removed from Doc XX §Y)

<Verbatim copy of the removed protocol text, preserving all formatting, tables,
code blocks, and mermaid diagrams. Multiple sections grouped under sub-headings
if from different source locations.>
```

---

## Legend

- **DEL-ADR-exist**: Delete — already covered by existing ADR
- **DEL-ADR-absorb**: Absorb into existing ADR, then delete
- **DEL-ADR-new**: Create new ADR, then delete
- **DEL-daemon-CTR**: Write daemon CTR, then delete
- **DEL-ime-CTR**: Write IME CTR, then delete
- **DEL-covered**: Already 100% covered by daemon/IME docs — just delete
- **DEL**: Just delete (non-normative, no destination needed)
- **MOVE**: Move verbatim to a standalone document outside protocol specs
- **REWRITE**: Rewrite to wire-observable facts only (remove
  rationale/internals)

---

## New ADR Index (00019-00033)

| ADR #     | Topic                                                                            |
| --------- | -------------------------------------------------------------------------------- |
| 00019     | Per-session focus model (v1)                                                     |
| 00020     | Session attachment model (single-per-connection, readonly, exclusive)            |
| 00021     | Preedit single-path rendering model                                              |
| 00022     | Server-owned scrollback (no client cache)                                        |
| 00023     | Message ordering and delivery guarantees (context before content)                |
| 00024     | Capability negotiation mechanics (string arrays, set intersection)               |
| 00025     | Input method identifier design (two-axis, string IDs, two-channel state)         |
| 00026     | Preedit lifecycle on interrupting events                                         |
| 00027     | Pane lifecycle (auto-close, auto-unzoom, remain-on-exit deferred)                |
| 00028     | Two-layer error handling model                                                   |
| 00029     | Notification subscription model (always-sent vs opt-in)                          |
| 00030     | Adaptive coalescing and flow control                                             |
| 00031     | Session persistence model (hybrid memory + JSON snapshots)                       |
| 00032     | Preedit message simplification (field removals, frame_type=2)                    |
| ~~00033~~ | ~~Protocol wire conventions~~ — **EXCLUDED**: content stays in protocol overview |
| 00034     | Per-connection handshake (no lightweight reconnect optimization in v1)           |

---

## File 1: Doc 01 — Protocol Overview

### 1a. ADRs to write (first occurrence in processing order)

| ADR # | Topic                                                                  | Content from this file                                                                                                              |
| ----- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 00020 | Session attachment model                                               | §5.2: single-session-per-connection rule, "matches tmux behavior"; §5.5.5: tmux precedent (same one-connection-per-session pattern) |
| 00034 | Per-connection handshake (no lightweight reconnect optimization in v1) | §5.5.4: sub-ms overhead, optimization deferred                                                                                      |

### 1b. Standalone document extraction

| Source                        | Lines   | Target                                 | Description                                 |
| ----------------------------- | ------- | -------------------------------------- | ------------------------------------------- |
| §8 Comparison tables (entire) | 939-980 | `docs/insights/protocol-comparison.md` | Move §8 verbatim to standalone insights doc |

### 1c. Daemon CTRs to write (first occurrence)

| CTR #  | Topic                                                 | Content from this file                                                                                                                                |
| ------ | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-06 | Ring buffer architecture and I-frame scheduling       | §5.8: per-pane ring, client cursors, sizing                                                                                                           |
| CTR-07 | Health escalation and recovery procedures             | §5.7: timeline, timeout values                                                                                                                        |
| CTR-08 | Coalescing tier internals and client power adaptation | §10: tier definitions, WAN adaptation                                                                                                                 |
| CTR-09 | Authentication implementation                         | §2.2 (getpeereid), §12.1 (Unix socket auth), §12.2 (SSH trust chain), §12.3 (timeout values)                                                          |
| CTR-12 | Server-side IME engine lifecycle                      | §5.5 lines 717-725 only: per-session engine, libhangul memory cost, preedit exclusivity, per-session locking (rest of §5.5 is wire-observable, stays) |

### 1d. Cleanup items

| #  | Section                                   | Lines     | Action         | Target              | Description                                   |
| -- | ----------------------------------------- | --------- | -------------- | ------------------- | --------------------------------------------- |
| 1  | §1.1 Goals table "Rationale" column       | 13-19     | DEL-ADR-exist  | ADR 00005-00009     | Goal rationale explanations                   |
| 2  | §1.2 Principle 1 (hybrid encoding)        | 23-31     | DEL-ADR-exist  | ADR 00006           | "for debuggability, schema evolution"         |
| 3  | §1.2 Principle 2 (server-authoritative)   | 33-38     | DEL-ADR-exist  | ADR 00013           | Philosophy paragraph                          |
| 4  | §1.2 Principle 3 (capability negotiation) | 40-42     | DEL-ADR-new    | ADR 00024           | "No fragile version-string parsing"           |
| 5  | §1.2 Principle 8 (semantic CellData)      | 62-67     | DEL-ADR-exist  | ADR 00007           | "Zero-copy wire-to-GPU is not a design goal"  |
| 6  | §2.1 Daemon auto-start                    | 106-109   | DEL-covered    | Daemon 03-lifecycle | Auto-start details                            |
| 7  | §2.2 SSH tunnel decision                  | 137-143   | DEL-ADR-exist  | ADR 00010           | "Custom TCP+TLS rejected"                     |
| 8  | §2.2 Security trust model                 | 131-135   | DEL-daemon-CTR | CTR-09              | getpeereid() UID verification                 |
| 9  | §3.3 Encoding flag rationale              | 215-217   | DEL-ADR-exist  | ADR 00006           | "clean split"                                 |
| 10 | §3.5 Compression decision                 | 291-294   | DEL-ADR-exist  | ADR 00014           | "removed from v1"                             |
| 11 | §5.2 Single-session rule                  | 617-621   | DEL-ADR-new    | ADR 00020           | "matches tmux" rationale                      |
| 12 | §5.4 Heartbeat RTT rejection              | 688-694   | DEL-ADR-exist  | ADR 00011           | "RTT via heartbeat rejected"                  |
| 13 | §5.5 IME state bullet only                | 717-725   | DEL-daemon-CTR | CTR-12              | Per-session engine, libhangul memory, locking |
| 14 | §5.5.4 Handshake overhead rationale       | 765-775   | DEL-ADR-new    | ADR 00034           | Optimization deferred decision                |
| 15 | §5.5.5 Precedent: tmux                    | 777-783   | DEL-ADR-new    | ADR 00020           | tmux same pattern rationale                   |
| 16 | §5.6 Resize policy details                | 786-798   | DEL-covered    | Daemon 04-runtime   | Algorithm internals                           |
| 17 | §5.7 Health escalation                    | 800-817   | DEL-daemon-CTR | CTR-07              | Timeline, timeouts                            |
| 18 | §5.8 Ring buffer architecture             | 819-847   | DEL-daemon-CTR | CTR-06              | Ring, cursors, sizing                         |
| 19 | §8 Comparison tables (entire)             | 939-980   | DEL            | —                   | Moved to `docs/insights/` in step 1b          |
| 20 | §9 Bandwidth analysis (entire)            | 983-1027  | REWRITE        | —                   | Keep wire estimates; remove impl analysis     |
| 21 | §10 Coalescing tier details               | 1030-1048 | DEL-daemon-CTR | CTR-08              | Tier definitions, WAN adaptation              |
| 22 | §11 Implementation notes (entire)         | 1052-1102 | DEL            | —                   | Zig structs and pseudocode                    |
| 23 | §12.1 Unix socket auth impl               | 1108-1116 | DEL-daemon-CTR | CTR-09              | Syscall selection, permissions                |
| 24 | §12.2 SSH tunnel auth impl                | 1119-1134 | DEL-daemon-CTR | CTR-09              | Trust chain, sshd UID                         |
| 25 | §12.3 Handshake timeout values            | 1136-1143 | DEL-daemon-CTR | CTR-09              | 5s/60s/90s durations                          |
| 26 | Appendix C Encoding rationale             | 1256-1277 | DEL-ADR-exist  | ADR 00006           | "What killed uniform binary"                  |

---

## File 2: Doc 06 — Flow Control & Auxiliary

### 2a. ADRs to write (first occurrence)

| ADR # | Topic                                    | Content from this file                                                     |
| ----- | ---------------------------------------- | -------------------------------------------------------------------------- |
| 00023 | Message ordering and delivery guarantees | §2.3: socket write priority model ("context before content")               |
| 00030 | Adaptive coalescing and flow control     | §2.4: PausePane advisory rationale; §7.3: idle-PTY blind spot + mitigation |
| 00031 | Session persistence model                | §4.1: hybrid memory + periodic JSON snapshots, 8s auto-save                |

### 2a′. ADRs to add content to (already created in earlier file)

| ADR # | Content from this file                                     |
| ----- | ---------------------------------------------------------- |
| 00024 | §8.1: "avoid fragile version-guessing" extension rationale |

### 2b. Daemon CTRs to add content to (already created in File 1)

| CTR #  | Content from this file                                                                |
| ------ | ------------------------------------------------------------------------------------- |
| CTR-06 | §2.1 (ring buffer background), §2.3 (two-channel mechanism), §2.5 (ring cursor reset) |
| CTR-07 | §2.8 (health escalation refs), §2.9 (recovery wire behavior)                          |
| CTR-08 | §1.1 (coalescing background)                                                          |

### 2b′. Daemon CTRs to write (first occurrence)

| CTR #  | Topic                     | Content from this file                             |
| ------ | ------------------------- | -------------------------------------------------- |
| CTR-10 | Session restore procedure | §4.6: snapshot reading, pane creation, IME re-init |

### 2c. Cleanup items

| #  | Section                               | Lines   | Action            | Target            | Description                         |
| -- | ------------------------------------- | ------- | ----------------- | ----------------- | ----------------------------------- |
| 1  | §1.1 Coalescing background            | 57-70   | DEL-daemon-CTR    | CTR-08            | Adaptive coalescing strategy        |
| 2  | §1.2 Design Note (client RTT)         | 109-115 | DEL-ADR-exist     | ADR 00011         | "why client self-reports RTT"       |
| 3  | §2.1 Ring buffer background           | 133-140 | DEL-daemon-CTR    | CTR-06            | "shared per-pane ring buffer"       |
| 4  | §2.3 Socket write priority model      | 147-161 | DEL-ADR-new + CTR | ADR 00023, CTR-06 | Decision + mechanism                |
| 5  | §2.4 PausePane advisory rationale     | 166-171 | DEL-ADR-new       | ADR 00030         | "advisory, does NOT stop"           |
| 6  | §2.5 ContinuePane ring cursor reset   | 193-206 | DEL-daemon-CTR    | CTR-06            | "advances cursor to latest I-frame" |
| 7  | §2.8 Health escalation refs           | 254-270 | DEL-daemon-CTR    | CTR-07            | Timeline, stale triggers            |
| 8  | §2.9 Recovery wire behavior (ring)    | 271-279 | DEL-daemon-CTR    | CTR-07            | "advancing ring cursor"             |
| 9  | §4.1 Persistence background           | 431-437 | DEL-ADR-new       | ADR 00031         | "hybrid persistence model"          |
| 10 | §4.5 RestoreSessionRequest procedure  | 475-481 | DEL-covered       | Daemon docs       | "creates new PTYs, spawns shells"   |
| 11 | §4.6 RestoreSessionResponse procedure | 523-536 | DEL-daemon-CTR    | CTR-10            | Snapshot reading, pane creation     |
| 12 | §7.1 Local RTT diagnostics            | 878-890 | DEL               | —                 | Explicitly "not wire protocol"      |
| 13 | §7.3 RTT heuristic                    | 927-929 | DEL               | —                 | Non-normative guidance              |
| 14 | §7.3 Idle-PTY blind spot              | 915-924 | DEL-ADR-new       | ADR 00030         | Design tradeoff                     |
| 15 | §8.1 Extension negotiation rationale  | 935-939 | DEL-ADR-new       | ADR 00024         | "avoid version-guessing"            |

---

## File 3: Doc 04 — Input & RenderState

### 3a. ADRs to write (first occurrence)

| ADR # | Topic                                     | Content from this file                                                   |
| ----- | ----------------------------------------- | ------------------------------------------------------------------------ |
| 00021 | Preedit single-path rendering model       | §3.2: no preedit section in JSON metadata, rendering path separation     |
| 00022 | Server-owned scrollback (no client cache) | §5.0: request/response model, §5.1: scroll broadcast to all clients      |
| 00025 | Input method identifier design            | §2.1: string identifier rationale ("self-documenting, no mapping table") |

### 3a′. ADRs to add content to (already created)

| ADR # | Content from this file                                      |
| ----- | ----------------------------------------------------------- |
| 00009 | §3.1: per-pane delivery rationale ("not just focused pane") |

### 3b. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                                     |
| ------ | -------------------------------------------------------------------------- |
| CTR-06 | §3.1 (ring buffer / coalescing tiers), §3.1 (I-frame scheduling algorithm) |
| CTR-12 | §2.1 (server IME processing: "derives text through native IME engine")     |

### 3c. IME CTRs to write (first occurrence)

| Target                 | CTR #  | Topic                                      | Content from this file                        |
| ---------------------- | ------ | ------------------------------------------ | --------------------------------------------- |
| IME behavior           | CTR-01 | Preedit lifecycle details                  | §2.1: Jamo decomposition note                 |
| IME interface-contract | CTR-01 | Engine decomposition and per-session state | §2.1: "decomposed into engine-specific types" |

### 3d. Cleanup items

| #  | Section                                | Lines     | Action         | Target         | Description                              |
| -- | -------------------------------------- | --------- | -------------- | -------------- | ---------------------------------------- |
| 1  | §2.1 Server IME processing             | 41-45     | DEL-daemon-CTR | CTR-12         | "derives text through native IME engine" |
| 2  | §2.1 Jamo decomposition note           | 94        | DEL-ime-CTR    | IME-beh CTR-01 | "Critical for Jamo decomposition"        |
| 3  | §2.1 String identifier rationale       | 116-119   | DEL-ADR-new    | ADR 00025      | "self-documenting, no mapping table"     |
| 4  | §2.1 Engine decomposition              | 121-126   | DEL-ime-CTR    | IME-ic CTR-01  | "decomposed into engine-specific types"  |
| 5  | §3.1 CellData normative note (ghostty) | 304-315   | REWRITE        | —              | Remove function names; keep generic      |
| 6  | §3.1 Per-pane delivery rationale       | 317-321   | DEL-ADR-absorb | ADR 00009      | "not just focused pane"                  |
| 7  | §3.1 Ring buffer / coalescing tiers    | 323-329   | DEL-daemon-CTR | CTR-06         | Server architecture                      |
| 8  | §3.1 Server renderer minimum           | 363-364   | DEL-covered    | Daemon docs    | "renderer's practical minimum"           |
| 9  | §3.1 PTY behavior during suppression   | 366-368   | DEL-covered    | Daemon docs    | "defined in daemon design docs"          |
| 10 | §3.1 I-frame scheduling algorithm      | 1040-1047 | DEL-daemon-CTR | CTR-06         | Timer, ring buffer, interval             |
| 11 | §3.2 No preedit in JSON metadata       | 498-510   | DEL-ADR-new    | ADR 00021      | Rendering path separation                |
| 12 | §7.3 Coalescing tier deferral          | 1036-1038 | DEL-covered    | Daemon docs    | "defined in daemon design docs"          |
| 13 | §7.4 PoC performance measurements      | 1051-1072 | DEL            | —              | Move to PoC docs or delete               |
| 14 | §8 Compression deferral (entire)       | 1076-1092 | DEL-ADR-exist  | ADR 00014      | One-liner cross-ref                      |
| 15 | Appendix C Encoding rationale          | 1256-1277 | DEL-ADR-exist  | ADR 00006      | Duplicate                                |

---

## File 4: Doc 05 — CJK Preedit Protocol

### 4a. ADRs to write (first occurrence)

| ADR # | Topic                                    | Content from this file                                                                                                                                                                                                                                 |
| ----- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 00026 | Preedit lifecycle on interrupting events | §6.1-6.10 (all decisions: pane close cancels, disconnect commits, focus change commits, mouse button commits/scroll preserves, IME switch commit_current, Escape commits, daemon restart commits); §8.2-8.3 (commit-on-restore, resume deferred to v2) |
| 00032 | Preedit message simplification           | §2.2/2.4 changes-from (remove composition_state, cursor/width; retain text for multi-client coordination; remove frame_type=2)                                                                                                                         |

### 4a′. ADRs to add content to (already created)

| ADR # | Content from this file                                                                                |
| ----- | ----------------------------------------------------------------------------------------------------- |
| 00021 | §1.1 (preedit as cell data rationale, capability decoupling), §13.1 (single-path rendering rationale) |
| 00023 | §13.2 (message ordering, "context before content principle")                                          |

### 4b. Daemon CTRs to write (first occurrence)

| CTR #  | Topic                                  | Content from this file                                                                                                                                    |
| ------ | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-11 | Preedit race condition server behavior | §6.1-6.10: server-side cancel/commit procedures, hotkey detection, resize repositioning, keystroke coalescing; §10.1: error handling (log, commit, reset) |

### 4b′. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                                                                  |
| ------ | ------------------------------------------------------------------------------------------------------- |
| CTR-08 | §7: preedit delivery latency, coalescing bypass                                                         |
| CTR-12 | §3.1 (setActiveInputMethod, locking), §3.3 (per-session state), §8.2 (engine initialization on restore) |

### 4c. IME CTRs to add content to (already created in File 3)

| Target                 | CTR #  | Content from this file                                                 |
| ---------------------- | ------ | ---------------------------------------------------------------------- |
| IME behavior           | CTR-01 | §2.3: Escape behavior rationale ("matches ibus-hangul, fcitx5-hangul") |
| IME interface-contract | CTR-01 | §1.1 (HangulInputContext, jamo stack), §3.3 (per-session engine state) |

### 4d. Cleanup items

| #  | Section                                       | Lines     | Action            | Target            | Description                          |
| -- | --------------------------------------------- | --------- | ----------------- | ----------------- | ------------------------------------ |
| 1  | §1.1 Server owns IME                          | 176-181   | DEL-ADR-exist     | ADR 00013         | "server owns native IME engine"      |
| 2  | §1.1 Preedit as cell data rationale           | 183-186   | DEL-ADR-new       | ADR 00021         | Dual-path design rationale           |
| 3  | §1.1 Preedit capability decoupling            | 197-203   | DEL-ADR-new       | ADR 00021         | "controls lifecycle only"            |
| 4  | §1.1 Preedit exclusivity + HangulInputContext | 223-230   | DEL-ime-CTR       | IME-ic CTR-01     | "one HangulInputContext"             |
| 5  | §2.3 Escape behavior rationale                | 346-350   | DEL-ADR-new       | ADR 00026         | "matches ibus-hangul"                |
| 6  | §3.1 Server hotkey detection                  | 433-436   | DEL-daemon-CTR    | CTR-11            | "detects mode-switch hotkeys"        |
| 7  | §3.1 Server impl (setActiveInputMethod)       | 444-452   | DEL-daemon-CTR    | CTR-12            | Internal API calls, locking          |
| 8  | §3.3 Per-session engine state                 | 495-499   | DEL-ADR-exist     | ADR 00013         | "one IME engine per session"         |
| 9  | §5.1 Problem statement framing                | 570-594   | REWRITE           | —                 | Keep reason values; remove framing   |
| 10 | §6.1 Pane close — cancel behavior             | 604-616   | DEL-ADR-new + CTR | ADR 00026, CTR-11 | Decision + server procedure          |
| 11 | §6.2 Disconnect — commit rationale            | 625       | DEL-ADR-new       | ADR 00026         | "preserve user's work"               |
| 12 | §6.3 Resize — repositioning                   | 641-650   | DEL-daemon-CTR    | CTR-11            | "repositions internally"             |
| 13 | §6.4 Screen switch — PTY commit ref           | 662       | DEL-covered       | Daemon docs       | "defined in daemon docs"             |
| 14 | §6.5 Rapid keystrokes — coalescing            | 676-685   | DEL-daemon-CTR    | CTR-11            | Coalescing algorithm                 |
| 15 | §6.7 Focus change — commit                    | 697-706   | DEL-ADR-new + CTR | ADR 00026, CTR-11 | Decision + procedure                 |
| 16 | §6.8 Session detach — commit                  | 723       | DEL-ADR-new       | ADR 00026         | "preserve user's work"               |
| 17 | §6.9 IME switch — hotkey note                 | 755-758   | DEL-daemon-CTR    | CTR-11            | "hotkey detection path"              |
| 18 | §6.10 Mouse-preedit rationale                 | 791-794   | DEL-ADR-new       | ADR 00026         | "Button commits, Scroll preserves"   |
| 19 | §7 Delivery latency (entire)                  | 798-807   | DEL-daemon-CTR    | CTR-08            | Coalescing bypass, latency           |
| 20 | §8.2 Restore — engine init                    | 859-864   | DEL-daemon-CTR    | CTR-12            | "creates one HangulImeEngine"        |
| 21 | §8.2 Restore — commit rationale               | 852-857   | DEL-ADR-new       | ADR 00026         | "client no longer connected"         |
| 22 | §8.3 Resume composition (future)              | 866-879   | DEL-ADR-new       | ADR 00026         | Deferred to v2; add to 99-post-v1    |
| 23 | §9.1 Server rendering details                 | 891-893   | REWRITE           | —                 | Keep disclaimer; remove examples     |
| 24 | §9.2 Observer UI features                     | 920-934   | REWRITE           | —                 | Keep wire fields; remove UI guidance |
| 25 | §10.1 Invalid composition error handling      | 940-949   | DEL-daemon-CTR    | CTR-11            | "Log, commit, reset"                 |
| 26 | §12 Bandwidth analysis (entire)               | 1015-1044 | DEL               | —                 | Non-normative                        |
| 27 | §13.1 Single-path rendering rationale         | 1050-1055 | DEL-ADR-new       | ADR 00021         | Architecture explanation             |
| 28 | §13.1 Ring buffer interaction                 | 1073-1084 | DEL-daemon-CTR    | CTR-06            | Ring vs direct queue                 |
| 29 | §13.2 Message ordering                        | 1084-1095 | DEL-ADR-new       | ADR 00023         | "context before content"             |

---

## File 5: Doc 02 — Handshake & Capability Negotiation

### 5a. ADRs to write (first occurrence)

| ADR # | Topic                            | Content from this file                                                                 |
| ----- | -------------------------------- | -------------------------------------------------------------------------------------- |
| 00019 | Per-session focus model (v1)     | §8.9: viewport clipping (related); main content from Doc 03 §8.1                       |
| 00024 | Capability negotiation mechanics | §2.1 (string arrays over bitmasks), §7.2 (set intersection), §7.3 (render requirement) |

### 5a′. ADRs to add content to (already created)

| ADR # | Content from this file                                                                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------- |
| 00020 | §8.1 (single-session-per-connection), §8.6 (multi-client input ordering), §8.7 (readonly), §8.8 (exclusive/detach_others) |
| 00023 | §8.2 (direct message queue, priority 1)                                                                                   |
| 00025 | §5.3 (two-axis model, string identifiers, field naming asymmetry)                                                         |

### 5b. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                       |
| ------ | ------------------------------------------------------------ |
| CTR-06 | §8.6 (ring buffer / coalescing tiers)                        |
| CTR-08 | §6.2 (server coalescing behavior), §6.3 (iOS tier breakdown) |
| CTR-09 | §11.1 (auth ref), §11.3 (timeout values)                     |

### 5c. Cleanup items

| #  | Section                            | Lines     | Action         | Target              | Description                   |
| -- | ---------------------------------- | --------- | -------------- | ------------------- | ----------------------------- |
| 1  | §2.1 String capabilities rationale | 112-115   | DEL-ADR-new    | ADR 00024           | "Instead of bitmasks"         |
| 2  | §4.2 CELLDATA_ENCODING rationale   | 388-391   | DEL-ADR-absorb | ADR 00006           | "RLE outperforms protobuf"    |
| 3  | §5.3 Two-axis model explanation    | 421-430   | DEL-ADR-new    | ADR 00025           | Two-axis orthogonal           |
| 4  | §5.3 String identifier rationale   | 480-484   | DEL-ADR-new    | ADR 00025           | "self-documenting"            |
| 5  | §5.3 Field naming asymmetry        | 468-478   | DEL-ADR-new    | ADR 00025           | layout vs layouts             |
| 6  | §6.2 Design decision (client RTT)  | 533-536   | DEL-ADR-exist  | ADR 00011           | "client is the only entity"   |
| 7  | §6.2 Server coalescing behavior    | 522-531   | DEL-daemon-CTR | CTR-08              | Power throttling, fps cap     |
| 8  | §6.3 iOS example tier breakdown    | 551-558   | DEL-daemon-CTR | CTR-08              | Tier calculations             |
| 9  | §7.2 Set intersection semantics    | 582-588   | DEL-ADR-new    | ADR 00024           | "intersection of flag sets"   |
| 10 | §7.3 Render capability requirement | 596-601   | DEL-ADR-new    | ADR 00024           | "at least one mode required"  |
| 11 | §8.1 Single-session-per-connection | 685-688   | DEL-ADR-new    | ADR 00020           | "at most one session"         |
| 12 | §8.2 IME per-session rationale     | 716-721   | DEL-ADR-exist  | ADR 00013           | "IME engine is per-session"   |
| 13 | §8.2 Direct message queue          | 732-735   | DEL-ADR-new    | ADR 00023           | "priority 1" mechanism        |
| 14 | §8.6 Ring buffer / coalescing      | 876-879   | DEL-daemon-CTR | CTR-06              | "shared per-pane ring buffer" |
| 15 | §8.6 Preedit exclusivity ref       | 872-875   | REWRITE        | —                   | Keep wire fact; trim          |
| 16 | §8.6 Multi-client input ordering   | 870-871   | DEL-ADR-new    | ADR 00020           | "arrival order"               |
| 17 | §8.7 Readonly attach mode          | 886-902   | DEL-ADR-new    | ADR 00020           | Full readonly semantics       |
| 18 | §8.8 Exclusive attach              | 904-912   | DEL-ADR-new    | ADR 00020           | "detach_others = true"        |
| 19 | §8.9 Resize internals ref          | 925-926   | DEL-covered    | Daemon 04-runtime   | "defined in daemon docs"      |
| 20 | §8.9 Viewport clipping             | 921-923   | DEL-ADR-new    | ADR 00019           | Clipping vs scrolling         |
| 21 | §11.1 Auth implementation ref      | 1000-1001 | DEL-covered    | Daemon 03-lifecycle | "defined in daemon docs"      |
| 22 | §11.3 Handshake timeout values     | 1013-1017 | DEL-daemon-CTR | CTR-09              | Duration values               |

---

## File 6: Doc 03 — Session & Pane Management

### 6a. ADRs to write (first occurrence)

| ADR # | Topic                           | Content from this file                                                              |
| ----- | ------------------------------- | ----------------------------------------------------------------------------------- |
| 00027 | Pane lifecycle                  | §2.3 (auto-unzoom + preedit constraint), §2.5 (auto-close, remain-on-exit deferred) |
| 00028 | Two-layer error handling model  | §6: status codes vs Error message split                                             |
| 00029 | Notification subscription model | §4: always-sent session-scope notifications                                         |

### 6a′. ADRs to add content to (already created)

| ADR # | Content from this file                                                          |
| ----- | ------------------------------------------------------------------------------- |
| 00019 | §8.1: "Decision for v1: Per-session focus (like tmux)"                          |
| 00023 | §1.6 ("context before content" principle), §7 (sequence correlation + ordering) |
| 00025 | §2.1/2.3 (IME inheritance), §3.1 (two-channel IME state model)                  |

### 6b. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                 |
| ------ | -------------------------------------- |
| CTR-07 | §8.4 (health state + resize exclusion) |

### 6c. Cleanup items

| #  | Section                            | Lines     | Action         | Target            | Description                    |
| -- | ---------------------------------- | --------- | -------------- | ----------------- | ------------------------------ |
| 1  | §1.6 "context before content"      | 222-225   | DEL-ADR-new    | ADR 00023         | Principle reference            |
| 2  | §2.1 IME inheritance normative     | 445-447   | DEL-ADR-new    | ADR 00025         | "inherits active_input_method" |
| 3  | §2.3 IME inheritance (duplicate)   | 488-490   | DEL-ADR-new    | ADR 00025         | Same, in SplitPane             |
| 4  | §2.3 Auto-unzoom + preedit         | 492-495   | DEL-ADR-new    | ADR 00027         | "MUST unzoom"                  |
| 5  | §2.5 Auto-close + cascade          | 524-530   | DEL-ADR-new    | ADR 00027         | Remain-on-exit deferred        |
| 6  | §2.8 Preedit flush-to-PTY          | 580-583   | DEL-covered    | Daemon 04-runtime | "defined in daemon"            |
| 7  | §2.10 Navigation algorithm         | 606-609   | DEL-covered    | —                 | Delete; keep one-liner         |
| 8  | §3.1 Per-session engine invariant  | 780-784   | REWRITE        | —                 | Keep invariant only            |
| 9  | §3.1 Two-channel IME state model   | 786-806   | DEL-ADR-new    | ADR 00025         | Architecture explanation       |
| 10 | §4 Always-sent notifications       | 875-882   | DEL-ADR-new    | ADR 00029         | "no subscription required"     |
| 11 | §5.2 Resize policy rationale       | 1054-1059 | DEL-ADR-exist  | ADR 00012         | "See ADR 00012"                |
| 12 | §5.2 Resize algorithm internals    | 1071-1072 | DEL-covered    | Daemon 04-runtime | "debounce, stale exclusion"    |
| 13 | §6 Two-layer error model           | 1105-1112 | DEL-ADR-new    | ADR 00028         | Status codes vs Error          |
| 14 | §7 Sequence correlation + ordering | 1126-1146 | DEL-ADR-new    | ADR 00023         | Ordering guarantee             |
| 15 | §8.1 Per-session focus decision    | 1154-1158 | DEL-ADR-new    | ADR 00019         | "Decision for v1"              |
| 16 | §8.4 Health + resize exclusion     | 1186-1192 | DEL-daemon-CTR | CTR-07            | "Stale excluded from resize"   |

---

## Counts Summary

| Category                                         | Items                                              |
| ------------------------------------------------ | -------------------------------------------------- |
| DEL-ADR-exist (delete, already in ADR)           | ~18                                                |
| DEL-ADR-absorb (extend existing ADR, delete)     | ~3                                                 |
| DEL-ADR-new (write new ADR, delete)              | ~45                                                |
| DEL-daemon-CTR (write daemon CTR, delete)        | ~30                                                |
| DEL-ime-CTR (write IME CTR, delete)              | ~4                                                 |
| DEL-covered (already in daemon/IME docs, delete) | ~12                                                |
| DEL (just delete, non-normative)                 | ~6                                                 |
| REWRITE (trim to wire facts only)                | ~7                                                 |
| **Total items**                                  | **~125**                                           |
| **New ADRs**                                     | **15 (00019-00032, 00034; 00033 excluded)**        |
| **New daemon CTRs**                              | **7 (CTR-06 to CTR-12)**                           |
| **New IME CTRs**                                 | **2 (behavior CTR-01, interface-contract CTR-01)** |
