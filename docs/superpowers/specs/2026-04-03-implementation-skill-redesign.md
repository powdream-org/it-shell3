# Implementation Skill Redesign: Fork-Based Step Isolation

- **Date:** 2026-04-03
- **Updated:** 2026-04-04
- **Status:** Draft
- **Scope:** `.claude/skills/implementation/` restructuring

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

**Root cause analysis:** Team leader's context window fills with intermediate
work products (code diffs, test output, review results) from Steps 6-9. This
context pollution degrades gate judgment and increases shortcutting in later
steps. The more the team leader sees, the worse it follows procedures.

**Reference:** `/design-doc-revision` skill successfully constrains team leader
via decision tables, mandatory skill delegation, and prescribed state updates.

## Design

### 1. Fork-Based Step Isolation

Steps 6-9 (the heaviest context consumers) are extracted into separate skills
with `context: fork` in their frontmatter. When the team leader invokes a fork
skill, a sub-agent inherits the team leader's full conversation context but
executes in isolation — intermediate work products (code diffs, test output,
agent coordination) do not flow back into the team leader's context. Only a
structured JSON result is returned.

#### Why these 4 steps

| Step | Context Weight | Escalation Risk | Fork? |
| ---- | -------------- | --------------- | ----- |
| 6    | HEAVY          | Low             | Yes   |
| 7    | MEDIUM-HEAVY   | Low             | Yes   |
| 8    | HEAVY          | Low             | Yes   |
| 9    | HEAVY          | Low             | Yes   |
| 10   | MEDIUM-HEAVY   | **High**        | No    |
| 11   | MEDIUM-HEAVY   | **High**        | No    |

Steps 10 and 11 remain un-forked because they frequently require owner
escalation (coverage exemptions, over-engineering triage). Fork would create an
awkward relay chain: fork → team leader → owner → team leader → re-dispatch
fork.

#### Role separation

```
Team Leader (direct execution)       Fork Skills (isolated execution)
┌──────────────────────────┐         ┌───────────────────────────┐
│ Steps 1-5: preparation   │         │ /impl-execute  (Step 6)   │
│ Step 7.5: triage         │ ←JSON── │ /impl-simplify (Step 7)   │
│ Step 8.5: triage         │         │ /impl-review   (Step 8)   │
│ Steps 10-15: quality +   │ ──arg─→ │ /impl-fix      (Step 9)   │
│   review + cleanup       │         │                           │
└──────────────────────────┘         └───────────────────────────┘
```

**Team leader directly:**

- Transition table lookup
- TODO.md state update
- Checkpoint commit (state only)
- Owner escalation
- `/triage` invocation (Steps 7.5, 8.5)

**Fork handles:**

- Step internal execution (agent spawning, coordination)
- Gate verification command execution
- Checkpoint commit (code only)
- JSON result construction

### 2. Fork Return Contract

All fork skills return a JSON object conforming to a common envelope:

```json
{
  "step": "<number>",
  "gate": "<PASS|FAIL|CLEAN|ISSUES>",
  "checkpoint": "<commit-sha>",
  "payload": {}
}
```

The team leader reads `gate` to look up the transition table. The `payload` is
read only when needed for triage or next-step dispatch.

#### `/impl-execute` (Step 6)

```json
{
  "step": 6,
  "gate": "PASS",
  "checkpoint": "abc1234",
  "payload": {
    "compilation": "PASS",
    "tests_executed": true,
    "test_summary": { "passed": 142, "failed": 0, "skipped": 0 },
    "spec_gaps": [
      {
        "file": "src/Session.zig",
        "line": 87,
        "spec_section": "Session Lifecycle",
        "description": "Spec requires graceful shutdown notification but implementation does not send one",
        "severity": "divergence"
      }
    ]
  }
}
```

#### `/impl-simplify` (Step 7)

```json
{
  "step": 7,
  "gate": "PASS",
  "checkpoint": "def5678",
  "payload": {
    "simplify_complete": true,
    "convention_complete": true,
    "tests_pass": true,
    "out_of_plan_violations": [
      {
        "file": "src/Pane.zig",
        "line": 42,
        "rule": "zig-naming §3.2",
        "current": "fn getBuf()",
        "expected": "fn getBuffer()",
        "description": "Abbreviation 'Buf' violates no-abbreviation convention",
        "in_current_plan": false
      }
    ]
  }
}
```

