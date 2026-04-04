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

### 4e. Present risks and surprises

If any of these exist, present to the owner and wait for decision:

- Coverage exemption requested
- Scope changes discovered during plan verification
- Unusual constraints or risks the owner hasn't seen
- Decisions made without owner input that could be overridden

If none exist, auto-proceed with a one-line status: "No risks or surprises.
Auto-proceeding to Step 5."

## Gate

- [ ] PoC and constraints collected: `grep 'PoC' <target>/TODO.md` → shows paths
      or "none"
- [ ] Agent definitions verified: `ls .claude/agents/impl-team/*.md` → all
      required agent files present
- [ ] TODO.md updated with plan path, PoC, coverage exemption:
      `grep -E 'Plan|PoC|Coverage exemption' <target>/TODO.md` → all fields
      populated
- [ ] ROADMAP.md updated: `grep '<plan-name>' docs/superpowers/plans/ROADMAP.md`
      → contains "In progress" with current stats
- [ ] Risks/surprises presented (or confirmed none exist) → owner confirmation
      or "no risks" logged
- [ ] Checkpoint commit performed (TODO.md + changed artifacts):
      `git log -1 --oneline` → commit message references cycle setup
