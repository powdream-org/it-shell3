---
name: writing-impl-plan
description: >
  Write or revise an implementation plan as a task breakdown with spec
  references. No code snippets, no test code — the implementer and QA design
  those from the spec.
---

# Writing Implementation Plans

Write or revise a task breakdown that tells the implementer and QA reviewer WHAT
to build and WHERE to look — not HOW to write it.

**Two modes:**

- **Create**: No plan exists. Read the spec, produce the plan.
- **Revise**: Plan exists but verifiers found issues. Read the existing plan and
  the issue list, then fix the plan. Do not rewrite from scratch — address each
  issue.

## Delegation

Plan writing is research-heavy (reading specs, analyzing code, cross-referencing
types and field names). The team leader does not write plans — they delegate to
a subagent and review the result.

**Create mode:**

1. Team leader spawns a general-purpose subagent with:
   - This skill's instructions (the subagent reads this SKILL.md)
   - Spec paths, source directory, ROADMAP entry, and any owner constraints
2. The subagent reads the specs and source, writes the plan per the format below
3. Team leader reviews the result — checks scope, task granularity, spec
   coverage, and red flags

**Revise mode:**

1. Team leader spawns a general-purpose subagent with:
   - This skill's instructions
   - The existing plan path and the numbered issue list from verifiers
2. The subagent reads the plan and issues, applies targeted fixes (not a full
   rewrite)
3. Team leader reviews the changes

The team leader provides paths and constraints. The subagent does the research
and writing.

## Document Authority

The plan is the **second-lowest authority** in the implementation cycle:

1. **Design spec** (highest) — defines types, APIs, behavior
2. **Implementation plan** — organizes work: files, ordering, dependencies
3. **Code** (lowest) — must conform to spec, not plan

The implementer and QA both verify against the **spec**, not the plan. The plan
is a map, not the territory.

## What the Plan Contains

Per task:

- **Files**: create or modify (exact paths)
- **Spec references**: which spec sections define the behavior for this task
- **Verification criteria**: what must be true when the task is done (not test
  code — criteria the QA reviewer uses to derive tests)
- **Dependencies**: which tasks must complete first

Per plan:

- **Header**: goal, architecture summary, tech stack, spec paths
- **Dependency graph**: task ordering
- **Scope**: in-scope / out-of-scope boundary

## What the Plan Does NOT Contain

- Function signatures, struct definitions, or any code snippets — the
  implementer designs these from the spec
- Test code or test case lists — the QA reviewer designs tests from the spec
- Implementation instructions ("call X, then Y, then Z") — that is
  micromanagement
- Allocator choices, buffer sizes, or other implementation decisions — those are
  the implementer's judgment calls

## Task Granularity

Each task produces a **compilable, testable increment**. Not "write line 43" and
not "implement the entire module." A task is typically one file or one cohesive
change to 2-3 files.

## Output Format

Save to: `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`

**After saving the plan**, update `docs/superpowers/plans/ROADMAP.md`:

- Add the plan to the **Plan Index** table with the plan file path and status
  `Not started`
- Add the plan to the **Dependency Graph** if it has dependencies
- Add a **Plan Summary** section with scope, spec refs, and depends-on

```markdown
# <Feature Name> Implementation Plan

**Goal:** <one sentence>

**Architecture:** <2-3 sentences — approach, not implementation detail>

**Tech Stack:** <libraries, dependencies>

**Spec references:**

- <spec-topic/version — path or name>
- ...

---

## Scope

**In scope:** <numbered list matching spec sections>

**Out of scope:** <what this plan does NOT cover, with reason>

**Convention scope rule:** If the plan includes convention fixes (naming,
documentation, testing structure, integer widths, etc.), identify ALL modules in
the project that share the same convention docs. Either include all affected
modules in scope, or explicitly list excluded modules in "Out of scope" with a
follow-up plan reference.

## File Structure

| File                    | Action | Responsibility         |
| ----------------------- | ------ | ---------------------- |
| `src/path/file.zig`     | Create | <one-line description> |
| `src/path/existing.zig` | Modify | <what changes>         |

## Tasks

### Task N: <Name>

**Files:** `src/path/file.zig` (create), `src/path/other.zig` (modify)

**Spec:** <topic> §N.N — <what this section defines>

**Depends on:** Task M

**Verification:** <what must be true — stated as observable criteria, not test
code>

## Dependency Graph

Task 1 → Task 2 → Task 3 ↘ Task 4 (parallel with 3)

## Summary

| Task | Files | Spec Section |
| ---- | ----- | ------------ |
| ...  | ...   | ...          |
```

## Red Flags — You Are Writing Code, Not a Plan

- Function signatures (`fn processKey(...)`)
- Struct definitions (`const Foo = struct { ... }`)
- Step-by-step implementation instructions ("1. Call X, 2. Update Y")
- Test case code or detailed test scenarios
- Allocator or memory strategy choices
- Specific error handling approaches

If you catch yourself writing any of these, delete it and replace with a spec
reference. The implementer reads the spec and makes these decisions.