The fork fixes all `in_current_plan: true` violations internally before
returning. Only `in_current_plan: false` items appear in
`out_of_plan_violations`. When this array is non-empty, the team leader
transitions to Step 7.5 and invokes `/triage` with this data. Each item carries
enough context for 5W1H triage presentation.

#### `/impl-review` (Step 8)

```json
{
  "step": 8,
  "gate": "ISSUES",
  "checkpoint": "789abcd",
  "payload": {
    "issues": [
      {
        "id": "R1-001",
        "category": "CODE",
        "file": "src/Session.zig",
        "line": 120,
        "spec_section": "Session Persistence",
        "summary": "save() writes JSON but spec requires binary encoding",
        "evidence": "Spec: 'Sessions are persisted in binary wire format' vs code: std.json.stringify()",
        "suggested_fix": "Replace JSON serialization with binary encoder from protocol module"
      }
    ]
  }
}
```

When `gate` is `ISSUES`, the team leader transitions to Step 8.5 and invokes
`/triage`. Each issue includes `category` for routing to implementer (`CODE`,
`CONV`) or QA engineer (`TEST`) in Step 9.

#### `/impl-fix` (Step 9)

```json
{
  "step": 9,
  "gate": "PASS",
  "checkpoint": "bcd2345",
  "payload": {
    "rounds_used": 2,
    "resolved": [
      { "id": "R1-001", "summary": "Replaced JSON with binary encoder" },
      { "id": "R1-002", "summary": "Added round-trip persistence test" }
    ],
    "unresolved": [],
    "tests_pass": true
  }
}
```

`gate: FAIL` with non-empty `unresolved` (after 3 rounds) triggers owner
escalation.

### 3. Master Transition Table

The team leader's sole procedure: read gate → look up table → update state →
commit → execute next.

| From | Gate Source    | Gate Result                       | TODO.md State Update | Next                    | Proceed   |
| ---- | -------------- | --------------------------------- | -------------------- | ----------------------- | --------- |
| 1    | file check     | TODO.md created                   | Step → 2 or 3        | 02 / 03                 | auto      |
| 2    | file check     | Plan written                      | Step → 3             | 03                      | auto      |
| 3    | verifier       | All clean                         | Step → 4             | 04                      | auto      |
| 4    | agent check    | Agents verified                   | Step → 5             | 05                      | auto      |
| 5    | build output   | Build passes                      | Step → 6             | dispatch /impl-execute  | auto      |
| 6    | fork JSON      | `gate: PASS`                      | Step → 7             | dispatch /impl-simplify | auto      |
| 6    | fork JSON      | `gate: FAIL`                      | (escalate)           | owner decides           | **owner** |
| 7    | fork JSON      | `gate: PASS`, violations: `[]`    | Step → 8             | dispatch /impl-review   | auto      |
| 7    | fork JSON      | `gate: PASS`, violations: `[...]` | Step → 7.5           | /triage                 | **owner** |
| 7.5  | triage done    | Owner dispositioned               | Step → 8             | dispatch /impl-review   | auto      |
| 8    | fork JSON      | `gate: CLEAN`                     | Step → 10            | 10                      | auto      |
| 8    | fork JSON      | `gate: ISSUES`                    | Step → 8.5           | /triage                 | **owner** |
| 8.5  | triage done    | fix items exist                   | Step → 9             | dispatch /impl-fix      | auto      |
| 8.5  | triage done    | all skip/defer                    | Step → 10            | 10                      | auto      |
| 9    | fork JSON      | `gate: PASS`                      | Step → 8, Fix Iter++ | dispatch /impl-review   | auto      |
| 9    | fork JSON      | `gate: FAIL`                      | (escalate)           | owner decides           | **owner** |
| 10   | command output | Coverage ≥ targets                | Step → 11            | 11                      | auto      |
| 10   | command output | Coverage < targets                | (escalate)           | owner decides           | **owner** |
| 11   | reviewer       | No code changed                   | Step → 12            | 12                      | auto      |
| 11   | reviewer       | Code changed                      | Step → 8, Round++    | dispatch /impl-review   | auto      |
| 12   | gate checks    | All green                         | Step → 13            | 13                      | auto      |
| 13   | owner          | Accepts                           | Step → 14            | 14                      | **owner** |
| 13   | owner          | Requests changes                  | Step → 6, new Round  | dispatch /impl-execute  | **owner** |
| 14   | retro output   | Complete                          | Step → 15            | 15                      | auto      |
| 15   | cleanup        | Done                              | (end)                | —                       | auto      |

