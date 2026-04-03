# Implementation Skill Redesign: Team Leader Harness

**Date:** 2026-04-03 **Status:** Draft **Scope:**
`.claude/skills/implementation/` restructuring

## Problem Statement

The `/implementation` skill's team leader consistently fails to follow
instructions despite those instructions being clear and correct. Observed
failure patterns from Plan 8 (and prior cycles):

| # | Pattern                                                         | Root Cause                            |
| - | --------------------------------------------------------------- | ------------------------------------- |
| 1 | State Update after commit, not before                           | Procedure sequence ignored            |
| 2 | Asks owner permission at auto-proceed gates                     | Unnecessary judgment inserted         |
| 3 | Gate not met but passed anyway (coverage 94.86% < 95%)          | Team leader interprets gate           |
| 4 | Directly edits code instead of delegating to implementer        | Facilitator role violated             |
| 5 | Triage quality degrades over time (first proper, rest shortcut) | Shortcutting after initial compliance |
| 6 | Gate verification skipped (coverage not re-measured)            | Fact-checking omitted                 |
| 7 | /triage invocation skipped, issues processed directly           | Skill delegation bypassed             |
| 8 | Triage grouping becomes 1 issue = 1 group                       | Grouping becomes formality            |

**Prior mitigations that failed:**

- Anti-pattern additions → more text to ignore
- Feedback memory entries → read and not followed
- Step splitting → more transition points to fail at
- Gate conditions → interpreted rather than checked

**Key observation:** Team leader succeeds at sub-agent spawning and routing, but
fails at procedures it must execute directly. The solution is to minimize direct
execution and maximize delegation.

**Reference:** `/design-doc-revision` skill successfully constrains team leader
via decision tables, mandatory skill delegation, and prescribed state updates.

## Design

### 1. Master Transition Table

Add to `SKILL.md`. Replaces per-step `## Next` sections as the authority for
step transitions. Team leader looks up the table, does not interpret prose.

```markdown
| From | Gate Result               | TODO.md State Update      | Next Step                                   | Proceed   |
| ---- | ------------------------- | ------------------------- | ------------------------------------------- | --------- |
| 1    | TODO.md created           | Step → 2 or 3             | 02 (no plan) / 03 (plan exists)             | auto      |
| 2    | Plan written              | Step → 3, Plan path       | 03                                          | auto      |
| 3    | All verifiers clean       | Step → 4                  | 04                                          | auto      |
| 4    | Agents verified           | Step → 5                  | 05                                          | auto      |
| 5    | Build passes              | Step → 6                  | 06                                          | auto      |
| 6    | Code compiles, tests run  | Step → 7, Active Team     | 07                                          | auto      |
| 7    | Simplify + conv done      | Step → 8                  | 08                                          | auto      |
| 8    | QA + conv clean           | Step → 10                 | 10                                          | auto      |
| 8    | [CODE]/[TEST]/[CONV] list | Step → 9                  | 09                                          | auto      |
| 9    | All issues resolved       | Step → 8, Fix Iteration++ | 08                                          | auto      |
| 10   | Coverage ≥ targets        | Step → 11                 | 11                                          | auto      |
| 10   | Coverage < targets        | (escalate)                | owner decides: 11 (exempt) / 10 (fill gaps) | **owner** |
| 11   | No code changed           | Step → 12                 | 12                                          | auto      |
| 11   | Code changed              | Step → 8, Round++         | 08                                          | auto      |
| 12   | All final gates green     | Step → 13                 | 13                                          | auto      |
| 13   | Owner accepts             | Step → 14                 | 14                                          | **owner** |
| 13   | Owner requests changes    | Step → 6, new Round       | 06                                          | **owner** |
| 14   | Retro complete            | Step → 15                 | 15                                          | auto      |
| 15   | Cleanup done              | (end)                     | —                                           | auto      |
```

### 2. Transition Rules

These rules govern how the transition table is applied. They eliminate team
leader judgment from the transition process.

1. **Gate satisfaction is binary.** All conditions met = satisfied. Any
   condition not met = not satisfied. No "close enough", "essentially met",
   "within margin" interpretations.

2. **Gate verification requires command output.** The team leader must execute
   the verification command and read the output. Memory, prior results, or
   estimation do not constitute verification. Examples:
   - Coverage: `mise run test:coverage` output must show `≥ 95%`
   - Tests: `mise run test:macos` output must show `passed`
   - Format: `zig fmt --check` exit code must be 0

3. **Gate not satisfied → `owner` proceed.** When any gate condition is not met,
   the team leader escalates to the owner. The team leader does not decide
   whether the gap is acceptable.

