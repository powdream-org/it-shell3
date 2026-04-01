# Handover: Plan 15 Unified Cycle v1.0-r9/r13/r11 to Next Revision

- **Date**: 2026-04-01
- **Author**: team lead

---

## Insights and New Perspectives

**Unified 4-topic cycles work but need tight cross-reference management**: The
16→20 byte header change (Resolution 19) cascaded through 4 verification rounds
because each round found more locations where "16" appeared. The hex dump in
Appendix A was the last holdout — found in Round 3. Lesson: when a numeric
constant changes, the same-class sweep in Step 6b.1 must include ALL
representations (prose, offset tables, performance analysis, hex dump examples,
Mermaid diagrams).

**Mechanical fixes converge reliably**: Rounds 1-3 each found progressively
fewer issues (6 → 1 → 1+1). All were number changes, string replacements, or
table updates. No prose fixes, no cascading regressions. This reinforces L4
(design-principles.md) and motivated SIP-1/SIP-3 to change the Round 3+
threshold.

**KeyEvent field naming revealed a 3-way spec divergence**: The wire protocol
uses `keycode: u16` (headroom), the daemon-arch used `keycode: u32` (stale), and
the IME contract uses `hid_keycode: u8` (bounded by HID_KEYCODE_MAX). This was
caught in Round 1 verification (S-2/C-3). The fix established the naming
convention: wire carries `keycode` (transport name), daemon/IME use
`hid_keycode` (domain name), with an explicit mapping note bridging them.

## Design Philosophy

**Spec follows code for Plan 15; code follows spec for all other plans**: This
was a CTR resolution cycle — the specs were catching up to implementation
reality. No new features were designed. The next cycle (if any) should only
start when new implementation work (Plan 8+) reveals additional spec gaps.

**Fixed-point arithmetic is the unified numeric model**: Split ratios, resize
deltas, and layout tree wire format all use u32/i32 fixed-point (x10^4). JSON
representations use integers (`"ratio": 5000` = 50.00%). No floating-point
anywhere in the pane geometry pipeline.

## Owner Priorities

- **Plan 16 (Post-Design Code Alignment) is next**: Specs are now updated; code
  changes that were blocked on spec updates can proceed. See `ROADMAP.md` Plan
  16 for the code alignment items.
- **No immediate next revision expected**: The specs are current with
  implementation reality through Plan 7.5. The next spec revision cycle would be
  triggered by Plans 8-10 implementation revealing new gaps.

## New Conventions and Procedures

- **Step 6 threshold change** (SIP-1 + SIP-3): Round 3+ CLEAN auto-declares
  clean. Round 3+ non-CLEAN runs Phase 1 only, then `/triage` for owner
  decision. Committed in skill files.
- **Triage sub-agent delegation** (SIP-2): Step 4 of triage now spawns a
  sub-agent to read quality examples and prepare full 5W1H presentations. Team
  leader reviews and presents, saving context window. Committed in skill files.

## Pre-Discussion Research Tasks

No research tasks for the next revision — this cycle resolved all known CTRs and
deferred review notes. The next revision will be driven by new inputs from
implementation (Plans 8-10) or client design (Plan 14.1).

### Unfixed secondary findings (carry forward)

- **Doc 01 Section 3.3 reader loop reference**: Consistency verifier (Round 4)
  noted that Doc 01 Section 3.1.1 references "reader loop (Section 9.2)" but
  Section 9 has no subsections — the reader loop is described in Section 3.3.
  Pre-existing, not introduced by this cycle. Minor.
