# Server-Client Protocols v1.0-r12 TODO

> **Inputs**: 6 carry-over review notes (v1.0-r10 → v1.0-r11), 1 cross-team
> request (daemon v0.4). **Review notes**: `draft/v1.0-r11/review-notes/`
> **Cross-team request**:
> `draft/v1.0-r11/cross-team-requests/01-daemon-surface-references.md`
> **Handover**: `draft/v1.0-r11/handover/handover-to-v012.md`

## Phase 0: Pre-Discussion Research (recommended by handover)

- [x] Section numbering audit: check all 6 protocol docs for
      gaps/inconsistencies introduced by v0.11 extraction
- [x] `frame_type=2` dependency research: identify all references across
      protocol docs + design-resolutions before removal

**Audit findings (owner-confirmed, Option A — full fix):**

Section numbering issues to fix in v1.0-r12:

| Doc    | Issue                                                                                                 |
| ------ | ----------------------------------------------------------------------------------------------------- |
| doc 05 | Section 2 → 4 gap: renumber 4→3, 5→4, ..., 15→14 (Section 3 was deleted in v0.7 but never renumbered) |
| doc 02 | Section 5: `### CJK Capability Semantics` unnumbered — add number or consolidate                      |
| doc 02 | Section 6: `### Render Capability Notes` unnumbered mixed with numbered `### 6.1`, `### 6.2`          |
| doc 03 | Preamble: `## Overview`, `## Message Type Assignments` unnumbered at same `##` level as `## 1.`       |
| doc 03 | Sections 3, 8, 9: all subsections unnumbered while other sections use `X.N`                           |
| doc 04 | Sections 1, 5, 10: subsections unnumbered while other sections use `X.N`                              |
| doc 05 | Section 1: `### Architecture Context`, `### Message Type Range` unnumbered                            |
| doc 06 | Preamble: `## Overview`, `## Message Type Range Assignments` unnumbered at `##` level                 |
| doc 06 | Sections 1–8: `### Background`, `### Message Types`, etc. unnumbered mixed with numbered `X.N`        |

## Phase 1: Team Discussion & Consensus (3.2) ✅

All 10 items resolved 5/5 unanimous. See
`design-resolutions/01-protocol-v012.md`.

- [x] RN-02: Option A — unzoom first, then split; preedit survives unzoom
- [x] RN-04: Defer to post-v1; keep `row_flags.hyperlink` bit 4; document
      HyperlinkTable design in 99-post-v1-features.md
- RN-01: MouseButton commits (`PreeditEnd reason="committed"`), MouseScroll does
  not
- RN-03: Auto-close pane on exit; cascade to session destroy
- RN-06: Remove `frame_type=2`; values: 0=P-frame, 1=I-frame; ~20 locations
  across 5 files
- CTR-01: Remove `ghostty_surface_preedit()` refs in doc 05 — expanded to 7
  locations (not 3)
- RN-05: **CANCELLED** —
  `v1.0-r7/design-resolutions/01-i-p-frame-ring-buffer.md` is a historical
  document; all v1.0-r12 edits reverted. Doc 05 row referenced non-existent
  sections (§8.2/8.4 deleted in v0.7 preedit overhaul).
- Section numbering: doc 05 gap (§4-15 → §3-14); unnumbered subsections;
  preamble left as-is

## Phase 2: Resolution Document (3.3) ✅

- [x] Write `design-resolutions/01-protocol-v012.md` — done and verified by all
      5 members

## Phase 3: Assignment Negotiation (3.4) ✅

Final assignment table (unanimous, 5/5):

| Document                                       | Primary Writer      | Reviewer            |
| ---------------------------------------------- | ------------------- | ------------------- |
| doc 01                                         | protocol-architect  | principal-architect |
| doc 02                                         | protocol-architect  | system-sw-engineer  |
| doc 03                                         | ime-expert          | cjk-specialist      |
| doc 04                                         | system-sw-engineer  | cjk-specialist      |
| doc 05                                         | cjk-specialist      | ime-expert          |
| doc 06                                         | principal-architect | protocol-architect  |
| 99-post-v1-features.md                         | principal-architect | protocol-architect  |
| design-resolutions/01-i-p-frame-ring-buffer.md | ime-expert          | principal-architect |

**Cross-doc dependency note**: Doc 05 renumbering (R8) affects all other
writers. cjk-specialist notifies final section numbers after completing doc 05.

## Phase 4: Document Writing (3.5) ✅

Changes per resolution doc (final assignments determined in Phase 3):

- doc 01: R6 — Remove `frame_type=2` references; **NOTE: also check line 386 for
  stale `ghostty_surface_preedit()` ref (out-of-scope from CTR-01 but discovered
  in review)**
- doc 02: R6, R8, R9 — Remove `frame_type=2` attach sequences; update Doc 05
  cross-refs (§6→§5, §6.3→§5.3); number subsections in §5, §6
