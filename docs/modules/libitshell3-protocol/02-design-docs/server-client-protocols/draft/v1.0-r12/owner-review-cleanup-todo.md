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

## File 1: Doc 01 — Protocol Overview ✅

All steps complete. Doc 01 reduced from ~1277 lines to ~878 lines.

- [x] 1a. ADRs written: 00020, 00034
- [x] 1b. `docs/insights/protocol-comparison.md` created from §8
- [x] 1c. Daemon CTRs written: CTR-06, CTR-07, CTR-08, CTR-09, CTR-12
- [x] 1d. 26 cleanup items applied (25 executed; #26 Appendix C already absent)

**Note**: Sections 8 and 11 deleted entirely → section numbering is now 1-7, 9,
10, 12. Renumbering deferred to final cross-doc consistency pass.

---

## File 2: Doc 06 — Flow Control & Auxiliary ✅

All steps complete.

- [x] 2a. ADRs written: 00023, 00030, 00031
- [x] 2b. ADR 00024 created with §8.1 extension rationale
- [x] 2c. CTR-06, CTR-07, CTR-08 extended with Doc 06 content
- [x] 2d. CTR-10 converted: session restore removal request (ADR 00036
      supersedes ADR 00031)
- [x] 2e. echo_nonce already covered in `99-post-v1-features.md` Section 4 — no
      changes needed
- [x] 2f. 16 cleanup items applied (14 executed; #7 and #11 already clean)
- [x] 2g. §11 Open Questions resolved and section deleted:
  - ADR 00035: Clipboard size limit (10 MB, Proposed — pending spec update)
  - ADR 00036: Snapshot/Restore deferred to post-v1 (supersedes ADR 00031)
  - ADR 00037: Extension negotiation timing (handshake phase,
    transport-agnostic)
  - ADR 00038: Silence detection scope + subscription lifecycle
  - CTR-13: Silence detection timer (per-pane countdown, PTY read path)
  - §5.5: RendererHealth minimum interval 1000 ms added (normative)
  - §6.2: `silence_threshold_ms` min/max [1000, 3600000] added to event_mask
    table

---

## File 3: Doc 04 — Input & RenderState ✅

All steps complete.

- [x] 3a. ADRs written: 00021, 00022, 00025
- [x] 3b. ADR 00009 extended with §3.1 per-pane delivery rationale
- [x] 3c. CTR-06 extended with §3.1 ring buffer + I-frame scheduling; CTR-12
      extended with §2.1 server IME processing
- [x] 3d. IME CTRs written: behavior CTR-01 (Jamo decomposition),
      interface-contract CTR-01 (engine decomposition + preedit exclusivity)
- [x] 3e. 15 cleanup items applied (#5 already done; #1-4, #6-15 executed)
- [x] 3f. §10 Open Questions deleted (all 6 closed); Appendix B v0.8 comparison
      para deleted (rationale, non-normative)

---

## File 4: Doc 05 — CJK Preedit Protocol

### 4a. ADRs to write (first occurrence)

| ADR # | Topic                                    | Content from this file                                                                                                                                                                                                                                 |
| ----- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 00026 | Preedit lifecycle on interrupting events | §6.1-6.10 (all decisions: pane close cancels, disconnect commits, focus change commits, mouse button commits/scroll preserves, IME switch commit_current, Escape commits, daemon restart commits); §8.2-8.3 (commit-on-restore, resume deferred to v2) |
| 00032 | Preedit message simplification           | §2.2/2.4 changes-from (remove composition_state, cursor/width; retain text for multi-client coordination; remove frame_type=2)                                                                                                                         |

### 4b. ADRs to add content to (already created)

| ADR # | Content from this file                                                                                                                             |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 00021 | §1.1 (preedit as cell data rationale, capability decoupling), §13.1 (single-path rendering rationale)                                              |
| 00023 | §13.2 (message ordering, "context before content principle")                                                                                       |
| 00025 | §3.3 (input_method identifier architecture — single canonical string, flows unchanged to IME constructor, registry in IME Interface Contract §3.7) |
| 00006 | §12.1 (JSON overhead ~30 B/msg vs binary, negligible at typing speeds — well worth the debuggability gain)                                         |

### 4c. Daemon CTRs to write (first occurrence)

| CTR #  | Topic                                     | Content from this file                                                                                                                                    |
| ------ | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-11 | Preedit race condition server behavior    | §6.1-6.10: server-side cancel/commit procedures, hotkey detection, resize repositioning, keystroke coalescing; §10.1: error handling (log, commit, reset) |
| CTR-15 | AmbiguousWidthConfig Terminal integration | §4.1: server passes ambiguous_width to pane's libghostty-vt Terminal for cursor movement and line wrapping calculations                                   |

### 4d. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                                                                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-06 | §13.1 (ring buffer interaction — preedit frames via shared ring, Tier 0 immediate flush, preedit protocol messages via direct queue, PreeditSync priority 1 before I-frame) |
| CTR-08 | §7: preedit delivery latency, coalescing bypass                                                                                                                             |
| CTR-12 | §3.1 (setActiveInputMethod, locking), §3.3 (per-session state), §8.2 (engine initialization on restore)                                                                     |

### 4e. IME CTRs to add content to (already created in File 3)

| Target                 | CTR #  | Content from this file                                                 |
| ---------------------- | ------ | ---------------------------------------------------------------------- |
| IME behavior           | CTR-01 | §2.3: Escape behavior rationale ("matches ibus-hangul, fcitx5-hangul") |
| IME interface-contract | CTR-01 | §1.1 (HangulInputContext, jamo stack), §3.3 (per-session engine state) |

### 4f. Cleanup items

| #  | Section                                       | Lines   | Action            | Target            | Description                          |
| -- | --------------------------------------------- | ------- | ----------------- | ----------------- | ------------------------------------ |
| 1  | §1.1 Server owns IME                          | 22-25   | DEL-ADR-exist     | ADR 00013         | "server owns native IME engine"      |
| 2  | §1.1 Preedit as cell data rationale           | 27-30   | DEL-ADR-new       | ADR 00021         | Dual-path design rationale           |
| 3  | §1.1 Preedit capability decoupling            | 55-57   | DEL-ADR-new       | ADR 00021         | "controls lifecycle only"            |
| 4  | §1.1 Preedit exclusivity + HangulInputContext | 67-74   | DEL-ime-CTR       | IME-ic CTR-01     | "one HangulInputContext"             |
| 5  | §2.3 Escape behavior rationale                | 190-194 | DEL-ADR-new       | ADR 00026         | "matches ibus-hangul"                |
| 6  | §3.1 Server hotkey detection                  | 277-280 | DEL-daemon-CTR    | CTR-11            | "detects mode-switch hotkeys"        |
| 7  | §3.1 Server impl (setActiveInputMethod)       | 288-296 | DEL-daemon-CTR    | CTR-12            | Internal API calls, locking          |
| 8  | §3.3 Per-session engine state                 | 339-343 | DEL-ADR-exist     | ADR 00013         | "one IME engine per session"         |
| 9  | §5.1 Problem statement framing                | 414-419 | REWRITE           | —                 | Keep reason values; remove framing   |
| 10 | §6.1 Pane close — cancel behavior             | 444-460 | DEL-ADR-new + CTR | ADR 00026, CTR-11 | Decision + server procedure          |
| 11 | §6.2 Disconnect — commit rationale            | 469     | DEL-ADR-new       | ADR 00026         | "preserve user's work"               |
| 12 | §6.3 Resize — repositioning                   | 485-494 | DEL-daemon-CTR    | CTR-11            | "repositions internally"             |
| 13 | §6.4 Screen switch — PTY commit ref           | 506     | DEL-covered       | Daemon docs       | "defined in daemon docs"             |
| 14 | §6.5 Rapid keystrokes — coalescing            | 521-529 | DEL-daemon-CTR    | CTR-11            | Coalescing algorithm                 |
| 15 | §6.7 Focus change — commit                    | 546-550 | DEL-ADR-new + CTR | ADR 00026, CTR-11 | Decision + procedure                 |
| 16 | §6.8 Session detach — commit                  | 559-566 | DEL-ADR-new       | ADR 00026         | "preserve user's work"               |
| 17 | §6.9 IME switch — hotkey note                 | 599-602 | DEL-daemon-CTR    | CTR-11            | "hotkey detection path"              |
| 18 | §6.10 Mouse-preedit rationale                 | 635-638 | DEL-ADR-new       | ADR 00026         | "Button commits, Scroll preserves"   |
| 19 | §7 Delivery latency (entire)                  | 642-652 | DEL-daemon-CTR    | CTR-08            | Coalescing bypass, latency           |
| 20 | §8.2 Restore — engine init                    | 703-708 | DEL-daemon-CTR    | CTR-12            | "creates one HangulImeEngine"        |
| 21 | §8.2 Restore — commit rationale               | 698-701 | DEL-ADR-new       | ADR 00026         | "client no longer connected"         |
| 22 | §8.3 Resume composition (future)              | 710-724 | DEL-ADR-new       | ADR 00026         | Deferred to v2; add to 99-post-v1    |
| 23 | §9.1 Server rendering details                 | 735-738 | REWRITE           | —                 | Keep disclaimer; remove examples     |
| 24 | §9.2 Observer UI features                     | 764-778 | REWRITE           | —                 | Keep wire fields; remove UI guidance |
| 25 | §10.1 Invalid composition error handling      | 784-793 | DEL-daemon-CTR    | CTR-11            | "Log, commit, reset"                 |
| 26 | §12 Bandwidth analysis (entire)               | 859-889 | DEL               | —                 | Non-normative                        |
| 27 | §13.1 Single-path rendering rationale         | 894-915 | DEL-ADR-new       | ADR 00021         | Architecture explanation             |
| 28 | §13.1 Ring buffer interaction                 | 917-928 | DEL-daemon-CTR    | CTR-06            | Ring vs direct queue                 |
| 29 | §13.2 Message ordering                        | 930-952 | DEL-ADR-new       | ADR 00023         | "context before content"             |

---

## File 5: Doc 02 — Handshake & Capability Negotiation

### 5a. ADRs to write (first occurrence)

| ADR # | Topic                            | Content from this file                                                                 |
| ----- | -------------------------------- | -------------------------------------------------------------------------------------- |
| 00019 | Per-session focus model (v1)     | §8.9: viewport clipping (related); main content from Doc 03 §8.1                       |
| 00024 | Capability negotiation mechanics | §2.1 (string arrays over bitmasks), §7.2 (set intersection), §7.3 (render requirement) |

### 5b. ADRs to add content to (already created)

| ADR # | Content from this file                                                                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------- |
| 00020 | §8.1 (single-session-per-connection), §8.6 (multi-client input ordering), §8.7 (readonly), §8.8 (exclusive/detach_others) |
| 00023 | §8.2 (direct message queue, priority 1)                                                                                   |
| 00025 | §5.3 (two-axis model, string identifiers, field naming asymmetry)                                                         |

### 5c. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                       |
| ------ | ------------------------------------------------------------ |
| CTR-06 | §8.6 (ring buffer / coalescing tiers)                        |
| CTR-08 | §6.2 (server coalescing behavior), §6.3 (iOS tier breakdown) |
| CTR-09 | §11.1 (auth ref), §11.3 (timeout values)                     |

### 5d. Cleanup items

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

### 6b. ADRs to add content to (already created)

| ADR # | Content from this file                                                          |
| ----- | ------------------------------------------------------------------------------- |
| 00019 | §8.1: "Decision for v1: Per-session focus (like tmux)"                          |
| 00023 | §1.6 ("context before content" principle), §7 (sequence correlation + ordering) |
| 00025 | §2.1/2.3 (IME inheritance), §3.1 (two-channel IME state model)                  |

### 6c. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                 |
| ------ | -------------------------------------- |
| CTR-07 | §8.4 (health state + resize exclusion) |

### 6d. Cleanup items

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

### 6e. Additional changes (discovered during Doc 06 review)

- [x] §1.9 DestroySessionRequest: cascade block removed → CTR-14
- [x] §4.3 SessionListChanged: event value table added
      (`created`/`destroyed`/`renamed`)
- [x] ADR 00039: SessionListChanged event semantics
- [x] CTR-14: session destroy cascade + rename broadcast flow → daemon

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
