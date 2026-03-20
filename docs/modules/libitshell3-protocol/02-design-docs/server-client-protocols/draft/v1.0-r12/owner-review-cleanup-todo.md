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
| 00040     | YAGNI — Remove compression header flag and capability (supersedes ADR 00014)     |
| 00041     | YAGNI — Remove `celldata_encoding` capability                                    |
| 00042     | Per-client viewports declined — breaks shared ring buffer optimization           |

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

## File 4: Doc 05 — CJK Preedit Protocol ✅

All steps complete. Doc 05 reduced from ~950 lines to ~686 lines.

- [x] 4a. ADRs written: 00026, 00032
- [x] 4b. ADRs extended: 00021, 00023, 00025, 00006
- [x] 4c. Daemon CTRs written: CTR-11, CTR-15
- [x] 4d. CTRs extended: CTR-06, CTR-08, CTR-12
- [x] 4e. IME CTRs extended: behavior CTR-01, interface-contract CTR-01 (done in
      File 3)
- [x] 4f. 29 cleanup items applied (+ Gap 1 §2.2, Gap 3 §3.3, Gap 4 §4.1)

**Note**: §5 section numbering has a gap (§5.1 deleted, §5.2 remains); §12
deleted (§11 → §13 gap). Both deferred to final cross-doc renumbering pass.

---

## File 5: Doc 02 — Handshake & Capability Negotiation

### 5a. ADRs to write (first occurrence)

| ADR # | Topic                                            | Content from this file                                                                                                     |
| ----- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| 00019 | Per-session focus model (v1)                     | §8.9: viewport clipping (related); main content from Doc 03 §8.1 — **write together with File 6 ADR 00019 entry**          |
| 00040 | YAGNI compression removal (supersedes ADR 00014) | Doc 01 §3.4/§3.5; Doc 02 §2.3/§4.1/§9.9; Doc 04 §8; 99-post-v1 §7 — ✅ WRITTEN                                             |
| 00041 | YAGNI: Remove `celldata_encoding` capability     | Doc 02: capability table row (346), §4.2 entire section (360-391), pseudocode block (620-629), degradation table row (957) |
| 00042 | Per-client viewports declined                    | §8.9 lines 920-922 (Doc 02); §8.9 also in Doc 03 if referenced — breaks shared ring buffer (memory/compute/transfer)       |

### 5b. ADRs to add content to (already created)

| ADR # | Content from this file                                            |
| ----- | ----------------------------------------------------------------- |
| 00020 | §8.6 (multi-client input ordering)                                |
| 00023 | §8.2 (direct message queue, priority 1)                           |
| 00024 | §2.1 (string arrays over bitmasks)                                |
| 00025 | §5.3 (two-axis model, string identifiers, field naming asymmetry) |

### 5c. Daemon CTRs to write (new)

| CTR #  | Content from this file                                                                                                                                                                                       |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| CTR-17 | §7.1–§7.3 server negotiation algorithms — `min()` version selection (566-575), capability intersection pseudocode (582-585), render caps intersection + validation (592-601) — move to daemon handshake docs |

### 5d. Daemon CTRs to add content to (already created)

| CTR #  | Content from this file                                                                |
| ------ | ------------------------------------------------------------------------------------- |
| CTR-06 | §8.6 (ring buffer / coalescing tiers)                                                 |
| CTR-08 | §6.2 (server coalescing behavior), §6.3 (iOS tier breakdown)                          |
| CTR-09 | §11.1 (auth ref), §11.3 (timeout values)                                              |
| CTR-16 | Daemon 03-lifecycle `capabilities` field example — ✅ WRITTEN (ADR 00040 consequence) |

### 5e. Cleanup items