### 4. Transition Rules

These rules govern how the transition table is applied:

1. **Gate satisfaction is binary.** All conditions met = satisfied. Any
   condition not met = not satisfied. No "close enough" or "essentially met".

2. **Fork steps: gate from JSON.** The team leader reads the `gate` field from
   the fork's JSON result. The fork has already executed verification commands.
   The team leader does not re-run them.

3. **Non-fork steps: gate from command output.** For Steps 1-5 and 10-15, the
   team leader executes the verification command specified in the step file and
   reads the output directly.

4. **Gate not satisfied → `owner` proceed.** When any gate condition is not met,
   the team leader escalates to the owner. The team leader does not decide
   whether the gap is acceptable.

5. **`auto` proceed = no owner interaction.** Proceed immediately with a
   one-line status update. Do not ask "Should I continue?", "Ready to proceed?",
   or any variant.

6. **`owner` proceed = wait for explicit signal.** Do not prompt, suggest, or
   nudge. Present the situation and wait.

7. **State update before commit.** The TODO.md state update is applied BEFORE
   the checkpoint commit. The fork commits code; the team leader commits state.

### 5. Delegation Rules

Fork structurally enforces delegation for Steps 6-9 — the team leader cannot
access intermediate code, test output, or agent coordination within those steps.

For Steps 10-11 (un-forked), delegation rules remain as explicit constraints:

**Team leader MAY directly:**

- Read/write TODO.md
- Look up the transition table
- Invoke fork skills and `/triage`
- Run git commands (add, commit, status, diff)
- Run gate verification commands (Steps 10-11 only)

**Team leader MUST delegate (Steps 10-11):**

- Code editing → implementer sub-agent
- Test editing → QA engineer sub-agent
- Coverage measurement → devops sub-agent
- Triage presentation → `/triage` skill

### 6. Triage Quality Rules

Triage occurs at Steps 7.5 and 8.5. These rules apply to both:

1. **Every `/triage` invocation follows the full procedure.** No exception for
   small issue counts, later rounds, or "obvious" issues.

2. **Grouping by root cause, not by symptom.** Issues that share the same
   underlying cause belong in the same group. Solo groups are allowed only when
   genuinely unrelated to all others.

3. **Sub-agent preparation is mandatory.** The sub-agent reads quality examples
   and prepares 5W1H presentations. The team leader does not present issues
   directly from the fork JSON.

4. **Triage is invoked, not inlined.** When a transition says "/triage", the
   team leader invokes the skill. Presenting issues in any other format violates
   this rule.

### 7. Directory Structure

Internal skills are organized by context isolation mode. Single source of truth
— no duplication.

- `isolated/` — `context: fork` skills. Execute in a forked sub-agent;
  intermediate work does not flow back to the team leader. Returns JSON result.
- `direct/` — Skills that execute in the team leader's context directly.

```
.claude/skills/implementation/
├── SKILL.md                              # Entry point + transition table
├── steps/
│   ├── 01-requirements-intake.md
│   ├── 02-plan-writing.md
│   ├── 03-plan-verification.md
│   ├── 04-cycle-setup.md
│   ├── 05-scaffold-and-build.md
│   ├── 10-coverage-audit.md
│   ├── 11-over-engineering-review.md
│   ├── 12-commit-and-report.md
│   ├── 13-owner-review.md
│   ├── 14-retrospective.md
│   └── 15-cleanup.md
├── isolated/
│   ├── impl-execute/SKILL.md             # Step 6 (was steps/06)
│   ├── impl-simplify/SKILL.md            # Step 7 (was steps/07)
│   ├── impl-review/SKILL.md              # Step 8 (was steps/08)
│   └── impl-fix/SKILL.md                 # Step 9 (was steps/09)
└── direct/
    └── impl-resolve-target/SKILL.md      # Target resolution (was in SKILL.md)
```

**Step Index in SKILL.md:**

