# Review Notes

## Location and Naming

```
v<X>/review-notes/{NN}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `{NN}` | Two-digit sequential number, starting at `01`. Monotonically increasing within the version — never reused, never reordered. |
| `{topic}` | Short kebab-case slug describing the concern (e.g., `resize-clipping`, `output-delivery-architecture`, `stale-client-disconnect`). |

New issues get the next available number. There is no distinction by source (owner,
team, verification) in the filename — who raised it is recorded inside the file.

## When Review Notes Are Created

Review notes are created ONLY during the Review Cycle, when the owner explicitly
instructs the team leader to write one. See
[Design Workflow](../../../work-styles/03-design-workflow.md) Section 4.2.

Agent team discussions during the Revision Cycle do NOT produce review-notes files.
The team discusses, reaches consensus, and produces `design-resolutions-{topic}.md`
or `review-resolutions-{NN}.md` directly. Review notes are for issues that need to
be tracked and resolved in a future revision, not for recording in-progress debate.

## File Format

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

## Severity Levels

| Severity | Definition |
|----------|-----------|
| **CRITICAL** | Incorrect behavior, missing normative content, protocol inconsistency, architectural flaw |
| **HIGH** | Important gap affecting implementors — missing fields, stale cross-references, undocumented behavior |
| **MEDIUM** | Should be fixed but does not block implementation — terminology drift, unclear prose |
| **LOW** | Cosmetic — typos, formatting, redundant descriptions |

## Cross-References

When review notes reference each other (e.g., coupled issues), use the number:
"See `03-keyframe-model.md`" or "Depends on issue 03 (keyframe model)."
