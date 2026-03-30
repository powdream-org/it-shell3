# Step 4: Assignment & Writing

## Anti-Patterns

- Do NOT let agents edit files before you explicitly signal "begin writing."
- Do NOT use sonnet for document writing — use opus always. Sonnet has produced
  quality issues that waste verification rounds.
- Do NOT micromanage ("change line 43 from X to Y"). State the goal, let the
  agent figure out the approach.
- Do NOT reuse agent names across steps without checking for stale shutdown
  requests. A respawned agent with the same name may process a shutdown request
  from a previous step, causing premature termination.

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

**Fix rounds (Round 2+):** Group assignments by **issue cluster**, not by doc.
One writer per cluster, even if the cluster spans multiple docs. A cluster is a
set of issues that share a topic or where fixing one affects the others (e.g.,
all mouse diagram issues across doc01/doc02, all lock language removals across
doc02/doc04). This prevents parallel writers from making independent judgment
calls that diverge on the same topic.

**File conflict scheduling:** When two clusters touch the same file, they MUST
run sequentially (not in parallel). The team leader builds a dependency graph:
clusters that share no files run in parallel; clusters that share files are
ordered by dependency or severity (higher-severity cluster first). Signal "begin
writing" per batch, not globally.

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

Checkpoint: commit all changed artifacts (TODO.md, written documents).

## Next

**Auto-proceed** — no owner input required.

Read `steps/05-verification.md`.
