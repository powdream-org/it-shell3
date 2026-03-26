---
name: sip
description: >
  Use when encountering a procedural problem during a running workflow session
  (/implementation or /design-doc-revision). Scaffolds a new SIP file or
  appends an item to the existing one. Also use when the team leader wants to
  log a skill improvement proposal without waiting for the retrospective step.
argument-hint: "<description>"
---

# Skill Improvement Proposal

Log a procedural problem as a SIP item for the current workflow session.

## Usage

```
/sip <one-line description of the procedural problem>
```

## Context Detection

Auto-detect the running workflow and SIP file location:

1. Find `TODO.md` — determines the active session:
   - `<target>/TODO.md` → `/implementation` session
   - `draft/vX.Y-rN/TODO.md` → `/design-doc-revision` session
2. SIP file path:
   - Implementation: `<target>/retrospective/skill-improvement-proposals.md`
   - Design-doc-revision:
     `draft/vX.Y-rN/retrospective/skill-improvement-proposals.md`
3. If no `TODO.md` found → error: "No active workflow session. Run /sip only
   during an /implementation or /design-doc-revision cycle."

## Action

### If SIP file does not exist

Create the directory and file with header + first item:

```markdown
# Skill Improvement Proposals

## SIP-1: <title derived from description>

**Discovered during**: <current step from TODO.md> **What happened**:
<expand from the description argument> **Root cause**:
<ask the user or infer from context> **Affected steps**:
<which skill step files need changes> **Proposed changes**: <specific edits —
anti-patterns, gate conditions, instructions>
```

### If SIP file exists

Read the file, find the highest `SIP-N` number, append `SIP-(N+1)` with the same
format.

## Item Format

Every SIP item has exactly 5 fields:

| Field                 | Content                                                         |
| --------------------- | --------------------------------------------------------------- |
| **Discovered during** | Step name and number from TODO.md's Current State               |
| **What happened**     | Factual description of the procedural failure                   |
| **Root cause**        | Why the process failed — not symptoms, causes                   |
| **Affected steps**    | Which step files in the skill need changes                      |
| **Proposed changes**  | Specific edits: add anti-pattern, clarify gate, fix instruction |

## When to Use

- A step's gate didn't catch a problem it should have
- An anti-pattern was hit that isn't documented
- An instruction was unclear or missing
- The owner had to intervene because the process failed
- A review caught something that an earlier step should have prevented
