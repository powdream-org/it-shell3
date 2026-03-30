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
  implementer or QA engineer. If reviewers find issues, they go through Step 6 —
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

- **If both clean** → Proceed to Step 10 (Coverage Audit).
- **If any issues found** → Merge issue lists (`[CODE]` + `[TEST]` + `[CONV]`)
  and proceed to Step 9 (Fix Cycle).

## Gate

- [ ] QA reviewer has completed dual review (Part A + Part B)
- [ ] Development-reviewer has completed convention re-verification
- [ ] Result is either "all clean" or a merged issue list with prefixes

## State Update

Update TODO.md:

- If clean: **Step**: 10 (Coverage Audit), mark Step 8 as `[x]`
- If issues: **Step**: 9 (Fix Cycle), mark Step 8 as `[x]`
- **Review Round**: increment by 1

Checkpoint: commit all changed artifacts (TODO.md).

## Next

**Auto-proceed** — no owner input required.

- If clean → Read `steps/10-coverage-audit.md`.
- If issues found → Read `steps/09-fix-cycle.md`.