- doc 03: R2, R3, R6, R8, R9 — Zoom+split note; auto-close rules; `frame_type=2`
  removal; update Doc 05 cross-ref (§7.7→§6.7); number subsections in §3, §8,
  §9; close Open Questions #4, #6
- doc 04: R1, R4, R6, R9 — Mouse+preedit cross-ref §2; close hyperlink Open
  Question §4; `frame_type=2` removal (~10 locations, remove §7.3 entirely);
  number subsections in §1, §5, §10
- doc 05: R1, R7, R8, R9 — Mouse+preedit rules §7; remove
  `ghostty_surface_preedit()` (7 locations); renumber §4-15 → §3-14; number
  subsections in §1
- doc 06: R6, R9 — Remove `frame_type=2` changelog ref; number subsections in
  §1-8
- 99-post-v1-features.md: R4 — Add §6 HyperlinkTable design direction
- design-resolutions/01-i-p-frame-ring-buffer.md: R5 — ToC fix + Doc 05 entry

## Phase 5: Verification (3.6–3.8)

### Round 1 ✅

**Phase 1 (consistency-verifier + semantic-verifier):**

- C-01: Doc 01 §11.3 line 919 — "Three frame_type values" still said value 2
  (missed by writer) → **FIXED** (§11.3 table updated; header + changelog
  updated to v1.0-r12/2026-03-14)
- C-02: Doc 04 line 510 — "P-partial" should be "P-frame" (stale terminology) →
  **FIXED**
- S-02: 99-post-v1-features.md lines 43, 66 — `ghostty_surface_preedit()`
  present despite CTR-01 removal → **FIXED** (issue-reviewer dismissed as
  non-normative, but team-lead applied fix per prior user direction)

**Phase 2 (history-guardian + issue-reviewer):**

- S-02 dismissed by issue-reviewer as "non-normative scope creep" — overridden
  (fixed anyway per user direction)
- All other issues confirmed as genuine

**Fix Round 1:**

- C-01, C-02, S-02 all fixed by team-lead (hook error blocked Agent spawning)
- C-03/R5: v1.0-r7 doc fully reverted (ToC + Doc 05 row); R5 status updated to
  CANCELLED in resolution doc

**Dismissed issues summary for Round 2:**

- S-02 fixed despite dismissal — do NOT re-raise `ghostty_surface_preedit()` in
  99-post-v1-features.md

### Round 2 ✅

**Phase 1 (consistency-verifier + semantic-verifier):**

- S-01 [critical]: Doc 05 §5.2 table used `"timeout"` instead of normative
  `"client_evicted"` → **FIXED** (table updated to `"client_evicted"` with
  T=300s description)
- S-02 [minor]: Doc 05 §6.2 stated 30-second timeout vs T=300s in §2.3 / doc 06
  health escalation → **FIXED** (updated to T=300s, PreeditEnd
  reason=`"client_evicted"` made explicit)
- S-03 [minor]: Doc 05 §5.2 "always produces PreeditStart" false for
  disconnect/timeout cases → **FIXED** (differentiated by case:
  `replaced_by_other_client` gets PreeditStart, others do not)
- C-R2-01 [critical]: Doc 02 header/changelog still said v0.11 / 2026-03-10 →
  **FIXED** (header updated to v1.0-r12/2026-03-14; v1.0-r12 changelog entry
  added)
- C-R2-02 [minor]: Doc 02 lines 494/499/500 referenced non-existent doc 06
  §1.5/§1.6 → **FIXED** (updated to §1.2, all 3 locations)
- C-R2-03 [minor]: Doc 02 line 984 v0.6 changelog referenced non-existent doc 05
  §5.3 → **FIXED** (updated to §5.2)

**Phase 2 (history-guardian + issue-reviewer):**

- All 6 confirmed (history-guardian 6/6 confirm; issue-reviewer 5/6 confirm,
  C-R2-03 dismiss — overridden by history-guardian's explicit broken-reference
  rule)

**Fix Round 2:**

- All 6 fixes applied by team-lead directly

**Dismissed issues summary for Round 3:**

- (none — all issues were fixed)

### Round 3 ✅

**Phase 1 (consistency-verifier + semantic-verifier):**

