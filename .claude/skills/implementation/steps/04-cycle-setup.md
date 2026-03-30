# Step 4: Cycle Setup

## Anti-Patterns

- **Don't skip agent verification.** Missing agents cause failures mid-cycle.
- **Don't proceed without owner approval.** The owner must see the full picture
  before implementation begins.

## Action

### 4a. Collect additional inputs

Check for PoC code:

```bash
ls poc/*<module>* 2>/dev/null
```

Record any PoC directories found — these serve as reference only.

Ask the owner for any constraints not in the plan:

- Performance targets
- Coverage requirements (or exemptions — see `05-implementation-workflow.md`
  §6.2)
- Tooling preferences

### 4b. Verify agent definitions

```bash
ls -la .claude/agents/impl-team/
```

Confirm that all required agents exist: `implementer.md`, `qa-engineer.md`,
`qa-reviewer.md`, `development-reviewer.md`, `devops.md`, and
`principal-architect.md`. If any are missing, report to the owner.

### 4c. Update TODO.md

Fill in the fields that were pending from Step 1:

- **Plan**: path to the verified implementation plan
- **PoC**: paths or "none"
- **Coverage exemption**: yes/no (with reason if yes)

### 4d. Update ROADMAP.md

Update `docs/superpowers/plans/ROADMAP.md`:

- Set the plan's Status to `In progress` in the Plan Index table
- Update the Current Status table with current source file count, test count,
  and coverage for the target module(s)

### 4e. Present to owner

Show the owner:

1. Spec version(s) being implemented
2. Plan summary (file list, task count, dependency graph)
3. PoC reference (if any)
4. Coverage approach (instrumented or scenario-matrix with exemption)
5. Team composition (from agent directory)
6. Verification results (from Step 3)

Wait for owner approval before proceeding.

## Gate

- [ ] PoC and constraints collected
- [ ] Agent definitions verified
- [ ] TODO.md updated with plan path, PoC, coverage exemption
- [ ] ROADMAP.md updated
- [ ] Owner has approved

## State Update

Update TODO.md:

- **Step**: 5 (Scaffold & Build Verification)
- Mark Step 4 as `[x]`

Checkpoint: commit all changed artifacts (TODO.md, ROADMAP.md).

## Next

**Auto-proceed** — owner already approved in 4e.

Read `steps/05-scaffold-and-build.md`.