4. **`auto` proceed = no owner interaction.** Proceed immediately with a
   one-line status update. Do not ask "Should I continue?", "Ready to proceed?",
   or any variant.

5. **`owner` proceed = wait for explicit signal.** Do not prompt, suggest, or
   nudge. Present the situation and wait.

6. **State Update before commit.** The TODO.md state update (step number, marks)
   is applied BEFORE the checkpoint commit. A single commit captures both gate
   artifacts and state update. Never commit first then update state.

### 3. Delegation Rules

Define what the team leader may and may not do directly. Based on the observed
pattern: team leader succeeds at delegation, fails at direct execution.

**Team leader MAY directly:**

- Read/write TODO.md
- Look up the transition table
- Spawn sub-agents
- Run git commands (add, commit, status, diff)
- Apply skill file edits (after reviewing sub-agent's temp file output)

**Team leader MUST delegate (may NOT do directly):**

- Code editing → implementer sub-agent
- Test editing → QA engineer sub-agent
- Triage presentation → `/triage` skill (with sub-agent preparation)
- Convention review → development-reviewer sub-agent
- Coverage measurement → devops sub-agent
- Plan writing/revision → `/writing-impl-plan` skill
- CTR writing → `/cross-team-request` skill
- ADR writing → `/adr` skill
- SIP writing → `/sip` skill

**Skill file editing exception:** Sub-agents cannot write to `.claude/skills/`
directly. For skill modifications:

1. Sub-agent writes proposed changes to a temp file
2. Team leader reviews the temp file
3. Team leader applies changes to the skill file

### 4. Convention Violation Routing

When the development-reviewer reports convention violations, the team leader
does not decide scope. Routing is by location:

| Violation Location               | Disposition       | Authority                                  |
| -------------------------------- | ----------------- | ------------------------------------------ |
| File changed in current plan     | Fix in this cycle | auto (implementer fixes)                   |
| File NOT changed in current plan | Escalate          | **owner** decides: fix now, defer, or skip |

"Pre-existing" is a timeline fact, not a disposition. The owner decides whether
pre-existing violations are fixed in the current cycle.

### 5. Triage Quality Rules

Address the observed degradation pattern (first triage proper, subsequent ones
shortcutted).

1. **Every `/triage` invocation follows the full procedure.** No exception for
   small issue counts, later rounds, or "obvious" issues. The procedure exists
   for decision quality, not for scaling.

2. **Grouping by root cause, not by symptom.** Issues that share the same
   underlying cause belong in the same group. Verification: every group has ≥ 2
   issues. If a group has 1 issue, attempt to merge with another group first.
   Solo groups are allowed only when genuinely unrelated to all others.

3. **Sub-agent preparation is mandatory.** The sub-agent reads quality examples
   and prepares 5W1H presentations. The team leader does not present issues
   directly from memory or from the issue list.

4. **Triage is invoked, not inlined.** When a step says "invoke `/triage`", the
   team leader invokes the skill. Presenting issues in any other format (summary
   table, inline list, batch) violates this rule.

### 6. Step File Changes

Each step file retains its current structure (Anti-Patterns, Action, Gate) but
with these modifications:

**Remove from each step file:**

- `## State Update` section — values are now in the master transition table
- `## Next` section — routing is now in the master transition table

**Add to each step file:**

- Gate conditions must specify the exact command to verify each condition (not
  just the condition statement)

**Rationale:** The State Update and Next sections are the primary sites of team
leader compliance failure. Moving them to a central lookup table removes the
need for the team leader to read, remember, and follow per-step prose
instructions for transitions.

### 7. Gate Verification Format

Each gate condition in step files must specify a verification command:

```markdown
## Gate

- [ ] Tests pass: `mise run test:macos` → output contains "tests passed"
- [ ] Format clean: `(cd <target> && zig fmt --check src/)` → exit code 0
- [ ] Coverage met: `mise run test:coverage` → libitshell3 line ≥ 95%
```

The team leader executes each command and checks the output. "I ran it earlier"
or "it was passing before" does not satisfy the gate.

## Migration Plan

1. Add the master transition table to `SKILL.md`
2. Add transition rules, delegation rules, convention routing, triage rules to
   `SKILL.md` Cross-Cutting Rules section
3. Remove `## State Update` and `## Next` from all 15 step files
4. Add verification commands to gate conditions in each step file
5. Update step file anti-patterns to reference the new rules where relevant

## Success Criteria

The redesign is successful if in the next implementation cycle:

- Zero instances of team leader asking permission at auto-proceed gates
- Zero instances of team leader directly editing code
- Zero instances of gate conditions passed without command verification
- All triage invocations follow the full procedure
- All convention violations routed per the location table (not self-triaged)
