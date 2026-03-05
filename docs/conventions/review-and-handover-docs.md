# Review Notes and Handover Document Conventions

This document standardizes the naming, format, and content of review artifacts
produced during the design workflow (see
[Agent Team Design Workflow](../work-styles/agent-team-design-workflow.md)).

---

## 1. Artifact Types

The design workflow produces the following artifact types. Each type has a distinct
purpose, author, and naming convention.

| Type | Purpose | Author | Workflow phase |
|------|---------|--------|---------------|
| **Review notes** | Issues found during review | Varies (see subtypes) | Phase 2, 2b, 3b, or owner |
| **Review resolutions** | Agreed fixes to review-note issues | Consensus reporter | Phase 2 output |
| **Design resolutions** | New design decisions from team discussion | Discussion participants | Phase 2 output |
| **Research reports** | Findings from reference codebase analysis | Research agents | Pre-Phase 2 or Phase 2 |
| **Handover documents** | Session-end context transfer for next revision | Team lead or doc owners | Phase 4 |

---

## 2. File Location

All artifacts live in the **version directory** of the spec area they belong to:

```
docs/{component}/02-design-docs/{topic}/v<X>/
```

`<X>` is the version identifier (e.g., `0.6`, `1`, `2.1`).

Examples:
```
docs/libitshell3/02-design-docs/server-client-protocols/v0.6/review-notes-01-resize-policy.md
docs/libitshell3-ime/02-design-docs/interface-contract/v1/handover-for-v2-revision.md
```

---

## 3. Naming Conventions

### 3.1 Review Notes

Review notes are categorized by **who raised the issues** and **what type of review**
produced them. The filename encodes both.

#### Pattern

```
review-notes-{type}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `review-notes` | Fixed prefix. Always present. |
| `{type}` | Review type identifier (see table below). |
| `{topic}` | Optional. Short descriptive slug. Use when the version has multiple review-note files of the same type. Omit when there is only one file of that type. |

#### Review Type Identifiers

| Type ID | Workflow phase | Who raises issues | When to use |
|---------|---------------|-------------------|-------------|
| `{NN}` (two-digit number) | Phase 2 (team review) | Core team agents | Sequential numbering within a version. First team review = `01`, second = `02`, etc. |
| `cross-{counterpart}` | Phase 2b (cross-component) | Mixed team from both spec areas | `{counterpart}` = the other spec area's short name (e.g., `ime`, `protocol`). |
| `consistency` | Phase 3b (verification) | Fresh verification agents | One file per verification pass. If multiple rounds produce separate files, append round number: `consistency-r2`. |
| `owner-{topic}` | Owner review | Project owner | Owner's own review observations. `{topic}` describes the concern area. |

#### Examples

```
# Team peer review, first round, about resize policy
review-notes-01-resize-policy.md

# Team peer review, second round, about encoding decisions
review-notes-02-encoding-and-fps.md

# Team peer review, only one review in this version (topic optional)
review-notes-01.md

# Cross-component review: protocol team reviewing against IME contract
review-notes-cross-ime.md

# Cross-component review: IME team reviewing against protocol docs
review-notes-cross-protocol.md

# Consistency verification (Phase 3b)
review-notes-consistency.md

# Owner review about output delivery architecture
review-notes-owner-output-delivery.md

# Owner review about general decisions
review-notes-owner-decisions.md
```

### 3.2 Review Resolutions

```
review-resolutions-{NN}.md
```

`{NN}` matches the review-notes number it resolves. If resolving multiple review
rounds, use the latest round number.

Example: `review-resolutions-01.md` resolves issues from `review-notes-01-*.md`.

### 3.3 Design Resolutions

```
design-resolutions-{topic}.md
```

Design resolutions capture new design decisions that emerged from team discussion,
as opposed to review resolutions which fix existing spec issues. The `{topic}` is
a short descriptive slug.

Example: `design-resolutions-resize-health.md`

### 3.4 Research Reports

```
research-{source}-{topic}.md
```

| Component | Rule |
|-----------|------|
| `research` | Fixed prefix. |
| `{source}` | Reference codebase analyzed (e.g., `tmux`, `zellij`, `ghostty`, `iterm2`). |
| `{topic}` | What was researched (e.g., `resize-health`, `client-protocol`, `ime-handling`). |

Examples:
```
research-tmux-resize-health.md
research-zellij-resize-health.md
research-ghostty-dirty-tracking.md
```

### 3.5 Handover Documents

```
handover-for-v<next>-revision.md        # Standard: next-version handover
handover-{topic}.md                     # Special: topic-specific handover
```

Standard handovers are written at session end. Topic-specific handovers are written
when a particular design area reaches a milestone (e.g., consensus on a contested
topic) and needs its own focused context transfer.

Examples:
```
handover-for-v07-revision.md
handover-identifier-consensus.md
```

---

## 4. Document Format

### 4.1 Review Notes

All review notes MUST follow this structure:

```markdown
# Review Notes: {version} {Description}

