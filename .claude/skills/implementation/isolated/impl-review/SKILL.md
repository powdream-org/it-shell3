---
name: impl-review
description: >
  Run spec compliance review with QA reviewer and development-reviewer, report issues found.
context: fork
---

# Step 8: Spec Compliance Review

## Anti-Patterns

- **Don't let the implementer review their own code.** The QA reviewer does this
  — that's the whole point of role separation.
- **Don't let the QA engineer review their own tests.** The QA reviewer checks
  test completeness against the spec — the person who wrote the tests cannot
  objectively assess their own coverage gaps.
- **Don't accept "it works" as proof of compliance.** Working code can still
  deviate from the spec (extra fields, wrong signatures, unauthorized behavior).
  The QA reviewer checks the spec, not the test results.
- **Don't rush this step.** Spec violations caught here are cheap to fix.
  Violations caught after commit are expensive.
- **Don't verify implementation against itself.** The QA reviewer reads the spec
  independently. "It works" is not compliance — a working implementation can
  still violate the spec's delivery mechanism or API contract. Verify against
  the SPEC, not the plan or the code's apparent intent.
- **Don't edit code directly.** The team leader delegates fixes to the
  implementer or QA engineer. If reviewers find issues, they go through Step 9 —
  the team leader never edits source files.
- **Don't skip convention re-verification.** The development-reviewer must
  re-verify after Step 7 fixes AND after any Step 9 fix cycle, since fixes can
  introduce new convention violations.

## Action

### 8a. Update TODO.md

Update TODO.md: set **Step** to 8 (Spec Compliance Review), mark Step 7 as
`[x]`. Increment **Review Round** if returning from Step 11 regression.

### 8b. Spawn parallel reviews

Spawn **QA reviewer** and **development-reviewer** in parallel:

**QA Reviewer** (`.claude/agents/impl-team/qa-reviewer.md`) — dual review:

```
Perform a dual review of <target>/src/ against the design spec.
Read TODO.md's ## Spec section for all spec paths.

**Part A — Implementation compliance:**
Review all source files (excluding tests) against the design spec. Check:
- Every spec requirement has corresponding code
- Types, field names, and method signatures match the spec EXACTLY
- Error handling matches spec-defined behavior
- Edge cases described in the spec are handled
- No undocumented behavior or implicit assumptions
- No unauthorized extensions (extra fields, methods, parameters)
- Memory ownership rules followed (buffer lifetimes, pointer validity)
- For each public API, cite the spec section that defines it and verify the
  implementation matches the SPEC — not the plan
- For delivery/performance-critical paths, verify the mechanism matches the
  spec (e.g., zero-copy vs copy, writev vs write)

**Part B — Test case completeness:**
Review all spec behavior tests in src/testing/spec/ against the design spec
and scenario matrix. Check:
- Every scenario in the spec's scenario matrix has a corresponding test
- Each test validates the spec requirement it claims to validate
- Test assertions match expected behavior defined in the spec
- No scenarios are missing test coverage
- Tests are derived from the spec, not from the implementation

Report either:
(a) "Clean pass — no issues found in either part", or
(b) A numbered issue list. Prefix each issue with [CODE] or [TEST]:
    [CODE] issues: file:line reference + spec section citation
    [TEST] issues: missing scenario or incorrect test + spec section citation
```

**Development Reviewer** (`.claude/agents/impl-team/development-reviewer.md`) —
convention re-verification:

```
Re-verify all source files in <target>/src/ for convention violations.
Zig version: run `mise current zig` to get the active version.
Zig reference docs: docs/references/<version>/zig-language-reference.html

This is a re-verification after Step 7 fixes. Check for any new violations
introduced by simplify or convention fixes.
Report all violations as a numbered [CONV] issue list.
If no violations: "Clean pass — no convention violations found."
```

### 8c. Collect results

Wait for both reviewers to report.

- **If both clean** → gate is `CLEAN`.
- **If any issues found** → gate is `ISSUES`. Merge issue lists (`[CODE]` +
  `[TEST]` + `[CONV]`) into the payload.

## Gate Verification

Each condition must be verified by the fork before returning.

- [ ] QA reviewer has completed dual review (Part A + Part B)
- [ ] Development-reviewer has completed convention re-verification
- [ ] Result is classified: either `CLEAN` (no issues) or `ISSUES` (merged issue
      list with `[CODE]`/`[TEST]`/`[CONV]` prefixes and unique IDs)
- [ ] Each issue has: unique ID (e.g. `R1-001`), category, file, line,
      spec_section, summary, evidence, and suggested_fix
- [ ] Checkpoint commit performed: `git add -A && git commit` with all changed
      artifacts (TODO.md)

## Return

Return a JSON object conforming to the fork return contract:

```json
{
  "step": 8,
  "gate": "CLEAN | ISSUES",
  "checkpoint": "<commit-sha>",
  "payload": {
    "issues": [
      {
        "id": "<unique ID, e.g. R1-001>",
        "category": "CODE | TEST | CONV",
        "file": "<path>",
        "line": "<number>",
        "spec_section": "<section name or convention rule>",
        "summary": "<one-line description of the issue>",
        "evidence": "<spec quote vs code quote showing the mismatch>",
        "suggested_fix": "<actionable fix description>"
      }
    ]
  }
}
```

**Field semantics:**

- `gate`: `CLEAN` if both QA reviewer and development-reviewer report no issues.
  `ISSUES` if any issues were found by either reviewer.
- `checkpoint`: The SHA of the checkpoint commit created at the end of the step.
- `issues`: Array of all issues found, merged from both reviewers. Empty array
  `[]` when `gate` is `CLEAN`. Each issue includes:
  - `id`: Unique identifier using format `R<round>-<sequence>`, e.g. `R1-001`.
  - `category`: `CODE` for implementation compliance issues (from QA reviewer
    Part A), `TEST` for test completeness issues (from QA reviewer Part B),
    `CONV` for convention violations (from development-reviewer).
  - `file`: Absolute or target-relative path to the file containing the issue.
  - `line`: Line number in the file where the issue occurs.
  - `spec_section`: The spec section or convention rule that is violated.
  - `summary`: One-line description of the issue.
  - `evidence`: Direct quote from the spec alongside the code that contradicts
    it, showing the mismatch clearly.
  - `suggested_fix`: Actionable description of how to resolve the issue. The
    team leader uses `category` to route: `CODE`/`CONV` to implementer, `TEST`
    to QA engineer.