| Step  | Location                              | Execution     |
| ----- | ------------------------------------- | ------------- |
| —     | `direct/impl-resolve-target/SKILL.md` | direct        |
| 1-5   | `steps/01~05.md`                      | team leader   |
| 6     | `isolated/impl-execute/SKILL.md`      | context: fork |
| 7     | `isolated/impl-simplify/SKILL.md`     | context: fork |
| 8     | `isolated/impl-review/SKILL.md`       | context: fork |
| 9     | `isolated/impl-fix/SKILL.md`          | context: fork |
| 10-15 | `steps/10~15.md`                      | team leader   |

### 8. Non-Fork Step File Changes

Steps 1-5 and 10-15 retain their current structure (Anti-Patterns, Action, Gate)
with these modifications:

**Remove from each step file:**

- `## State Update` section — values are in the master transition table
- `## Next` section — routing is in the master transition table

**Add to each step file:**

- Gate conditions must specify the exact verification command:

```markdown
## Gate

- [ ] Tests pass: `mise run test:macos` → output contains "tests passed"
- [ ] Format clean: `(cd <target> && zig fmt --check src/)` → exit code 0
- [ ] Coverage met: `mise run test:coverage` → libitshell3 line ≥ 95%
```

The team leader executes each command and checks the output. "I ran it earlier"
or "it was passing before" does not satisfy the gate.

### 9. Existing Spec Proposals — Disposition

| § | Original Proposal            | Disposition                                                                                                                       |
| - | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 1 | Master Transition Table      | **Kept + modified** — Gate Source column added, Steps 7.5/8.5 added                                                               |
| 2 | Transition Rules             | **Kept + reduced** — command verification moves inside fork for Steps 6-9; team leader reads JSON `gate` instead                  |
| 3 | Delegation Rules             | **Structurally replaced** for Steps 6-9 by fork isolation; explicit rules remain for Steps 10-11 only                             |
| 4 | Convention Violation Routing | **Kept, timing changed** — fork classifies violations via `in_current_plan` field; team leader routes at Step 7.5                 |
| 5 | Triage Quality Rules         | **Kept unchanged** — triage occurs at 7.5/8.5, both outside fork                                                                  |
| 6 | Step File Changes            | **Modified** — Steps 6-9 become isolated skills; target resolution becomes direct skill; Steps 1-5/10-15 follow original proposal |
| 7 | Gate Verification Format     | **Split** — fork steps: JSON contract; non-fork steps: command-in-step-file format                                                |

## Migration Plan

| #  | Task                                                                            | Depends On |
| -- | ------------------------------------------------------------------------------- | ---------- |
| 1  | Add master transition table to SKILL.md                                         | —          |
| 2  | Update SKILL.md Cross-Cutting Rules (reduced delegation rules)                  | 1          |
| 3  | Create `isolated/` directory and 4 isolated skills                              | —          |
| 3a | `isolated/impl-execute/SKILL.md` ← content from `steps/06`                      |            |
| 3b | `isolated/impl-simplify/SKILL.md` ← content from `steps/07`                     |            |
| 3c | `isolated/impl-review/SKILL.md` ← content from `steps/08`                       |            |
| 3d | `isolated/impl-fix/SKILL.md` ← content from `steps/09`                          |            |
| 4  | Create `direct/` directory and target resolution skill                          | —          |
| 4a | `direct/impl-resolve-target/SKILL.md` ← target resolution from SKILL.md         |            |
| 5  | Delete `steps/06~09.md`                                                         | 3          |
| 6  | Remove target resolution from SKILL.md, add invocation reference                | 4          |
| 7  | Update SKILL.md Step Index (isolated/direct references)                         | 3, 4, 5    |
| 8  | Modify non-fork step files: remove State Update/Next, add verification commands | 1          |
| 9  | Update Success Criteria                                                         | all        |

## Success Criteria

The redesign is successful if in the next implementation cycle:

- Zero instances of team leader asking permission at auto-proceed gates
- Zero instances of team leader directly editing code
- Zero instances of gate conditions passed without verification
- All triage invocations follow the full procedure
- All convention violations routed per the location table (not self-triaged)
- Fork steps (6-9) return valid JSON conforming to the defined schema
- Team leader's fork step processing consists only of: JSON gate read →
  transition table lookup → state update → commit
- Steps 10-11: team leader executes gate verification commands directly
