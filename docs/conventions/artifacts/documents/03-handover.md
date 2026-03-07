# Handover Documents

## Location and Naming

```
v<X>/handover/handover-to-v<next>.md
```

One handover per version. Written at session end when the review round completes.

## Purpose

The handover captures **what is NOT in the review notes** — context, perspective,
and judgment that would otherwise be lost between sessions. The reader is expected to
read all review notes in `v<X>/review-notes/` independently; the handover does not
repeat their content.

## File Format

```markdown
# Handover: {Spec Area} v<X> to v<next>

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
| Per-issue details (problem, analysis, proposed fix) | Duplicates review notes | `review-notes/{NN}-{topic}.md` |
| Per-document change checklists | Derived from review notes at apply time | Revision Cycle task descriptions |
| File location indexes | Filesystem is the source of truth | `ls v<X>/review-notes/` |
| Team composition recommendations | May not apply to next session | Workflow doc or agent definitions |
