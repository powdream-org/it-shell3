# Step 1: Requirements Intake

## Anti-Patterns

- **Don't start coding.** This step is setup only.
- **Don't create module-specific agent definitions.** Use the shared
  `.claude/agents/impl-team/` agents.

## Action

### 1a. Detect existing code

```bash
ls <target>/src/*.zig 2>/dev/null
```

- **No source files** → **greenfield** cycle.
- **Source files exist** → **modification** cycle. Note: what changed (new spec?
  bug?), which files are affected.

### 1b. Identify the design spec

Find the latest spec for this target:

```bash
find docs/ -path "*/02-design-docs/*/draft" -type d | sort
```

For each topic, find the latest `vX.Y-rN/` directory. Record the spec
version(s). See `docs/conventions/spec-document-sources.md` for precedence rules
(ADRs > CTRs > design docs).

If this is a modification cycle, also identify the previous spec version the
existing code was built against.

If no stable spec exists, report to the owner and STOP.

### 1c. Find the implementation plan

```bash
ls docs/superpowers/plans/*<module>* 2>/dev/null
```

- **Plan exists** → Read it. Confirm it covers file list, task dependencies, and
  test categories.
- **No plan exists** → Will be written in Step 2.

### 1d. Create TODO.md

Create `<target>/TODO.md` with this format:

```markdown
# <Module> Implementation TODO

## Current State

- **Step**: 1 (Requirements Intake)
- **Cycle Type**: <greenfield / modification (Plan N — description)>
- **Review Round**: 0
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: <target path>
- **Spec version(s)**: <list of spec topic/version pairs>
- **Previous spec version(s)**: <for modification cycles, or "N/A">
- **Plan**: <path or "pending — Step 2">
- **PoC**: <pending — Step 4>
- **Coverage exemption**: <pending — Step 4>

## Spec Gap Log

(empty — gaps discovered during implementation are logged here)

## Fix Cycle State

- **Fix Iteration**: 0
- **Active Issues**: (none)

## Progress — Round 1

- [ ] Step 1: Requirements Intake
- [ ] Step 2: Plan Writing
- [ ] Step 3: Plan Verification
- [ ] Step 4: Cycle Setup
- [ ] Step 5: Scaffold & Build Verification
- [ ] Step 6: Implementation Phase
- [ ] Step 7: Code Simplify & Convention Compliance
- [ ] Step 8: Spec Compliance Review
- [ ] Step 9: Fix Cycle
- [ ] Step 10: Coverage Audit
- [ ] Step 11: Over-Engineering Review
- [ ] Step 12: Commit & Report
- [ ] Step 13: Owner Review
- [ ] Step 14: Retrospective
- [ ] Step 15: Cleanup & ROADMAP Update
```

## Gate

- [ ] Cycle type determined (greenfield / modification)
- [ ] Design spec identified and version(s) recorded
- [ ] Plan existence checked
- [ ] TODO.md created
- [ ] ROADMAP Plan Index status updated to `In progress`
- [ ] Checkpoint commit performed (TODO.md + changed artifacts)

## State Update

Update TODO.md:

- **Step**: 2 (Plan Writing) or 3 (Plan Verification)
- Mark Step 1 as `[x]`

Update ROADMAP Plan Index: set this plan's status to `**In progress**`.

Checkpoint: commit all changed artifacts (TODO.md, ROADMAP.md).

## Next

**Auto-proceed** — no owner input required.

- If no plan → Read `steps/02-plan-writing.md`.
- If plan exists → Read `steps/03-plan-verification.md`.
