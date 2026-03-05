# Cross-Team Requests

## Location and Naming

Cross-team requests are placed in the TARGET team's version directory, not the source team's.

```
{target-team}/v<X>/cross-team-requests/{NN}-{source-team}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `{NN}` | Two-digit sequential number, starting at `01`. |
| `{source-team}` | The team that produced the request (e.g., `ime`, `protocol`). |
| `{topic}` | Short kebab-case slug describing the change (e.g., `per-session-engine`, `keyframe-model`). |

## When Created

During the Revision Cycle (step 3.4), when a team's design decisions require changes
in another team's documents. The resolution document (step 3.3) identifies which
changes affect other teams; the core member writes the cross-team request during
document writing.

## File Format

```markdown
# {Title}

**Date**: YYYY-MM-DD
**Source team**: {team that produced this request}
**Source version**: {version of the source team's docs that produced this, e.g., "IME contract v0.6"}
**Source resolution**: {resolution document that drove this change, if applicable}
**Target docs**: {list of target spec documents affected}
**Status**: open | applied in v<Y> | deferred to v<Y>

---

## Context

{Brief explanation of the source team's design decision that drives this change.
The reader should understand WHY the change is needed without reading the full
source resolution.}

## Required Changes

{Numbered list of specific changes. Each change should specify:
- Which document / section / message is affected
- What the current content says (if updating)
- What it should say after the change
- Rationale tying back to the source decision}

## Summary Table

| Target Doc | Section/Message | Change Type | Source Resolution |
|-----------|----------------|-------------|-------------------|
| ... | ... | ... | ... |
```

## Discovery

The target team's leader discovers cross-team requests when starting a Revision
Cycle (step 3.1 Requirements Intake). They are listed as an input source alongside
review notes, handover documents, and PoC findings.

Cross-team requests do NOT appear in the source team's handover document — the
file's presence in the target team's directory is sufficient for discovery.

## Relationship to Other Artifacts

- Cross-team requests are NOT review notes. Review notes are created by the owner
  during the Review Cycle. Cross-team requests are created by a team during the
  Revision Cycle.
- Cross-team requests are driven by design resolutions. The source team's
  resolution document identifies the cross-team impact; the request provides
  actionable instructions for the target team.