**Date**: YYYY-MM-DD
**Reviewers**: {who reviewed — agent names, "owner", or "verification team"}
**Scope**: {what was reviewed — which docs, which aspects}
**Verdict**: {N} issues found ({breakdown by severity})

> **Related review notes:**
> - `other-review-notes-file.md` -- brief description
> (list all sibling review-note files in the same version directory)

---

## Issue List

### {Document or Section Name}

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 1 | **CRITICAL** | Sec N.N | What is wrong and what needs to change | Which resolution/decision |

(repeat per document or logical group)

---

## Summary Statistics

| Severity | Count | Affected docs |
|----------|-------|---------------|
| CRITICAL | N | Doc X (n), Doc Y (n) |
| HIGH | N | ... |
| MEDIUM | N | ... |
| LOW | N | ... |

**By document:**

| Document | CRITICAL | HIGH | MEDIUM | LOW | Total |
|----------|----------|------|--------|-----|-------|
| Doc X | ... | ... | ... | ... | ... |
```

#### Severity Levels

| Severity | Definition | Examples |
|----------|-----------|---------|
| **CRITICAL** | Incorrect behavior, missing normative content, protocol inconsistency | Missing message type, wrong algorithm, contradicting resolutions |
| **HIGH** | Important gap or inconsistency that affects implementors | Missing fields, stale cross-references to wrong sections, undocumented behavior |
| **MEDIUM** | Should be fixed but does not block implementation | Terminology drift, missing convenience fields, unclear prose |
| **LOW** | Cosmetic or stylistic | Typos in prose notes, formatting inconsistencies, redundant descriptions |

#### Issue Numbering

- Issues are numbered **sequentially within a single review-notes file**, starting at 1.
- Issue numbers are **local to the file** — different review-notes files in the same
  version may reuse numbers.
- When referencing issues across files, use the filename: "Issue 3 in
  `review-notes-owner-output-delivery.md`".
- Confirmations (verified-OK checks) use the same numbering but are marked as
  severity `NONE`.

### 4.2 Design Resolutions

```markdown
# Design Resolutions: {Topic}

**Version**: v<X>
**Date**: YYYY-MM-DD
**Status**: Resolved / Partially resolved
**Participants**: {agent names}
**Discussion rounds**: {N}
**Source issues**: {which review notes or owner questions triggered this}

---

## Resolution {N}: {Title}

**Consensus ({N}/{total}).** {Decision statement.}

**Rationale**: {Why this was chosen over alternatives.}

(optional: implementation sketch, prior art references, wire protocol changes)
```

#### Requirements

- Each resolution MUST state the consensus count (e.g., "3/3" or "2/3 with dissent").
- Each resolution MUST have a rationale — never just state the decision without why.
- If the resolution changes wire protocol, include a "Wire Protocol Changes Summary"
  section at the end listing: new message types, modified messages, affected docs.
- If the resolution defers items to a future version, list them explicitly in a
  "Deferred to v<next>" section.

### 4.3 Research Reports

```markdown
# Research: {Source} — {Topic}

**Date**: YYYY-MM-DD
**Researcher**: {agent name}
**Source codebase**: {path, e.g., ~/dev/git/references/tmux/}
**Requested by**: {who asked for this research, e.g., review-notes-01 Issue 2}

---

## Findings

### {Subtopic}

{How the reference codebase handles this problem.}

**Source references:**
- `path/to/file.c` -- {function/struct name}: {what it does}
- `path/to/other.c` -- {function/struct name}: {what it does}

### Trade-offs Observed

