# Skill Improvement Proposals

## SIP-1: Implementation skill requires unnecessary owner approvals at auto-proceed steps

**Discovered during**: Step 4 (Cycle Setup)

**What happened**: The team leader paused for owner approval at Step 4e despite
all gate conditions being mechanically verifiable (agents exist, plan verified,
ROADMAP updated). The owner expressed frustration that every step requires
approval even when conditions are fully specified. Earlier steps (1→2→3) also
paused unnecessarily — Step 1's gate says "Owner approves, TODO.md created" but
the approval is just confirming factual information (cycle type, spec versions).

**Root cause**: Multiple steps have "owner approval" gates that conflate two
different concerns: (1) decisions requiring human judgment (e.g., coverage
exemptions, scope changes) and (2) mechanical checkpoints that just confirm
artifacts exist. The skill treats both identically, forcing the team leader to
pause and present information the owner can verify themselves.

**Affected steps**:

- `steps/01-requirements-intake.md` — gate says "Owner approves"
- `steps/04-cycle-setup.md` — gate says "Owner has approved", step 4e says "Wait
  for owner approval before proceeding"
- Potentially other steps with similar patterns

**Proposed changes**:

- Distinguish "owner decision gates" (require judgment: scope, exemptions,
  trade-offs) from "mechanical gates" (all conditions are objectively
  verifiable: files exist, tests pass, agents present).
- Convert mechanical gates to auto-proceed with a brief status update (not a
  question). The owner can interrupt if something looks wrong.
- Step 1: Change gate to auto-proceed — cycle type and spec versions are
  factual, not judgment calls.
- Step 4: Split gate into mechanical (auto-proceed: agents verified, ROADMAP
  updated, TODO.md filled) and judgment (pause only if: coverage exemption
  requested, unusual constraints, or PoC changes scope). When no judgment items
  exist, auto-proceed with a summary line.
- Add a general principle to the skill: "If all gate conditions can be verified
  by reading files and running commands, auto-proceed. Only pause for owner
  approval when a gate involves a trade-off or decision that requires human
  judgment."

## SIP-2: Implementer agent not aware of project Zig conventions

**Discovered during**: Step 6 (Implementation Phase)

**What happened**: The implementer agent definition
(`.claude/agents/impl-team/implementer.md`) has generic Zig guidelines (no
`= undefined`, vendored C with ReleaseSafe) but does not reference the
project-specific convention docs under `docs/conventions/zig-*.md` (zig-coding,
zig-naming, zig-documentation, zig-testing). The team leader's spawn prompt
mentioned "Read `docs/conventions/zig-coding.md` and
`docs/conventions/zig-naming.md`" but this is easy to miss and not enforced by
the agent definition itself. This means implementers may produce code that
violates project conventions (e.g., wrong integer widths, abbreviated names,
missing doc comment patterns), creating rework in Step 7
(fix-code-convention-violations).

**Root cause**: The implementer agent definition was written generically and
never updated to include project-specific convention references. The spawn
prompt in Step 6 mentions conventions as a suggestion rather than a mandatory
read-first instruction built into the agent itself.

**Affected steps**:

- `.claude/agents/impl-team/implementer.md` — agent definition
- `steps/06-implementation.md` — spawn prompt template

**Proposed changes**:

- Add to `implementer.md` a "Project Conventions" section with mandatory reads:
  ```
  ## Project Conventions (MANDATORY — read before writing any code)
  - docs/conventions/zig-coding.md — integer widths, packed struct rules
  - docs/conventions/zig-naming.md — no abbreviations, buffer constants, getters
  - docs/conventions/zig-documentation.md — doc comment format, TODO format
  - docs/conventions/zig-testing.md — inline vs spec tests, naming, ownership
  ```
- Add to Step 6 spawn prompt: "MANDATORY: Read ALL docs/conventions/zig-*.md
  files before writing any code. Convention violations caught later are
  expensive rework."
- Add anti-pattern to Step 6: "Don't assume agents know project conventions. The
  agent definition and spawn prompt must both reference convention docs
  explicitly."

## SIP-3: Team leader self-triaged over-engineering findings instead of escalating to owner

**Discovered during**: Step 11 (Over-Engineering Review)

**What happened**: The over-engineering reviewer reported 2 findings
(hid_keycode u16 vs spec u8, duplicate KeyEvent types). The team leader decided
both were "pre-existing, not Plan 16 scope" and logged them in the Spec Gap Log
without invoking `/triage` — effectively making the disposition decision (defer)
without presenting the findings to the owner. Step 11d explicitly says "If
findings exist → Invoke `/triage` to present them to the owner."

**Root cause**: The team leader rationalized skipping triage because the
findings were pre-existing, not new code from Plan 16. This is a classic
self-triage anti-pattern — the team leader judged the findings as "obviously
defer" and bypassed the owner's authority. Whether something is pre-existing
does not change the requirement to escalate: the owner might decide to fix it
now, file a CTR, or add it to Plan 8's scope.

**Affected steps**:

- `steps/11-over-engineering-review.md` — Step 11d triage instruction

**Proposed changes**:

- Add anti-pattern to Step 11: "Don't self-triage over-engineering findings.
  Even if findings appear pre-existing or out-of-scope, the owner decides the
  disposition. 'Pre-existing' is a timeline fact, not a disposition — the owner
  may still choose Fix, Justified, or Defer. Always invoke `/triage`."
- Add gate condition to Step 11: "If findings exist, `/triage` was invoked and
  owner dispositions recorded before any action taken."

## SIP-4: Checkpoint commits never performed throughout the cycle

**Discovered during**: Step 12 (Commit & Report)

**What happened**: Every step file includes a "Checkpoint: commit all changed
artifacts" instruction in its State Update section. The team leader never
performed any checkpoint commits throughout the entire Plan 16 cycle (Steps
1-11). All changes accumulated as uncommitted working tree modifications. This
means: (1) no safe rollback points exist if a step goes wrong, (2) if the
session crashed or context was lost, all work since the start would need to be
reconstructed, (3) the git history will show a single monolithic commit instead
of incremental progress.

**Root cause**: The "Checkpoint: commit" instruction is buried at the bottom of
each step's State Update section, after the gate conditions. The team leader
focused on gates and next-step transitions, treating the checkpoint as optional
commentary rather than a mandatory action. There is no gate condition that
enforces "checkpoint commit performed" — it is only mentioned in prose.

**Affected steps**:

- All step files (01 through 15) — each has a "Checkpoint: commit" instruction
  that is not enforced

**Proposed changes**:

- Add an explicit gate condition to every step: "- [ ] Checkpoint commit
  performed (TODO.md + changed artifacts)"
- Add anti-pattern to SKILL.md Cross-Cutting Rules: "Don't skip checkpoint
  commits. Each step's checkpoint creates a rollback point. Without them, a
  crash or context loss requires reconstructing all work from scratch. Commit
  before proceeding to the next step."
- Consider making the checkpoint commit the FIRST action of the State Update
  section (before updating TODO.md step number), so it is performed as part of
  the transition, not as an afterthought.
