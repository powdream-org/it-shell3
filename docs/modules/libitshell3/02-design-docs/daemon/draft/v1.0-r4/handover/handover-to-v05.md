# Handover: Daemon Design v0.4 to v0.5

**Date**: 2026-03-13
**Author**: team leader

---

## Insights and New Perspectives

**Version header hygiene**: Every verification round found at least one doc with a stale version header. Future revision cycles should update version headers as a mandatory first step in the writing phase (Section 3.5), before verification begins.

**Pre-existing issues in "unchanged" docs**: Doc04 was marked "unchanged" in v0.4 but accumulated 3 issues during verification. Verification reads all docs, not just changed ones — this is correct behavior. Future cycles should not assume "unchanged" docs are issue-free when read by fresh agents for the first time.

**Historical document rule**: v0.1 design resolution docs must not be modified. They are permanent historical artifacts. Established in v0.4.

**Team leader violations (lessons from this cycle)**:
- The team leader applied Round 1 fixes directly instead of delegating to fix agents. The team leader is a facilitator, not a doer — even mechanical, trivial fixes must be delegated.
- The team leader created this handover and a review note at the end of the Revision Cycle, before the Review Cycle began. Handover must be written only after the owner declares the review cycle complete (Section 4.3). Review notes must be created only when the owner explicitly requests them (Section 4.2).
- A protocol-side observation found during daemon verification was incorrectly filed as a daemon review note. Observations requiring changes in another team's documents must be filed as a cross-team request in the target team's directory — not as a review note in the source team's directory.

## Design Philosophy

None.

## Owner Priorities

None — v0.5 is driven by the owner's review of v0.4 documents.

## New Conventions and Procedures

None.

## Pre-Discussion Research Tasks

None.
