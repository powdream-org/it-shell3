# Step 3: Plan Verification

## Anti-Patterns

- **Don't use sonnet for verification.** Sonnet is biased toward existing code
  patterns and misses spec-vs-plan divergences. Use the plan review team (opus +
  effort: max).
- **Don't resolve spec-code divergences yourself.** When a verifier reports a
  divergence, ALWAYS escalate to the owner. The team leader is not qualified to
  determine which side is correct.
- **Don't dismiss divergences as "out of scope."** Every divergence must be
  investigated. "Out of scope for this plan" is a conclusion AFTER
  investigation.
- **Don't treat "the plan covers it" as investigation.** Knowing the plan will
  fix a divergence does not explain WHY the code diverges.
- **Don't infer "intentional deferral" from circumstantial evidence.** Only
  explicit decision documents (ADR, design resolution, owner instruction)
  justify divergence from spec.
- **Don't create CTR files manually.** Always use `/cross-team-request`.

## Action

### 3a. Spawn the plan review team

Spawn ALL three verifiers from `.claude/agents/impl-plan-review-team/` in
**parallel**:

**spec-plan-verifier:**

```
Verify the implementation plan against the design spec.
Spec: <paths from Step 1>
Plan: <path>
ROADMAP: docs/superpowers/plans/ROADMAP.md
Report: clean pass or [SPEC-PLAN] issue list.
```

**spec-code-verifier** (modification cycles only):

```
Verify existing code against the design spec.
Spec: <paths from Step 1>
Source: <target>/src/
ROADMAP: docs/superpowers/plans/ROADMAP.md
Report: clean pass or [SPEC-CODE] issue list.
```

**plan-code-verifier** (modification cycles only):

```
Check the plan for redundancy with existing code.
Plan: <path>
Source: <target>/src/
Spec: <paths from Step 1>
ROADMAP: docs/superpowers/plans/ROADMAP.md
Report: clean pass or [REDUNDANT] issue list.
```

For greenfield cycles, only spawn the spec-plan-verifier.

### 3b. Triage issues

When verifiers report issues, invoke `/triage` with the issue list.

Dispositions for this step:

- **Fix** → Delegate plan revision via `/writing-impl-plan` Revise mode
- **Defer** → Log in Spec Gap Log
- **CTR** → Spec needs updating, use `/cross-team-request`
- **False alarm** → No action

### 3c. Re-verify after fixes

After plan revision:

1. Re-spawn the verifiers that reported issues
2. Repeat until ALL verifiers report clean pass

Do NOT proceed to Step 4 until all three verifiers pass clean.

## Gate

- [ ] spec-plan-verifier: clean pass → verifier agent reports "clean pass"
- [ ] spec-code-verifier: clean pass (or N/A for greenfield) → verifier agent
      reports "clean pass" or N/A
- [ ] plan-code-verifier: clean pass (or N/A for greenfield) → verifier agent
      reports "clean pass" or N/A
- [ ] All divergences investigated (not dismissed) → team leader confirmation
- [ ] Owner-escalated items resolved → owner confirmation
- [ ] Checkpoint commit performed (TODO.md + changed artifacts):
      `git log -1 --oneline` → commit message references plan verification
