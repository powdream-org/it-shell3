# Handover: Plan 15 Unified Cycle v1.0-r9/r13/r11 to Next Revision

- **Date**: 2026-04-01
- **Author**: team lead

---

## Insights and New Perspectives

**Unified 4-topic cycles work but need exhaustive same-class sweeps**: The
16-to-20 byte header change (Resolution 19) cascaded through 4 verification
rounds because each round found more locations where "16" appeared in different
forms — prose text (Round 1), offset tables and performance analysis (Round 2),
hex dump examples (Round 3). The same-class sweep in Step 6b.1 must cover ALL
representation forms of a numeric constant: prose, tables, pseudocode, offset
tables, performance calculations, hex dump examples, and Mermaid diagrams. This
cycle proved that "grep for 16-byte" is insufficient when the constant also
appears as a bare `16` in offset tables and calculation breakdowns.

**Mechanical fixes converge reliably** (reinforces L4): Rounds 1-3 each found
progressively fewer issues (6, 1, 1+1 pre-existing). All were number changes,
string replacements, or table updates. No prose fixes, no cascading regressions.
This pattern motivated SIP-1/SIP-3 to change the Round 3+ threshold — by Round
3, issues are minor enough that owner triage is more efficient than another
automatic fix cycle.

**KeyEvent field naming revealed a 3-way spec divergence**: The wire protocol
uses `keycode: u16` (headroom for future HID page extensions), the daemon-arch
used `keycode: u32` (stale from before HID keycode design was finalized), and
the IME contract uses `hid_keycode: u8` (bounded by HID_KEYCODE_MAX = 0xE7).
Caught in Round 1 (S-2/C-3). The fix established a naming convention: wire
carries `keycode` (transport name), daemon/IME use `hid_keycode` (domain name),
with an explicit mapping note bridging them. This pattern — different names for
the same data at different layers — should be applied deliberately when types
narrow across boundaries.

**9-agent unified discussion converged in one round**: Despite the scope (16
CTRs + 4 review notes across 4 topics), all 9 agents reached unanimous consensus
without needing a second discussion round. The key factor was that all items
were spec-catching-up-to-code — no genuinely novel design decisions. CTR
resolution cycles are fundamentally different from feature design cycles.

## Design Philosophy

**Spec follows code for CTR resolution; code follows spec for feature design**:
Plan 15 was a spec alignment cycle. The specs were catching up to implementation
reality (Plans 1-7.5). No new features were designed. The next cycle (if any)
should only start when new implementation work (Plan 8+) reveals additional spec
gaps.

**Fixed-point arithmetic is the unified numeric model**: Split ratios, resize
deltas, and layout tree wire format all use u32/i32 fixed-point (x10^4). JSON
representations use integers (`"ratio": 5000` = 50.00%). No floating-point
anywhere in the pane geometry pipeline. This was established by ADR 00062 and
applied consistently across daemon-arch, daemon-behavior, and protocol specs.

**Wire names vs domain names at layer boundaries**: The protocol spec uses
transport-layer names (`keycode`, `sequence`), while daemon and IME specs use
domain-layer names (`hid_keycode`, `frame_sequence`). This is intentional: each
layer names things for its consumers. Mapping notes at the boundary connect
them.

## Owner Priorities

- **Plan 16 (Post-Design Code Alignment) is next**: Specs are now updated; code
  changes that were blocked on spec updates can proceed. See ROADMAP.md Plan 16
  for items: ADR 00059 (KeyEvent.Modifiers code), ADR 00052 (MAX_CLIENTS
  review), ADR 00054 (socket path code), ADR 00058 (inline buffers code), ADR
  00062 (fixed-point ratio code).
- **No immediate next spec revision expected**: The specs are current with
  implementation reality through Plan 7.5. The next spec revision cycle would be
  triggered by Plans 8-10 implementation revealing new gaps.

## New Conventions and Procedures

- **Step 6 threshold change** (SIP-1 + SIP-3): Round 3+ CLEAN auto-declares
  clean. Round 3+ non-CLEAN runs Phase 1 only, then `/triage` for owner
  decision. No confirmation questions for CLEAN results. Committed to
  `steps/06-fix-round.md`.
- **Triage sub-agent delegation** (SIP-2): Step 4 of triage now spawns a
  sub-agent to read quality examples and prepare full 5W1H presentations. Team
  leader reviews and presents, saving context window. Anti-pattern added:
  "Skipping quality examples." Committed to `.claude/skills/triage/SKILL.md`.

## Pre-Discussion Research Tasks

No research tasks for the next revision — this cycle resolved all known CTRs and
deferred review notes. The next revision will be driven by new inputs from
implementation (Plans 8-10) or client design (Plan 14.1).

### Unfixed secondary findings (carry forward)

- **Doc 01 Section 3.1.1 reader loop reference**: Consistency verifier (Round 4)
  noted that Doc 01 Section 3.1.1 references "reader loop (Section 9.2)" but
  Section 9 has no subsections — the reader loop is described in Section 3.3.
  Pre-existing, not introduced by this cycle. Minor.

### Cycle artifacts for reference

- Resolution: `design-resolutions/01-plan15-unified-cycle.md` (20 resolutions +
  6 corrections + 2 owner decisions)
- Verification: `verification/round-1-issues.md` (6 confirmed, 2 dismissed).
  Rounds 2-4 issues fixed by team lead directly (not recorded in separate
  files).
- Retrospective: `retrospective/skill-improvement-proposals.md` (3 SIPs)
- No cross-team requests filed during this cycle.
- No review notes filed during owner review.
