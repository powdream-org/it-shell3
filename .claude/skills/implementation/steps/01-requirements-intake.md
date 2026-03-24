# Step 1: Requirements Intake

## Anti-Patterns

- **Don't skip the plan check.** Implementation without a plan leads to
  uncoordinated parallel work. If no plan exists, stop and tell the owner.
- **Don't create module-specific agent definitions.** Use the shared
  `.claude/agents/impl-team/` agents — they are parameterized at spawn time with
  module-specific context.
- **Don't start coding.** This step is setup only. No source code is written
  until Step 2 (scaffold) passes.

## Action

### 1a. Detect existing code

Check if the target already has source code:

```bash
ls <target>/src/*.zig 2>/dev/null
```

- **If no source files exist** → This is a **greenfield** cycle. Proceed
  normally through all steps.
- **If source files exist** → This is a **modification** cycle (spec update, bug
  fix, or feature addition). Record the cycle type and note:
  - What changed (new spec version? bug report? owner request?)
  - Which files are affected (delta analysis)
  - Step 2 (scaffold) will be skipped if the build already works

Record the cycle type in TODO.md (see 1e).

### 1b. Identify the design spec

Find the latest stable (or owner-approved) spec for this target:

```bash
find docs/ -path "*/02-design-docs/*/draft" -type d | sort
```

For each topic, find the latest `vX.Y-rN/` directory. Read the spec documents to
confirm they exist and are complete. Record the spec version(s) being
implemented.

If this is a modification cycle, also identify the **previous spec version**
that the existing code was built against (check git log or the previous TODO.md
commit). The delta between old and new spec drives the implementation scope.

If no stable spec exists, report to the owner and STOP.

### 1c. Check for implementation plan

Look for an existing plan:

```bash
ls .claude/plan/*<module>* 2>/dev/null
```

If a plan exists, read it and confirm it covers:

- Directory structure and file list
- Test matrix (integration test categories)
- Build system configuration
- Dependencies (vendored C libraries, etc.)

If no plan exists, tell the owner: "No implementation plan found. Please create
one (you can use `/writing-plans`) or provide the plan details." STOP until the
owner provides a plan.

### 1d. Collect additional inputs

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

### 1e. Verify agent definitions

```bash
ls -la .claude/agents/impl-team/
```

Confirm that `implementer.md`, `qa-reviewer.md`, and `principal-architect.md`
exist. If any are missing, report to the owner.

### 1f. Create TODO.md

Create `<target>/TODO.md` with this exact format:

```markdown
# <Module> Implementation TODO

## Current State

- **Step**: 1 (Requirements Intake)
- **Cycle Type**: <greenfield / spec-update / bug-fix>
- **Review Round**: 0
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: <target path, e.g., modules/libitshell3-ime>
- **Spec version(s)**: <list of spec topic/version pairs>
- **Previous spec version(s)**: <for modification cycles, or "N/A" for
  greenfield>
- **Plan**: <path to implementation plan>
- **PoC**: <path(s) or "none">
- **Coverage exemption**: <yes/no — if yes, reason>

## Spec Gap Log

(empty — gaps discovered during implementation are logged here)

## Fix Cycle State

- **Fix Iteration**: 0
- **Active Issues**: (none)

## Progress — Round 1

- [ ] Step 1: Requirements Intake
- [ ] Step 2: Scaffold & Build Verification
- [ ] Step 3: Implementation Phase
- [ ] Step 4: Code Simplify
- [ ] Step 5: Spec Compliance Review
- [ ] Step 6: Fix Cycle
- [ ] Step 7: Coverage Audit
- [ ] Step 8: Over-Engineering Review
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup
```

### 1g. Present to owner

Show the owner:

1. Spec version(s) being implemented
2. Plan summary (file list, test count)
3. PoC reference (if any)
4. Coverage approach (instrumented or scenario-matrix with exemption)
5. Team composition (from agent directory)

Wait for owner approval before proceeding.

## Gate

- [ ] Design spec identified and version(s) recorded
- [ ] Implementation plan exists
- [ ] Agent definitions verified
- [ ] TODO.md created in `<target>/`
- [ ] Owner has approved

## State Update

Update TODO.md:

- **Step**: 2 (Scaffold & Build Verification)
- Mark Step 1 as `[x]`

## Next

Read `steps/02-scaffold-and-build.md`.