| #  | Section                            | Lines     | Action         | Target              | Description                                                                              |
| -- | ---------------------------------- | --------- | -------------- | ------------------- | ---------------------------------------------------------------------------------------- |
| 1  | §2.1 String capabilities rationale | 112-115   | DEL-ADR-new    | ADR 00024           | "Instead of bitmasks"                                                                    |
| 2  | §3.2 tab_count removal note        | 260-266   | DEL-ADR-exist  | ADR 00008           | "v0.2 change" changelog relic                                                            |
| 3  | §2.3 "compression" row             | 334       | DEL-ADR-exist  | ADR 00040           | Delete capability row; shift bit numbers down                                            |
| 4  | §2.3 `celldata_encoding` cap row   | 346       | DEL-ADR-new    | ADR 00041           | Delete capability table row                                                              |
| 5  | §4.1 compression note              | 350-351   | DEL-ADR-exist  | ADR 00040           | Delete 2-line compression deferral note                                                  |
| 6  | §4.2 CELLDATA_ENCODING section     | 360-391   | DEL-ADR-new    | ADR 00041           | Delete entire section                                                                    |
| 7  | §5.3 Two-axis model explanation    | 423-425   | REWRITE        | ADR 00025           | Keep field names/enum values; move separation rationale to ADR                           |
| 8  | §5.3 Field naming asymmetry        | 475-478   | DEL-ADR-new    | ADR 00025           | layout vs layouts                                                                        |
| 9  | §5.3 String identifier rationale   | 480-484   | DEL-ADR-new    | ADR 00025           | "self-documenting"                                                                       |
| 10 | §6.2 Server coalescing behavior    | 522-524   | DEL-daemon-CTR | CTR-08              | Power throttling, fps cap                                                                |
| 11 | §6.2 Design decision (client RTT)  | 533-536   | DEL-ADR-exist  | ADR 00011           | "client is the only entity"                                                              |
| 12 | §6.3 iOS example tier breakdown    | 551-556   | DEL-daemon-CTR | CTR-08              | Tier calculations                                                                        |
| 13 | §7.1 Version selection algorithm   | 566-575   | REWRITE        | CTR-17              | Replace pseudocode with wire fact (ERR_VERSION_MISMATCH); move min() algorithm to daemon |
| 14 | §7.2 intersection pseudocode       | 582-585   | REWRITE        | CTR-17              | Replace pseudocode with prose; move server algorithm to daemon                           |
| 15 | §7.3 render caps pseudocode        | 592-601   | REWRITE        | CTR-17              | Keep ERR_CAPABILITY_REQUIRED wire fact; move intersection + validation to daemon         |
| 16 | §7.5 CELLDATA_ENCODING Negotiation | 615-630   | DEL-ADR-new    | ADR 00041           | Delete entire §7.5 section (v2+ no-op)                                                   |
| 17 | §8.2 IME per-session rationale     | 716-721   | REWRITE        | ADR 00013           | Keep field location wire facts; move per-session engine rationale to ADR                 |
| 18 | §8.2 Direct message queue          | 732-735   | REWRITE        | ADR 00023           | Keep PreeditSync ordering rule; move "context before content" principle ref to ADR       |
| 19 | §8.6 Preedit exclusivity ref       | 872-874   | ~~REWRITE~~    | —                   | ~~Keep wire fact; trim~~ ✅                                                              |
| 20 | §8.6 Ring buffer / coalescing      | 875-878   | DEL-daemon-CTR | CTR-06              | "shared per-pane ring buffer"                                                            |
| 21 | §8.9 Viewport clipping             | 920-922   | DEL-ADR-new    | ADR 00042           | "deferred to v2" → declined; per-client viewports break shared ring buffer               |
| 22 | §8.9 Resize internals ref          | 924-925   | DEL-covered    | Daemon 04-runtime   | "defined in daemon docs"                                                                 |
| 23 | §9.9 fallback table                | 950       | DEL-ADR-exist  | ADR 00040           | Delete "compression" fallback row                                                        |
| 24 | §9.9 degradation table row         | 957       | DEL-ADR-new    | ADR 00041           | Delete `celldata_encoding` degradation row                                               |
| 25 | §11.1 Auth implementation ref      | 999-1000  | DEL-covered    | Daemon 03-lifecycle | "defined in daemon docs"                                                                 |
| 26 | §11.3 Handshake timeout values     | 1012-1017 | DEL-daemon-CTR | CTR-09              | Duration values                                                                          |
| —  | _(cross-doc items from ADR 00040)_ | —         | —              | —                   | —                                                                                        |
| 27 | **Doc 01** §3.4 COMPRESSED row     | 148       | DEL-ADR-exist  | ADR 00040           | Delete row; shift RESPONSE/ERROR/MORE_FRAGMENTS bits                                     |
| 28 | **Doc 01** §3.4 flags example      | 158       | DEL-ADR-exist  | ADR 00040           | Remove "ENCODING=1 + COMPRESSED=1" example                                               |
| 29 | **Doc 01** §3.5 Compression        | 233-237   | DEL-ADR-exist  | ADR 00040           | Delete entire §3.5 section                                                               |
| 30 | **Doc 01** §9.3 ERR_PROTOCOL_ERROR | 766       | DEL-ADR-exist  | ADR 00040           | Remove "COMPRESSED" from error description example                                       |
| 31 | **99-post-v1** §7 reserved lang    | 271-272   | DEL-ADR-exist  | ADR 00040           | Remove "COMPRESSED flag reserved" sentence                                               |
| 32 | **Doc 04** §8 Compression          | 975-981   | DEL-ADR-exist  | ADR 00040           | Delete COMPRESSED flag paragraph                                                         |
| 33 | **Doc 04** §8 wire dump comment    | 1033      | DEL-ADR-exist  | ADR 00040           | Remove "no compression" annotation                                                       |

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
