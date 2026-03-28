# Step 1: Requirements Intake

## Anti-Patterns

- **Don't skip the plan check.** Implementation without a plan leads to
  uncoordinated parallel work. If no plan exists, stop and tell the owner.
- **Don't create module-specific agent definitions.** Use the shared
  `.claude/agents/impl-team/` agents — they are parameterized at spawn time with
  module-specific context.
- **Don't start coding.** This step is setup only. No source code is written
  until Step 2 (scaffold) passes.
- **Don't dismiss divergences as "out of scope."** During Plan 5, verifiers
  reported 4 pre-existing spec-code divergences (PaneSlot u4 vs u8,
  keyboard_layout naming, default "us" vs "qwerty", missing fields). The team
  leader dismissed all 4 as "out of scope for this plan" without investigating.
  Every spec-code divergence must be investigated — "out of scope for this plan"
  is a valid conclusion AFTER investigation, not a reason to skip it.
- **Don't treat "the plan covers it" as investigation.** A verifier reported
  missing IME fields as a divergence. The team leader said "Plan Task 2 covers
  this" and moved on. Knowing the plan will fix the divergence does not answer
  WHY the code diverges — was it intentional deferral, a prior plan's bug, or a
  spec update the code hasn't caught up to? The answer affects whether a simple
  fix suffices or deeper issues exist.
- **Don't infer "intentional deferral" from circumstantial evidence.** Git
  timestamps, plan scope statements, and ROADMAP entries do not prove a
  divergence was intentional. The owner's rule: spec is authoritative unless an
  explicit decision document (ADR, design resolution, or owner instruction) says
  otherwise. Code that diverges from spec without such a document is a bug.
- **Don't write the plan yourself.** The team leader is a facilitator. Plan
  writing is research-heavy work (reading specs, analyzing code,
  cross-referencing) that belongs to a subagent. Provide paths and constraints,
  not prose.
- **Don't edit the plan yourself.** When verifiers find issues, delegate fixes
  to a subagent via `/writing-impl-plan` in Revise mode. The team leader
  describes required changes — a subagent applies them.
- **Don't bypass the `/writing-impl-plan` skill.** During Plan 5, plan revisions
  were made via ad-hoc Edit calls instead of re-invoking the skill. The skill
  ensures format consistency and completeness. Ad-hoc edits skip validation.
- **Don't create CTR files manually.** Always use the `/cross-team-request`
  skill. It handles placement rules, naming conventions, and format
  automatically. Manual creation causes convention violations (wrong directory,
  wrong filename, wrong metadata).

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

### 1c. Find or write the implementation plan

Look for an existing plan:

```bash
ls docs/superpowers/plans/*<module>* 2>/dev/null
```

- **If a plan exists** → Read it and confirm it covers directory structure, file
  list, task dependencies, and test categories.
- **If no plan exists** → Delegate plan writing to a subagent via the
  `/writing-impl-plan` skill. The team leader provides the subagent with:
  - Spec paths discovered in 1b
  - Source directory path
  - ROADMAP entry for the target
  - Any owner-provided constraints

  The team leader reviews the result, not writes it.

Record the plan path in TODO.md.

### 1d. Verify plan against spec

Spawn one verifier per spec topic (e.g., architecture, behavior). Each verifier
reads the spec, plan, and source code directly — the team leader provides paths,
not curated summaries.

Send to each verifier:

```
Verify the implementation plan against the design spec.

Spec: <paths from TODO.md>
Plan: <path>
Source (modification cycle only): <target>/src/

Check:
- Every in-scope spec requirement has a corresponding plan task
- Plan's type names, field names match the spec
- Plan does not re-add what already exists in source code
- If spec and source code disagree, report as "spec-code divergence"
  with both sides quoted — do NOT dismiss either side

Report: clean pass, or numbered issue list.
```

This is an **autonomous convergence loop**. Do NOT ask the owner for permission
to re-verify. Keep iterating (fix → re-verify) until clean pass. **EXCEPTION**:
if investigation reveals a divergence requiring owner judgment (e.g., spec may
need updating), escalate that specific item and continue fixing other issues in
parallel.

1. Spawn verifiers with paths above
2. If issues found:
   - **Plan-vs-spec gap** → Delegate to a subagent: re-invoke
     `/writing-impl-plan` in Revise mode with the issue list. The team leader
     provides the issue list and plan path; the subagent reads the plan, applies
     fixes, and reports back. All plan fixes MUST go through the skill — do NOT
     make ad-hoc edits.
   - **Spec-code divergence** → Investigate: read the spec's rationale, check
     for ADRs, understand why the code differs. Spec wins by default.
     "Intentional deferral" requires explicit documentation (ADR, design
     resolution, or owner instruction). A plan's out-of-scope list does not
     count. Without explicit documentation, report the divergence as a bug. If
     the fix belongs to a different plan, log it in TODO.md's Spec Gap Log with
     the investigation result. If unable to determine which side is correct,
     escalate to owner before proceeding.
   - **Plan-vs-code redundancy** (plan re-adds existing code) → Delegate to a
     subagent: re-invoke `/writing-impl-plan` in Revise mode with the issue list
   - **Cross-team request needed** → Always use the `/cross-team-request` skill.
     Do NOT manually create CTR files.
3. Re-spawn verifiers after plan update
4. Repeat until clean pass

Do NOT proceed to Step 2 until the plan passes spec verification.

### 1e. Collect additional inputs

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

### 1f. Verify agent definitions

```bash
ls -la .claude/agents/impl-team/
```

Confirm that `implementer.md`, `qa-reviewer.md`, and `principal-architect.md`
exist. If any are missing, report to the owner.

### 1g. Create TODO.md

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
- [ ] Step 11: Retrospective
- [ ] Step 12: Cleanup & ROADMAP Update
```

### 1h. Update ROADMAP.md

Update `docs/superpowers/plans/ROADMAP.md`:

- Set the plan's Status to `In progress` in the Plan Index table
- Update the Current Status table with current source file count, test count,
  and coverage for the target module(s)

### 1i. Present to owner

Show the owner:

1. Spec version(s) being implemented
2. Plan summary (file list, test count)
3. PoC reference (if any)
4. Coverage approach (instrumented or scenario-matrix with exemption)
5. Team composition (from agent directory)

Wait for owner approval before proceeding.

## Gate

- [ ] Design spec identified and version(s) recorded
- [ ] Implementation plan exists (found or written via `/writing-impl-plan`
      through a subagent)
- [ ] Plan verified against design spec (autonomous convergence loop, clean
      pass)
- [ ] All spec-code divergences investigated (not dismissed)
- [ ] Agent definitions verified
- [ ] TODO.md created in `<target>/`
- [ ] Owner has approved

## State Update

Update TODO.md:

- **Step**: 2 (Scaffold & Build Verification)
- Mark Step 1 as `[x]`

## Next

Read `steps/02-scaffold-and-build.md`.
