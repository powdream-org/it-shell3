# Step 5: Spec Compliance Review

## Anti-Patterns

- **Don't let the implementer review their own code.** The QA reviewer does this
  — that's the whole point of role separation.
- **Don't accept "it works" as proof of compliance.** Working code can still
  deviate from the spec (extra fields, wrong signatures, unauthorized behavior).
  The QA reviewer checks the spec, not the test results.
- **Don't rush this step.** Spec violations caught here are cheap to fix.
  Violations caught after commit are expensive.

## Action

### 5a. Instruct the QA reviewer

Send to QA reviewer:

```
Review all source files in <target>/src/ against the design spec.
Check:
- Every spec requirement has corresponding code
- Types, field names, and method signatures match the spec EXACTLY
- Error handling matches spec-defined behavior
- Edge cases described in the spec are handled
- No undocumented behavior or implicit assumptions
- No unauthorized extensions (extra fields, methods, parameters)
- Memory ownership rules followed (buffer lifetimes, pointer validity)

Report either:
(a) "Clean pass — no issues found", or
(b) A numbered issue list with file:line references and spec section citations
```

### 5b. Collect results

Wait for the QA reviewer to report.

- **If clean pass** → Proceed to Step 7 (Coverage Audit).
- **If issues found** → Proceed to Step 6 (Fix Cycle).

## Gate

- [ ] QA reviewer has completed the review
- [ ] Result is either "clean pass" or a numbered issue list

## State Update

Update TODO.md:

- If clean: **Step**: 7 (Coverage Audit), mark Step 5 as `[x]`
- If issues: **Step**: 6 (Fix Cycle), mark Step 5 as `[x]`
- **Review Round**: increment by 1

## Next

- If clean → Read `steps/07-coverage-audit.md`.
- If issues found → Read `steps/06-fix-cycle.md`.
