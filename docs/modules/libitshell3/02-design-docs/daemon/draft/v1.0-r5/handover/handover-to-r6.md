# Handover: Daemon v1.0-r5 to v1.0-r6

- **Date**: 2026-03-22
- **Author**: team leader

---

## Insights and New Perspectives

**Deferred tables in spec docs are a maintenance trap.** The v1.0-r5 §7 "Items
Deferred to Future Versions" table contained 4 items, each misplaced:

- "Multiple tabs per session (Phase 3)" — was not a deferral; the owner never
  planned this. Already covered by ADR 00008.
- "Multi-threaded event loop (Not planned)" — a permanent architectural
  decision, not a deferral. Promoted to ADR 00033.
- "Floating panes" and "Kitty keyboard protocol" — feature scoping decisions
  that belong in `99-post-v1-features.md`, not in a daemon spec appendix.

The lesson: items in deferred tables straddle two failure modes — they look like
"we'll do this later" when the owner meant "we chose not to do this," and they
sit outside any canonical location that future teams would check.

**Prior Art summary tables duplicate inline citations.** All 3 daemon docs
(doc01, doc02, doc03) had Prior Art sections that repeated references already
present inline in the body text, with added problems: stale version numbers
("IME contract v0.8", "Protocol spec v0.10"), stale section numbers, and a
maintenance burden that grows with every revision. The owner removed all 3.

**Verification surfaced real architectural issues, not just formatting bugs.** 4
verification rounds found: deactivate() scope conflict with multi-client model
(SEM-05), PaneMetadataChanged vs ProcessExited semantic overlap (SEM-03), state
diagram contradictions (CRX-03/SEM-01), and missing struct fields (SEM-02).
These were pre-existing issues exposed by Phase 1 verifiers examining the full
doc set, not introduced by the CTR-01 changes.

## Design Philosophy

**Canonical location principle.** Every piece of information should have exactly
one canonical home:

- Architectural decisions → ADRs
- Post-v1 feature scoping → `99-post-v1-features.md`
- Reference codebase learnings → `docs/insights/reference-codebase-learnings.md`
- Inline citations in body text → sufficient; no summary table needed

A deferred table, a Prior Art summary, or a changelog in a spec header is a
secondary copy that will diverge from the primary source. Delete the copy;
strengthen the primary.

**Convention compliance is structural, not cosmetic.** The v1.0-r5 review found
that all 4 spec docs had AGENTS.md convention violations (forbidden metadata
fields, exact cross-revision file-path links). These aren't style issues — the
exact-path links broke every time a referenced document was revised, and the
changelog metadata obscured the two fields that matter (Date, Scope).

## Owner Priorities

1. **Binary split tree layout decision needs an ADR.** The owner identified this
   during review but it was not yet written. v1.0-r6 team should write ADR for
   "binary split tree as the sole pane layout model" with rationale (YAGNI,
   tmux/cmux/ghostty precedent, index arithmetic benefits). This is a design
   decision, not a feature deferral.

2. **Preedit ownership scope (SEM-A) must be resolved.** Deferred from v1.0-r5
   Round 2 with review note `01-preedit-ownership-scope.md`. Core question: is
   `PanePreeditState` (doc04 §6.1) about multi-client contention on a single
   pane, or multi-pane contention? The relationship between
   `PanePreeditState.preedit_text` and `Session.current_preedit` also needs
   explicit documentation.

3. **20 open cross-team requests from protocol team.** All filed during protocol
   v1.0-r12 owner review cleanup. These are the primary content inputs for
   v1.0-r6:

   **Content migration (protocol → daemon):**

   | CTR | Title                                                 | Scope                                                                             |
   | --- | ----------------------------------------------------- | --------------------------------------------------------------------------------- |
   | 01  | Resize algorithm internals                            | `latest_client_id` tracking, resize orchestration, stale exclusion, detach resize |
   | 02  | KeyEvent pane_id routing logic                        | Focused-pane routing, pane validation                                             |
   | 03  | Korean composition example                            | Hangul end-to-end walkthrough                                                     |
   | 05  | Input processing priority and flow diagram            | Key input priority rules, flow diagram                                            |
   | 06  | Ring buffer architecture and I-frame scheduling       | Ring buffer sizing, I-frame scheduling, per-client cursors                        |
   | 07  | Health escalation and recovery procedures             | Stale/pause/eviction timeline, recovery procedures                                |
   | 08  | Coalescing tier internals and client power adaptation | Adaptive coalescing, power tier switching                                         |
   | 09  | Authentication implementation                         | Unix socket UID verification, future auth models                                  |
   | 11  | Preedit race condition server behavior                | Preedit ownership transfer under concurrent input                                 |
   | 12  | IME engine lifecycle (server-side)                    | Per-session engine init/deinit, activate/deactivate triggers                      |
   | 15  | AmbiguousWidthConfig terminal integration             | ghostty ambiguous width configuration pass-through                                |
   | 17  | Server negotiation algorithms                         | Handshake capability negotiation server-side logic                                |

   **Scope removal:**

   | CTR | Title                    | Action                                                  |
   | --- | ------------------------ | ------------------------------------------------------- |
   | 10  | Snapshot/restore removed | Remove snapshot/restore references from daemon docs     |
   | 16  | Compression flag removed | Remove compression capability example from client state |

   **New behavior / design gaps:**

   | CTR | Title                                        | Action                                                    |
   | --- | -------------------------------------------- | --------------------------------------------------------- |
   | 04  | Mouse event and preedit interaction          | Design gap: what happens to active preedit on mouse click |
   | 13  | Silence detection timer                      | Implement silence detection and subscription lifecycle    |
   | 14  | Session destroy cascade and rename broadcast | Document session list change notification flow            |
   | 18  | Pane process exit cascade — sequence diagram | Add sequence diagram for pane exit flow                   |
   | 19  | Pane navigation algorithm                    | Design and document directional pane navigation           |
   | 20  | Doc 03 section renumbering                   | §9 becomes §8 after protocol doc restructuring            |

## New Conventions and Procedures

- **No Prior Art summary tables in daemon spec docs.** Inline citations in body
  text are the canonical form. Summary tables removed from doc01, doc02, doc03.
- **No deferred-items tables in spec docs.** Feature deferrals go to
  `99-post-v1-features.md`. Architectural decisions go to ADRs. The §7 section
  pattern is retired.
- **ADR 00033** (single-threaded event loop) written during this review cycle.
- **AGENTS.md convention violations** in metadata and cross-doc references were
  fixed retroactively. All daemon docs now use `- **Date** / - **Scope**` format
  and loose prose references for cross-revision-cycle citations.

## Pre-Discussion Research Tasks

1. **Multi-client preedit contention (for SEM-A resolution)**: Research whether
   two clients sending keys simultaneously to the same focused pane is a real
   scenario in tmux control-mode or similar multi-client terminal multiplexers.
   This determines whether `PanePreeditState`'s concurrent-attempt protocol
   (doc04 §6.2) is exercisable or over-specified.

2. **Binary split tree ADR research**: Survey tmux `layout_cell`, cmux Bonsplit,
   ghostty split API, and zellij tiled/floating model to document the design
   space and justify binary-split-tree-only for v1. The ADR should reference the
   `99-post-v1-features.md` §8 (Floating Panes) for the deferred alternative.