- S-R12-01 [minor]: Doc 05 §6.3 used "ghostty surface"/"ghostty-internal" —
  implementation-internal language missed by the R7 fix (§6.3 not in original
  7-location enumeration) → **FIXED** (replaced with "server repositions preedit
  cells internally" and "server-internal")
- R3-01 [critical]: Three locations (doc 02 line 689, doc 03 line 200, doc 05
  §13.2 line 744) referenced "doc 06 Section 2.2" for socket write priority
  model, but §2.2 is the Message Types table → **FIXED** (added "context before
  content" / socket write priority model definition to doc 06 §2.3; updated all
  3 cross-references to §2.3)

**Phase 2 (history-guardian + issue-reviewer):** Both confirmed both issues (4/4
confirm, 0 dismiss).

**Fix Round 3:** All 5 edits applied by team-lead directly.

**Dismissed issues summary for Round 4:**

- (none — all issues were fixed)

### Round 4 ✅

**Phase 1 (consistency-verifier + semantic-verifier):** 8 issues found. **Phase
2 (issue-reviewer-fast + issue-reviewer-deep):** 7 confirmed, 1 dismissed (C4-03
— historical changelog record).

See `verification/round-4-issues.md` for full details.

**All 7 confirmed issues are pre-existing** (not caused by v1.0-r12
resolutions).

| Issue | Description                                           | Resolution                                                 |
| ----- | ----------------------------------------------------- | ---------------------------------------------------------- |
| C4-01 | Wrong message type names in Doc 01 §5.6 / Doc 02 §9.9 | **FIXED**                                                  |
| C4-02 | Broken cross-ref in Doc 06 §10 timeout table          | **FIXED**                                                  |
| S4-01 | Missing DestroySessionResponse state transition       | **FIXED**                                                  |
| S4-02 | AttachOrCreateRequest missing fields                  | **DEFERRED** — ADR 00003 (merge into AttachSessionRequest) |
| S4-03 | ClipboardWrite OSC 52 procedure + encoding asymmetry  | **DEFERRED** — ADR 00004 (symmetric encoding field)        |
| S4-04 | `pane_remains: true` contradicts v1 auto-close        | **FIXED** (field removed, moved to post-v1)                |
| S4-05 | Stale parenthetical in reserved range annotation      | **FIXED**                                                  |

**Round 5 not needed**: all fixes are mechanical (no semantic changes). Owner
declared CLEAN.

## Phase 6: Commit (3.9) ✅

- [x] Commit `draft/v1.0-r12/`
- [x] Report to owner

## Phase 7: Owner Review Cleanup (post-commit)

Owner review identified structural improvements beyond v1.0-r12 resolutions.
Work in progress — session split point.

### Completed

- [x] Version naming: `v0.12` → `v1.0-r12` throughout all r12 docs
- [x] Metadata format: convert all `**Key**: value` to `- **Key**: value` bullet
      items (deno fmt compatibility)
- [x] Strip non-essential metadata (Status, Version, Author, Depends on, Changes
      from) from spec doc headers — Date and Scope only per AGENTS.md
- [x] Remove `# NN —` / `# NN -` prefixes from doc 03–06 titles
- [x] ADR migration: 19 decided items from Doc 01 §11.3 → ADR 00005–00015
- [x] ADR migration: 10 decided items from Doc 02 §12 → ADR
      00006/00010/00013/00016
- [x] Remove Doc 02 §12 (3 remaining proposed items already covered by ADRs)
- [x] Remove Doc 02 §5 CJK Capability Flags (non-negotiable, always supported)
  - Deleted `cjk_capabilities` from ClientHello/ServerHello
  - Deleted §9.1 CJK Capability Fallback
  - Renumbered sections 6→5 through 13→12
- [x] Remove Changelog sections from Doc 01, 02, 03, 06
- [x] Remove Cursor Blink normative note from Doc 03 (duplicate of Doc 04)
- [x] Split Doc 03 Message Type Assignments into subsection tables
- [x] Move JSON Payload Conventions from Doc 03 to Doc 01 §3.6
- [x] Clean up Doc 03 §5.2 resize rationale (move to ADR 00012)
- [x] Remove Doc 03 §8.3 Window Size (duplicate of §5.2)
- [x] ADR 00017: Pane minimum size (2x1), remove Doc 03 §10 Open Questions
- [x] Move Doc 03 §5.3–5.6 resize internals to daemon CTR-01
- [x] Remove Doc 04 Changes from v0.11/v0.8/v0.7/v0.6
- [x] Remove Doc 04 §1.2 header duplication (cross-ref to Doc 01 §3.1)
- [x] Remove Doc 04 JSON encoding rationale (duplicate of ADR 00006)
- [x] Remove Doc 04 §2.8 Readonly restrictions (duplicate of Doc 03 §9)
- [x] Remove Doc 04 IME routing validation (canonical in IME contract)
- [x] Remove Doc 04 Wire-to-IME KeyEvent Mapping (canonical in daemon docs)
- [x] Move Doc 04 Korean composition example to daemon CTR-03
- [x] Move Doc 04 MouseButton preedit interaction to daemon CTR-04 (gap noted)
- [x] ADR 00018: Multiplexed input channel; move §3 to daemon CTR-05

### Remaining (next session)

- [x] Continue Doc 04 owner review — complete (owner-review-cleanup-todo.md File
      3 ✅; 15 cleanup items applied, ADRs 00021/00022/00025 written, CTRs
      extended, IME CTRs written; §10 Open Questions deleted; Appendix B v0.8
      comparison para deleted)
- [ ] Doc 05 owner review
- [x] Doc 06 owner review ✅ (§11 Open Questions all resolved; ADR 00035–00038,
      CTR-13 written)
- [ ] Doc 03 remaining cleanup (if any)
- [ ] Final commit and handover
