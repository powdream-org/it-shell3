# Step 4: Assignment & Writing

## Anti-Patterns

- Do NOT let agents edit files before you explicitly signal "begin writing."
- Do NOT use sonnet for document writing — use opus always. Sonnet has produced
  quality issues that waste verification rounds.
- Do NOT micromanage ("change line 43 from X to Y"). State the goal, let the
  agent figure out the approach.

## Action

### 4a. Context check

Before spawning, check if context window is **25% or below**. If so, ask owner
to `/compact` first.

### 4b. Leader assigns

Review the resolution document and agent expertise. The team leader directly
assigns which agent writes which document/section. No negotiation phase.

**Why leader assigns:** Agent negotiation added a full spawn cycle and often
ended with the leader making a unilateral pick anyway. Direct assignment saves
tokens without loss of quality.

### 4c. Spawn assigned writers only

Spawn only the agents that have writing assignments (opus). Pass each agent:

- The resolution document
- Their specific assignment (which docs/sections)
- The current draft spec docs
- If fix round (Round 2+): the verification issues file (`round-{N}-issues.md`)

**Explicitly instruct: "Wait for my signal before editing any files."**

### 4d. Writing gate

Once all agents are spawned and idle, send to each: **"Begin writing your
assigned changes."**

### 4e. Monitor and disband

Wait for all agents to report completion. Disband the team.

## Gate

- [ ] All assigned spec documents updated on disk
- [ ] Cross-team requests written (if applicable)
- [ ] All agents shut down

## State Update

Update TODO.md:

- `Current State` → `Step: 5 (Verification)`
- `Active Team` → (none)
- `Team Directory` → (none)
- Mark `Step 4` as `[x]`

## Next

Read `steps/05-verification.md`.
