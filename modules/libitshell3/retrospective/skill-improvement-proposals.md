# Skill Improvement Proposals

## SIP-1: State Update not committed before crossing step boundary

**Discovered during**: Step 3 (Plan Verification)

**What happened**: At the Step 1 → Step 2 transition, the gate checkpoint commit
was performed (TODO.md created, ROADMAP updated). Then the State Update was
applied (TODO.md step number advanced to 2, Step 1 marked [x]). But no commit
was made after the State Update before starting Step 2 work. The State Update
changes were bundled into the Step 2 checkpoint commit instead. If context had
been lost between steps, TODO.md would still say "Step 1" despite Step 1 being
complete, causing the agent to repeat Step 1 on resume.

**Root cause**: Each step file has two separate sections — "Gate" (with a
checkpoint commit requirement) and "State Update" (which modifies TODO.md after
the gate). The ordering is: do gate checks → commit → update state → proceed.
There is no instruction or gate requiring a commit after the State Update. The
State Update is treated as a post-gate housekeeping action, but it produces
uncommitted changes that are critical for crash recovery.

**Affected steps**: All step files in
`.claude/skills/implementation/steps/01-requirements-intake.md` through
`15-cleanup.md` — every step that has a State Update section followed by a
"Next" section.

**Proposed changes**: Merge the State Update into the gate checkpoint. Change
the pattern from:

1. Gate checks (including "checkpoint commit performed")
2. State Update (modify TODO.md)
3. Next (proceed)

To:

1. Gate checks (excluding commit)
2. State Update (modify TODO.md)
3. Checkpoint commit (single commit capturing both gate artifacts AND state
   update)
4. Next (proceed)

This ensures TODO.md always reflects the current step at every committed
checkpoint. The "Checkpoint commit performed" line moves from the Gate section
to after the State Update section, or the State Update instructions explicitly
say "include these changes in the checkpoint commit."

## SIP-2: Save feedback memory for checkpoint commit discipline

**Discovered during**: Step 3 (Plan Verification)

**What happened**: SIP-1 identified a procedural gap where State Update changes
are not committed before crossing step boundaries. The owner requested that this
lesson also be persisted as a feedback memory so that future conversations
(post-compaction or new sessions) remember to always commit State Update changes
before proceeding to the next step. Without a memory entry, the agent will
repeat the same mistake in every new context.

**Root cause**: SIP items are session-scoped artifacts — they live in the
retrospective directory and are processed at Step 14. They do not persist into
the agent's cross-conversation memory. A procedural lesson that should apply to
ALL future implementation cycles needs to be saved as a feedback memory in
addition to being logged as a SIP.

**Affected steps**: `.claude/skills/implementation/steps/` — all step files
(same as SIP-1). Additionally, the agent's memory system
(`~/.claude/projects/.../memory/`).

**Proposed changes**: Save a feedback memory entry documenting the rule: "Always
commit State Update changes (TODO.md step advancement) as part of the checkpoint
commit before crossing to the next step. Do State Update BEFORE the commit, not
after." This ensures the lesson survives context resets.
