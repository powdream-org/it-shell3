# Cross-Team Requests

## Location and Naming

Cross-team requests are placed according to the target team's current state.
**Always check the target topic's directory first** to determine which case
applies.

**Case A — target team has an active draft** (`draft/vX.Y-rN/` exists and is in
progress):

```
{target-team}/draft/vX.Y-rN/cross-team-requests/{NN}-{source-team}-{topic}.md
```

**Case B — target topic has no prior drafts** (brand-new topic):

Create a seed round `r0` containing only the CTR and a handover. No spec
documents or other process artifacts are created in `r0`.

```
{target-team}/draft/v1.0-r0/cross-team-requests/{NN}-{source-team}-{topic}.md
{target-team}/draft/v1.0-r0/handover/handover-to-r1.md
```

The `r1` team leader consumes the seed round during Requirements Intake (step
3.1), just as they would consume any other handover and CTR.

**Case C — target team is idle** (stable `vX.Y/` declared, no new draft started
yet):

```
{target-team}/inbox/cross-team-requests/{NN}-{source-team}-{topic}-from-v{X.Y}.md
```

> **⚠️ `inbox/` is ONLY for Case C.** If the target has an active draft (Case A)
> or the topic is new (Case B), do NOT use `inbox/`.

The `-from-v{X.Y}` suffix (Case C only) encodes the source team's version that
produced the request, so the target team can identify the origin by filename
alone (without opening the file). The `{X.Y}` is the source team's minor version
(e.g., `v0.7`); the round number is omitted as it is not meaningful to the
receiving team.

The `inbox/` directory is unversioned. The target team's leader consumes all
`inbox/cross-team-requests/` files during the next Requirements Intake (step
3.1) and moves them into the new `draft/vX.Y-r1/cross-team-requests/` directory
at that time (dropping the `-from-v{X.Y}` suffix, as the draft path provides
context).

| Component       | Rule                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------- |
| `{NN}`          | Two-digit sequential number, starting at `01`.                                              |
| `{source-team}` | The team that produced the request (e.g., `ime`, `protocol`).                               |
| `{topic}`       | Short kebab-case slug describing the change (e.g., `per-session-engine`, `keyframe-model`). |
| `{X.Y}`         | Source team's minor version that produced the request (inbox only).                         |

## When Created

During the Revision Cycle (step 3.4), when a team's design decisions require
changes in another team's documents. The resolution document (step 3.3)
identifies which changes affect other teams; the core member writes the
cross-team request during document writing.

## File Format

```markdown
# {Title}

- **Date**: YYYY-MM-DD
- **Source team**: {team that produced this request}
- **Source version**: {draft version of the source team's docs that produced
  this, e.g., "IME contract draft/v1.0-r3"}
- **Source resolution**: {resolution document that drove this change, if
  applicable}
- **Target docs**: {list of target spec documents affected}
- **Status**: open | applied in draft/vX.Y-rN | deferred to draft/vX.Y-rN |
  deferred to vX.Y

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
| ---------- | --------------- | ----------- | ----------------- |
| ...        | ...             | ...         | ...               |
```

## Discovery

The target team's leader discovers cross-team requests when starting a Revision
Cycle (step 3.1 Requirements Intake). They are listed as an input source
alongside review notes, handover documents, and PoC findings.

Cross-team requests do NOT appear in the source team's handover document.
However, the **target team's** handover MUST mention incoming cross-team
requests so the next revision's team leader discovers them during requirements
intake.

## Relationship to Other Artifacts

- Cross-team requests are NOT review notes. Review notes are created by the
  owner during the Review Cycle. Cross-team requests are created by a team
  during the Revision Cycle.
- Cross-team requests are driven by design resolutions. The source team's
  resolution document identifies the cross-team impact; the request provides
  actionable instructions for the target team.
