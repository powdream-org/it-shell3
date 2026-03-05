# Review Notes and Handover Document Conventions

This document standardizes the structure, naming, format, and content of review
artifacts produced during the design workflow (see
[Agent Team Design Workflow](../work-styles/agent-team-design-workflow.md)).

---

## 1. Directory Structure

Each version directory contains two subdirectories for review artifacts:

```
docs/{component}/02-design-docs/{topic}/v<X>/
├── 01-spec-doc.md
├── 02-spec-doc.md
├── ...
├── design-resolutions-{topic}.md       (if produced during this version)
├── research-{source}-{topic}.md        (if produced during this version)
├── review-notes/
│   ├── 01-{topic}.md
│   ├── 02-{topic}.md
│   ├── 03-{topic}.md
│   └── ...
└── handover/
    └── handover-to-v<next>.md
```

**Design resolutions** and **research reports** remain at the version directory level
(not inside subdirectories) because they are produced by the design team as part of
the design process, not as review output.

---

## 2. Review Notes

### 2.1 Location and Naming

```
v<X>/review-notes/{NN}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `{NN}` | Two-digit sequential number, starting at `01`. Monotonically increasing within the version — never reused, never reordered. |
| `{topic}` | Short kebab-case slug describing the concern (e.g., `resize-clipping`, `output-delivery-architecture`, `stale-client-disconnect`). |

New issues get the next available number. There is no distinction by source (owner,
team, verification) in the filename — who raised it is recorded inside the file.

### 2.2 When Review Notes Are Created

| Source | When |
|--------|------|
| **Owner review** | Owner identifies issues during spec review. One file per topic. |
| **Cross-document verification** (Phase 3b) | Verification agents find inconsistencies. One file per topic (not one giant file). |
| **Cross-component review** (Phase 2b) | Cross-component reviewers find interface mismatches. One file per topic. |

**Agent team design discussions (Phase 2) do NOT produce review-notes files.** The
team discusses, reaches consensus, and produces `design-resolutions-{topic}.md` or
`review-resolutions-{NN}.md` directly. Review notes are for issues that need to be
tracked and resolved in a future revision, not for recording in-progress debate.

### 2.3 File Format

Every review note file MUST follow this structure:

```markdown
# {Title}

**Date**: YYYY-MM-DD
**Raised by**: {who — "owner", agent name, or "verification team"}
**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Affected docs**: {list of affected spec documents}
**Status**: open | resolved in v<Y> | deferred to v<Y>

---

## Problem

{What is wrong, what is missing, or what question needs answering.
Be specific — cite section numbers, field names, line numbers where relevant.}

## Analysis

{Why this matters. Include:
- Quantified impact if applicable (e.g., memory usage, bandwidth, O(N) complexity)
- Trade-off analysis if multiple approaches exist
- Prior art references if relevant
- Relationship to other review notes (by number) if coupled}

## Proposed Change

{What should change. For open design questions, present options clearly:

**Option A**: {description}
- Pro: ...
- Con: ...

**Option B**: {description}
- Pro: ...
- Con: ...

For straightforward fixes, just state the required change.}

## Owner Decision

{If the owner made a binding decision, record it here with rationale.
If left to designers, state: "Left to designers for resolution."}

## Resolution

{Filled when the issue is resolved. State what was done and in which version.
Leave empty while the issue is open.}
```

### 2.4 Severity Levels

| Severity | Definition |
|----------|-----------|
| **CRITICAL** | Incorrect behavior, missing normative content, protocol inconsistency, architectural flaw |
| **HIGH** | Important gap affecting implementors — missing fields, stale cross-references, undocumented behavior |
| **MEDIUM** | Should be fixed but does not block implementation — terminology drift, unclear prose |
| **LOW** | Cosmetic — typos, formatting, redundant descriptions |

### 2.5 Cross-References

When review notes reference each other (e.g., coupled issues), use the number:
"See `03-keyframe-model.md`" or "Depends on issue 03 (keyframe model)."

---

## 3. Handover Documents

### 3.1 Location and Naming

```
v<X>/handover/handover-to-v<next>.md
```

One handover per version. Written at session end when the review round completes.

### 3.2 Purpose

The handover captures **what is NOT in the review notes** — context, perspective,
and judgment that would otherwise be lost between sessions. The reader is expected to
read all review notes in `v<X>/review-notes/` independently; the handover does not
repeat their content.

### 3.3 File Format

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

### 3.4 What Does NOT Go in a Handover

| Do not include | Why | Where it belongs |
|----------------|-----|-----------------|
| Per-issue details (problem, analysis, proposed fix) | Duplicates review notes | `review-notes/{NN}-{topic}.md` |
| Per-document change checklists | Derived from review notes at apply time | Phase 3 task descriptions |
| File location indexes | Filesystem is the source of truth | `ls v<X>/review-notes/` |
| Team composition recommendations | May not apply to next session | Workflow doc or agent definitions |

---

## 4. Design Resolutions

```
v<X>/design-resolutions-{topic}.md
```

Produced by the design team (Phase 2) when discussion reaches consensus on new
design decisions. Lives at the version directory level (not inside `review-notes/`).

### Required Content

- Each resolution: consensus count (e.g., "3/3"), decision statement, rationale
- Wire protocol changes summary (if applicable)
- Items deferred to future versions (if any)
- Prior art references used as evidence

---

## 5. Research Reports

```
v<X>/research-{source}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `{source}` | Reference codebase analyzed (e.g., `tmux`, `zellij`, `ghostty`). |
| `{topic}` | What was researched (e.g., `resize-health`, `dirty-tracking`). |

### Required Content

- Specific source file paths and function/struct names from the reference codebase
- Factual findings only — no design recommendations
- Trade-offs observed (what works well, what doesn't)
- Known bugs or limitations in the reference implementation

---

## 6. Review Resolutions

```
v<X>/review-resolutions-{NN}.md
```

`{NN}` matches the review round it resolves. Produced when the team agrees on fixes
to review-note issues. Lives at the version directory level.

---

## 7. Anti-Patterns

| Anti-pattern | Problem | Correct approach |
|-------------|---------|-----------------|
| One giant review-notes file with 20+ issues | Hard to track, hard to resolve individually | One file per topic |
| Handover that repeats review notes content | Duplication, divergence risk | Handover captures insights only; reader reads review notes separately |
| Review notes without severity | No prioritization | Always assign severity |
| Review notes without status | Can't tell what's resolved | Always maintain status field |
| Agent team review producing review-notes files | Confuses tracking — team resolves issues inline | Team produces design-resolutions or review-resolutions, not review-notes |
| Mixing multiple unrelated topics in one review note | Hard to track resolution independently | One topic per file, even if both are LOW severity |
