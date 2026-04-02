# Step 2: Plan Writing

## Anti-Patterns

- **Don't write the plan yourself.** The team leader is a facilitator. Delegate
  to a subagent via `/writing-impl-plan`.
- **Don't edit the plan yourself.** When verifiers find issues, delegate fixes
  via `/writing-impl-plan` in Revise mode.
- **Don't bypass the `/writing-impl-plan` skill.** Ad-hoc edits skip format
  validation and completeness checks.

## Action

### 2a. Delegate plan writing

Invoke `/writing-impl-plan` with:

- Spec paths from Step 1
- Source directory path
- ROADMAP entry for the target
- Any owner-provided constraints

The subagent reads specs and source, writes the plan. The team leader reviews
the result — checks scope, task granularity, spec coverage.

### 2b. Review the plan

Confirm the plan covers:

- Directory structure and file list
- Task dependencies
- Spec references per task
- In-scope / out-of-scope boundary
- Verification criteria per task

## Gate

- [ ] Plan written via `/writing-impl-plan` skill
- [ ] Plan reviewed by team leader
- [ ] Checkpoint commit performed (TODO.md + changed artifacts)

## State Update

Update TODO.md:

- **Step**: 3 (Plan Verification)
- **Plan**: path to the written plan
- Mark Step 2 as `[x]`

Checkpoint: commit all changed artifacts (TODO.md, plan file).

## Next

**Auto-proceed** — no owner input required.

Read `steps/03-plan-verification.md`.
