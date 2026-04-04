# Step 10: Coverage Audit

## Anti-Patterns

- **Don't estimate coverage from test count.** Instrumented measurement is
  required (see `05-implementation-workflow.md` §6.2). "We have 100 tests" is
  not evidence of coverage.
- **Don't skip this step for exempted modules.** Even exempted modules must
  demonstrate scenario-matrix completeness — every spec-defined code path has a
  named test. (Lesson T1)
- **Don't add tests for unreachable code.** `unreachable` branches, panic
  handlers, and platform-specific code are valid exceptions IF documented with
  rationale. "Hard to test" is NOT a valid exception.

## Action

### 10a. Update TODO.md

Update TODO.md: set **Step** to 10 (Coverage Audit), mark Step 9 as `[x]`. Clear
**Active Issues** (all resolved).

### 10b. Determine coverage approach

**Always re-measure.** Never trust previous coverage numbers — code changes
between passes invalidate them. Even if returning from a regression loop, run
coverage measurement fresh.

Read TODO.md's `Coverage exemption` field:

- **No exemption** → Use instrumented coverage (kcov/llvm-cov)
- **Exemption granted** → Use scenario-matrix audit

### 10c. Instrumented coverage (default path)

Instruct the QA engineer (the QA engineer owns all coverage gap-closing tests —
the implementer does not write gap tests). The QA reviewer audits the results:

```
Run instrumented coverage on <target>:

1. Build the test binary: mise run test:macos (or zig build test --summary none for kcov binary)
2. Run with kcov: kcov --include-path=src/ coverage-report/ ./zig-out/bin/test
3. Report coverage numbers: line %, branch %, function %
4. If targets not met (line ≥95%, branch ≥90%, function 100%):
   - Identify uncovered code paths
   - Add tests to cover them (or document valid exceptions)
   - Re-run until targets met

If kcov fails (Mach-O/DWARF issues), report the error. Do NOT silently fall
back to scenario-matrix — the team leader must request an owner exemption.
```

If kcov fails and the owner grants an exemption, update TODO.md's
`Coverage
exemption` field and fall through to 7c.

### 10d. Scenario-matrix audit (exempted modules only)

Instruct the QA engineer:

```
Perform a scenario-matrix coverage audit:

1. Use the test matrix from the implementation plan (verified in Step 1).
   If the plan has no test matrix, STOP and report to the team leader —
   the plan is incomplete.
2. For each scenario, verify a named test exists that exercises that code path
3. Report: total scenarios, covered scenarios, any gaps
4. For gaps: add a named test for each uncovered scenario
5. Repeat until every scenario has a corresponding test

The test name must clearly identify which scenario it covers.
```

### 10e. Collect coverage results

Record coverage numbers (or scenario count) in TODO.md for the final report.

## Gate

- [ ] Coverage measured with instrumented tooling OR scenario-matrix audit
      complete (if exempted): `mise run test:coverage` → coverage report
      generated, or scenario matrix reviewed
- [ ] Targets met: line ≥ 95%, branch ≥ 90%, function = 100% — OR scenario
      matrix 100% covered: `mise run test:coverage` → line ≥ 95%, branch ≥ 90%,
      function = 100%
- [ ] Exceptions documented with rationale:
      `grep 'unreachable\|Exception' <target>/TODO.md` → rationale present for
      each exception
- [ ] `mise run test:all` passes (with coverage):
      `mise run test:macos && mise run test:macos:release-safe` → all tests pass
- [ ] If new tests revealed spec violations → returned to Step 8 → team leader
      confirmation
- [ ] Checkpoint commit performed (TODO.md + changed artifacts):
      `git log -1 --oneline` → commit message references coverage audit
