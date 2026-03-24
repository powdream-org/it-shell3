# Step 6: Coverage Audit

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

### 6a. Determine coverage approach

Read TODO.md's `Coverage exemption` field:

- **No exemption** → Use instrumented coverage (kcov/llvm-cov)
- **Exemption granted** → Use scenario-matrix audit

### 6b. Instrumented coverage (default path)

Instruct the QA reviewer:

```
Run instrumented coverage on <target>:

1. Build the test binary: (cd <target> && zig build test --summary none)
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
exemption` field and fall through to 6c.

### 6c. Scenario-matrix audit (exempted modules only)

Instruct the QA reviewer:

```
Perform a scenario-matrix coverage audit:

1. List every spec-defined scenario (from the spec's scenario matrix or
   integration test categories in the plan)
2. For each scenario, verify a named test exists that exercises that code path
3. Report: total scenarios, covered scenarios, any gaps
4. For gaps: add a named test for each uncovered scenario
5. Repeat until every scenario has a corresponding test

The test name must clearly identify which scenario it covers.
```

### 6d. Collect coverage results

Record coverage numbers (or scenario count) in TODO.md for the final report.

## Gate

- [ ] Coverage measured with instrumented tooling OR scenario-matrix audit
      complete (if exempted)
- [ ] Targets met: line ≥ 95%, branch ≥ 90%, function = 100% — OR scenario
      matrix 100% covered
- [ ] Exceptions documented with rationale
- [ ] `zig build test` still passes

## State Update

Update TODO.md:

- **Step**: 7 (Over-Engineering Review)
- Mark Step 6 as `[x]`

## Next

Read `steps/07-over-engineering-review.md`.
