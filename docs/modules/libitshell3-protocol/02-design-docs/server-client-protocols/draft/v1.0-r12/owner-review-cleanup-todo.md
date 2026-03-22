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

| ADR #     | Topic                                                                                                                                                         |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 00019     | Per-session focus model (v1)                                                                                                                                  |
| 00020     | Session attachment model (single-per-connection, readonly, exclusive)                                                                                         |
| 00021     | Preedit single-path rendering model                                                                                                                           |
| 00022     | Server-owned scrollback (no client cache)                                                                                                                     |
| 00023     | Message ordering and delivery guarantees (context before content)                                                                                             |
| 00024     | Capability negotiation mechanics (string arrays, set intersection)                                                                                            |
| 00025     | Input method identifier design (two-axis, string IDs, two-channel state)                                                                                      |
| 00026     | Preedit lifecycle on interrupting events                                                                                                                      |
| ~~00027~~ | ~~Pane lifecycle~~ — **CANCELLED**: remain-on-exit already in 99-post-v1-features.md; auto-unzoom/auto-close are wire spec (kept in Doc 03)                   |
| ~~00028~~ | ~~Two-layer error handling model~~ — **CANCELLED**: ERR_* paragraphs are duplicates of §1.5 and §9.2; error layer rule is wire spec (no rationale to extract) |
| ~~00029~~ | ~~Notification subscription model~~ — **CANCELLED**: §4 text is wire spec only; no design reasoning to extract                                                |
| 00030     | Adaptive coalescing and flow control                                                                                                                          |
| 00031     | Session persistence model (hybrid memory + JSON snapshots)                                                                                                    |
| 00032     | Preedit message simplification (field removals, frame_type=2)                                                                                                 |
| ~~00033~~ | ~~Protocol wire conventions~~ — **EXCLUDED**: content stays in protocol overview                                                                              |
| 00034     | Per-connection handshake (no lightweight reconnect optimization in v1)                                                                                        |
| 00027     | YAGNI — Remove compression header flag and capability (supersedes ADR 00014)                                                                                  |
| 00028     | YAGNI — Remove `celldata_encoding` capability                                                                                                                 |
| 00029     | Per-client viewports declined — breaks shared ring buffer optimization                                                                                        |

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

## File 5: Doc 02 — Handshake & Capability Negotiation ✅

All steps complete. Doc 02 reduced from ~1017 lines to ~879 lines.

- [x] 5a. ADRs written: 00028, 00029
- [x] 5b. ADRs extended: 00023, 00024, 00025
- [x] 5c. Daemon CTR written: CTR-17
- [x] 5d. CTRs extended: CTR-06, CTR-08, CTR-09
- [x] 5e. 26 cleanup items applied

**Note**: Cross-doc items 27–33 (ADR 00027 COMPRESSED flag removal) applied to
Doc 01, Doc 04, and 99-post-v1-features.md. ✅

---

## File 6: Doc 03 — Session & Pane Management ✅

> **Pre-execution review completed (2026-03-22).** Original plan was too
> aggressive — most planned DEL actions targeted wire-observable content. Kept
> in Doc 03 (no action): §1.6, §2.1, §2.3 auto-unzoom, §2.8, §5.2 policy table,
> §7 ordering. CTR-07 extension and ADR 00023/00025 extensions cancelled. ADR
> 00019 moved from 6b to 6a (does not yet exist).
>
> **Additional finding (2026-03-22):** §8 Multi-Client Behavior (§8.1–§8.4)
> deleted entirely — all content is either duplicate of individual message
> definitions or covered by Doc 06 §2.8. §9 Readonly Client Permissions becomes
> the new §8, requiring 5 cross-reference fixes (3 inner-doc + 1 Doc 05 + 1
> daemon CTR-20).

All steps complete.

- [x] 6a. ADR written: 00019 (per-session focus model)
- [x] 6c. Daemon CTRs written: CTR-18 (pane exit cascade diagram), CTR-19
      (navigation algorithm), CTR-20 (§9→§8 cross-ref fix notification)
- [x] 6d. 11 cleanup items applied; §4.1 dangling "two-channel model" cross-ref
      also fixed

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
