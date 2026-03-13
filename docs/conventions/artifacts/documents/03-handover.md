# Handover Documents

## Location and Naming

```
draft/vX.Y-rN/handover/handover-to-r(N+1).md    (more revisions needed)
{topic}/inbox/handover/handover-for-vX.Y.md      (stable declared)
```

When stable is declared, the handover is placed in `inbox/handover/` — the
input tray the next revision cycle team reads during Requirements Intake (3.1).
The next revision cycle's target version (minor bump `vX.(Y+1)` vs. major bump
`v(X+1).0`) is decided by the owner at that Requirements Intake, not at
handover time.

One handover per review cycle completion. Written at the end of every Review Cycle
when the owner declares the review complete (workflow step 4.3).

## Purpose

The handover captures **what is NOT in the review notes** — context, perspective,
and judgment that would otherwise be lost between sessions. The reader is expected to
read all review notes in `draft/vX.Y-rN/review-notes/` independently; the handover
does not repeat their content.

## File Format

```markdown
# Handover: {Spec Area} vX.Y-rN to vX.Y-r(N+1)

**Date**: YYYY-MM-DD
**Author**: {team lead or owner}

---

## Insights and New Perspectives

{What was learned during the review that changed understanding of the
design space. New mental models, reframed problems, shifted priorities.
These are the "aha moments" that review notes don't capture.}

## Design Philosophy

{Architectural principles that emerged or were reinforced. Why certain
directions feel right. The spirit behind the decisions, not just the
letter.}

## Owner Priorities

{What the owner cares about most. Strong preferences, non-negotiable
constraints, quality bars. Things the next session's team must respect
even if they seem debatable in isolation.}

## New Conventions and Procedures

{Any work style changes, naming conventions, workflow adjustments, or
process improvements decided during this session. Link to convention
docs if they were created or updated.}

## Pre-Discussion Research Tasks

{Research that should happen before the next design round begins.
Specify what to investigate, which reference codebases to consult,
and what questions the research should answer.}
```

## Post-Handover: Update Design Principles

After writing the handover, review its §2 (Insights) and §3 (Design Philosophy) against
[`docs/insights/design-principles.md`](../../../../insights/design-principles.md). If a
principle is new, add it. If it reinforces an existing one, update the Origin column. This
ensures validated knowledge graduates from version-specific handovers into a single living
document that agents and humans can consult without reading every handover in history.

## What Does NOT Go in a Handover

| Do not include | Why | Where it belongs |
|----------------|-----|-----------------|
| Per-issue details (problem, analysis, proposed fix) | Duplicates review notes | `draft/vX.Y-rN/review-notes/{NN}-{topic}.md` |
| Per-document change checklists | Derived from review notes at apply time | Revision Cycle task descriptions |
| File location indexes | Filesystem is the source of truth | `ls draft/vX.Y-rN/review-notes/` |
| Team composition recommendations | May not apply to next session | Workflow doc or agent definitions |
