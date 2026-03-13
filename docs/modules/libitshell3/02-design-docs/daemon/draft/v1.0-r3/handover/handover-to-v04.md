# Handover: Daemon Design v0.3 to v0.4

**Date**: 2026-03-10
**Author**: team leader

---

## Insights and New Perspectives

The v0.3 cross-team migration revealed that "headless architecture" is more than a design label — it's a pervasive invariant that every contributor must internalize. During verification, 3 of the 12 confirmed issues (V1-01, V1-02, R2-03) were Surface API references (`ghostty_surface_key()`, `ghostty_surface_preedit()`) that leaked into daemon docs during content absorption from IME and protocol sources. The original IME/protocol docs were written when the Surface-based architecture was still assumed; blindly copying their text into daemon docs violated the headless constraint established in doc 01.

**Lesson**: When absorbing content from other modules, the text must be *translated* to the target module's architecture, not just moved. Future revisions should treat cross-module content migration as a rewriting task, not a copy task.

The 4-document structure (01-internal-architecture, 02-integration-boundaries, 03-lifecycle-and-connections, 04-runtime-policies) proved effective for organizing 31 absorbed topics without bloating any single document. Doc 04 in particular serves as a natural home for operational policies that don't fit the architectural (01), integration (02), or lifecycle (03) categories.

## Design Philosophy

**Single source of truth for daemon behavior**: After v0.3, the daemon docs are the sole authoritative source for all daemon-side behavioral descriptions. Protocol docs define wire format and message semantics only. IME docs define engine API contracts only. This separation was the entire purpose of v0.3 and must be maintained — future revisions should not re-introduce daemon behavioral content into protocol or IME docs.

**Headless equivalents table**: The mapping established in doc 01 §4.3 (ImeResult field → headless API) is the canonical reference for how the daemon interacts with ghostty without a Surface. Any new feature that touches key processing or preedit must consult this table.

## Owner Priorities

1. **R2-02 (CRITICAL)**: SessionDetachRequest vs DetachSessionRequest naming mismatch is the highest-priority item. This is a cross-module naming inconsistency between daemon and protocol docs that will cause confusion during implementation.
2. **Review note 03 (HIGH)**: pane_slots placement and SessionEntry introduction — this is an architectural question about state tree organization that has been deferred since v0.2.
3. The remaining review notes (01, 02) are LOW cosmetic issues.

## New Conventions and Procedures

No new conventions. The cross-team revision workflow (primary TODO in daemon, secondary TODOs in protocol/IME cross-referencing the primary) worked well and should be reused for future multi-module revisions.

## Pre-Discussion Research Tasks

- **SessionDetachRequest naming audit**: Grep all daemon docs for message type names and cross-check against protocol doc 03's normative message type table. Produce a complete list of mismatches (R2-02 may not be the only one).
- **SessionEntry design**: Review note 03 proposes introducing a SessionEntry struct. Research how tmux and zellij organize their session/pane state trees to inform the design decision.
