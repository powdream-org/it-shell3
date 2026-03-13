# Verification Round 3 Issues

**Round**: 3
**Date**: 2026-03-08
**Verifiers**: r3-cross-ref, r3-history, r3-semantic, r3-terminology
**Consensus**: 4/4 unanimous on all issues
**Round 2 fixes**: All 4 verified correct
**Cascading assessment**: NOT cascading. Regressions per round: R1→R2: 1 critical, R2→R3: 1 minor. Converging.

---

## Confirmed Issues (3, all minor)

### R3-S01 — minor — regression (introduced by Round 2 V2-01 fix)

**Source documents**: Doc 04 §4.1 — two normative MUSTs with unstated precedence

**Description**: The V2-01 fix correctly removed the `frame_type=2` liveness mechanism for undersized panes. However, the same §4.1 section now contains two MUSTs without explicit precedence: (1) "server MUST suppress FrameUpdate" for undersized panes, and (2) "server MUST set `frame_type=2`" for unchanged payloads. An idle pane that becomes undersized satisfies both conditions simultaneously.

**Expected correction**: Add clarifying sentence: "Dimension-based suppression takes precedence; no FrameUpdate is sent for undersized panes regardless of payload identity."

**Fix applied**: Yes — single clarifying sentence added to doc 04 §4.1 minimum dimensions normative.

**Consensus note**: All 4 verifiers confirmed.

---

### R3-T01 — minor — pre-existing (out of v0.9 scope)

**Source documents**: Doc 03 §1.6 and §1.14

**Description**: Both attachment responses describe initial frame delivery as "A full I-frame (`frame_type=2`) for each visible pane from the shared ring buffer." The parenthetical `(frame_type=2)` incorrectly implies the ring always delivers frame_type=2 on attach. In reality, the ring's latest I-frame may be frame_type=1 or frame_type=2.

**Expected correction**: Replace "(frame_type=2)" with "(frame_type=1 or frame_type=2)" in both sections.

**Fix applied**: No — doc 03 was NOT modified in v0.9. Carried over to v0.10.

**Consensus note**: All 4 verifiers confirmed. History guardian noted this is a v0.8 regression.

---

### R3-C01 — minor — pre-existing (exposed by Round 1 V1-05 fix)

**Source documents**: Doc 01 §9.1

**Description**: JSON metadata blob listed as ~200 B in the component table, but the stated total of ~33 KB requires ~1,700 B (matching doc 04 §7.2 I-frame computation). The ~200 B is a P-frame cursor-only estimate, erroneously used in an I-frame context. With ~200 B, components sum to ~31 KB, not ~33 KB.

**Expected correction**: Update JSON metadata line to ~1,700 B with I-frame breakdown.

**Fix applied**: Yes — updated to "~1,700 B | Full I-frame: cursor, colors (fg + bg + 256-entry palette = 768 B), dimensions, terminal modes, mouse state."

**Consensus note**: All 4 verifiers confirmed.

---

## Dismissed Issues

- **R3-S04** (scroll recovery gap): False alarm. Scroll is a transient per-client view into scrollback; ContinuePane correctly returns client to live terminal state via ring I-frame. Doc 06 §2.3 documents the exception without contradicting any invariant. Unanimously dismissed.