{What works well, what doesn't, known issues in the reference implementation.}
```

#### Requirements

- Research reports MUST include specific source file paths and function/struct names.
- Research reports MUST NOT include design recommendations — only factual findings.
  Core team members incorporate findings into their designs.
- If the reference codebase has known bugs or limitations relevant to the topic,
  document them explicitly.

### 4.4 Handover Documents

```markdown
# Handover: {Spec Area} v<X> to v<next> Revision

> **Date**: YYYY-MM-DD
> **Author**: {team-lead or expert agent name}
> **Scope**: {what this handover covers}
> **Prerequisite reading**: {files the next session MUST read before starting}

---

## 1. What was accomplished

{Summary of completed work — review rounds, resolutions reached, docs revised.}

## 2. Open items for next revision

### Priority 1: {Category}

{Detailed per-document breakdown of required changes, with issue references.}

### Priority 2: {Category}

{Design questions requiring team discussion, with full problem statements.}

(continue with Priority 3, 4, etc. as needed)

## 3. Pre-discussion research tasks

{Research that MUST be completed before the team discusses open design questions.}

## 4. Recommended workflow

{Step-by-step plan for the next session, with phase ordering and dependencies.}

## 5. Key decisions log

{Owner decisions that constrain the next revision. Format as a table:}

| Decision | Context | Constraint |
|----------|---------|------------|

## 6. File locations

{Complete table of all artifacts — spec docs, review notes, research, handovers.}
```

#### Requirements

- Handovers MUST be self-contained — readable without opening any other file.
- Handovers MUST distinguish between decided issues (apply without debate) and
  open questions (need team discussion first).
- Handovers MUST include file paths, not just descriptions.
- The "Key decisions log" section MUST include owner decisions that should not be
  re-debated. State the rationale to prevent the next session from questioning them.

---

## 5. Cross-References Between Files

When a version directory contains multiple review-notes files, each file MUST include
a "Related review notes" block in its header listing all sibling files:

```markdown
> **Related review notes:**
> - `review-notes-01-resize-policy.md` -- Team review: resize and health issues (8 items)
> - `review-notes-consistency.md` -- Verification: unapplied design resolutions (17 items)
> - `review-notes-owner-output-delivery.md` -- Owner review: frame delivery architecture (4 items)
```

Handover documents MUST reference all review-notes files in their "File locations"
section.

---

## 6. Lifecycle: When to Create Each Artifact

```
Phase 1 (drafting)
  └── research-{source}-{topic}.md          (if prior art needed)

Phase 2 (review)
  ├── review-notes-{NN}-{topic}.md          (team review findings)
  ├── design-resolutions-{topic}.md         (new design decisions, if any)
  └── review-resolutions-{NN}.md            (agreed fixes)

Phase 2b (cross-component review)
  ├── review-notes-cross-{counterpart}.md   (per component side)
  └── review-resolutions-{NN}.md            (if changes agreed)

Phase 3 (applying revisions)
  └── (spec docs updated — no new artifacts)

Phase 3b (verification)
  └── review-notes-consistency.md           (verification findings)

Phase 4 (handover)
  └── handover-for-v<next>-revision.md       (session-end context transfer)

Owner review (any time)
  └── review-notes-owner-{topic}.md         (owner observations)
```

---

## 7. Anti-Patterns

| Anti-pattern | Problem | Correct approach |
|-------------|---------|-----------------|
| Unnamed review notes (`review-notes.md`) | Ambiguous when multiple exist | Always include type ID |
| Mixing team review and owner review in one file | Different authority levels, different audiences | Separate files per review type |
| Review notes without severity levels | No prioritization for implementors | Always assign CRITICAL/HIGH/MEDIUM/LOW |
| Review notes without summary statistics | Hard to gauge scope of work | Always include severity × document breakdown |
| Handover without file paths | Next session wastes time finding artifacts | Always include full paths |
| Handover that says "see review notes for details" | Not self-contained | Include enough detail to start work without opening other files |
| Numbered issues that span multiple files | Confusing references ("Issue 23" — which file?) | Numbers are local to each file; cross-reference with filename |
| Research reports with design recommendations | Mixes facts with opinions | Researchers report findings only; core members design |
| Modifying review notes after issues are applied | Creates confusion about what was fixed | Mark issues as resolved inline or create a new review-notes file for the next round |
