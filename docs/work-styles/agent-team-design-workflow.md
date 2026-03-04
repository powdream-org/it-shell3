# Agent Team Workflow: System Design & Spec Writing

## Overview

This documents the workflow for using Claude Code agent teams to design systems
and produce versioned design documents, based on the libitshell3 protocol design
experience.

---

## Phase 1: Initial Draft (Parallel Writing)

### Setup
1. Create output directory (e.g., `docs/design/server-client-protocols/`)
2. Create a team via `TeamCreate`
3. Create tasks with `TaskCreate` — one per document/topic
4. Set dependencies between tasks where needed (`addBlockedBy`)

### Agent Roles
Spawn 2-4 specialized agents based on the domain:

| Role pattern | Expertise | Typical docs |
|-------------|-----------|-------------|
| Protocol/architecture lead | Framing, lifecycle, type allocation | Overview, handshake |
| Systems engineer | OS integration, process mgmt, persistence | Session mgmt, flow control |
| Domain specialist | Rendering, CJK, GPU, input handling | Input/output, domain-specific |

### Execution
- Agents work in parallel on independent tasks
- Each agent reads reference docs first, then writes their assigned specs
- Use `run_in_background: true` for all agents
- Report progress as agents complete

### Cleanup
- Shutdown all agents via `SendMessage` with `type: "shutdown_request"`
- `TeamDelete` to clean up team resources

---

## Phase 2: Review & Discussion

### Review Input
- Human reviewer writes review notes as a markdown file in the same directory
- Notes should be structured: issue number, severity, what's wrong, what needs to change

### Team Discussion
1. Create a **new team** (e.g., `protocol-review`) — don't reuse the old one
2. Spawn the **same roles** as Phase 1 (they re-read their docs + review notes)
3. **Critical**: Instruct agents to message EACH OTHER directly, not just report to lead
4. **Designate one agent as consensus reporter** — explicitly assign one agent
   (typically the architecture lead) to synthesize peer-agreed positions and
   report the final consensus to team-lead. This prevents ambiguity about who
   "owns" the summary.
5. Discussion lead sends initial analysis to all teammates
6. Others respond with positions, especially on issues affecting their docs
7. Cross-cutting issues get debated between relevant specialists

### Context Carry-Forward (Restarting After Session Loss)

If a session ends mid-discussion (context window exhaustion, crash, etc.),
the previous team's agents become unreachable. To resume:

1. Force-clean stale team: `rm -rf ~/.claude/teams/<name>` then `TeamDelete`
2. Create a **new team** with fresh agents
3. **Feed prior discussion as structured context** in each agent's spawn prompt:
   - Prior proposals and agreed positions (copy from inbox JSON files)
   - Specific unresolved questions (numbered, with each agent's last position)
   - Which tasks were completed vs. still open
4. This avoids re-discussing settled points and lets agents pick up mid-debate

Inbox files from the dead team persist at `~/.claude/teams/<old-name>/inboxes/*.json`
until manually cleaned up — read them to reconstruct context.

### Resolving Disagreements
- If agents disagree (e.g., 2-vs-1 on a design choice), the team lead (you)
  can broadcast the project owner's decision to break the tie
- Always cite the authority: "The reviewer's mapping is the final word"

### PoC Validation as Review Input

Review rounds can be triggered by **PoC test results** in addition to human-written
review notes. When a PoC validates (or invalidates) spec assumptions:

1. Include PoC test results as structured review input:
   - Which tests passed/failed
   - API patterns that worked vs. didn't work
   - Known limitations discovered (e.g., library bugs, platform constraints)
2. Frame PoC findings as review issues — e.g., "PoC proved Space key needs
   special handling (flush + forward with `.text`), but spec doesn't document this"
3. Agents use PoC source code as ground truth when debating API correctness
4. PoC bugs themselves can become resolutions — e.g., "PoC used wrong keycode
   type; spec should clarify the correct type"

This was used successfully for the v0.2→v0.3 interface contract revision, where
the real ghostty PoC (`poc/ime-ghostty-real/`) drove 6 new resolutions.

### Output
- Consensus reporter synthesizes all peer-agreed positions into a single
  message to team-lead (not piecemeal per-agent reports)
- Team lead assigns an agent to write `review-resolutions.md` with agreed resolutions
- Each resolution: issue summary, agreed change, which docs affected

---

## Phase 3: Applying Revisions (Versioned)

### Directory Structure
```
docs/design/topic/
├── v0.1/                      # Initial drafts
│   ├── 01-xxx.md
│   ├── ...
│   └── review-notes-01.md
├── v0.2/                      # After first review round
│   ├── 01-xxx.md              # Updated with resolutions applied
│   └── ...
├── review-resolutions.md      # Lives at top level, tracks all rounds
└── v1/                        # Final consensus version (bumped when stable)
```

### Task Dependencies for Write-After-Discuss

Use `TaskCreate` with `addBlockedBy` to enforce the correct ordering:

```
Task #1: Discuss and reach consensus          (no blockers)
Task #2: Write review-resolutions.md          (blocked by #1)
Task #3: Write v0.N+1 docs with revisions     (blocked by #2)
```

This prevents agents from starting to write before consensus is reached.
Assign different agents to each task — the consensus reporter writes
resolutions, another agent applies them to produce the updated spec.

### Execution
- Move current docs to versioned directory **before** revision starts
- Each agent reads their v0.N doc, applies resolutions, writes to v0.N+1
- **Important**: Be VERY explicit with agents about creating new files
  (they may think the resolutions doc IS the deliverable — tell them to
  produce updated spec files with changes applied inline)
- After writing, agents cross-check each other's docs for consistency

---

## Lessons Learned

### What Works Well
- Parallel writing of independent docs saves significant time (3 agents = 6 docs simultaneously)
- Direct agent-to-agent messaging produces genuine debate and better outcomes
- Structured review notes (numbered issues, severity, proposed fix) get resolved faster
- Versioned directories make it easy to diff and track changes
- Broadcasting project-owner decisions quickly resolves deadlocks

### Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Agents don't create files | Agent goes idle, says "done" but no file on disk | Be explicit: "Use Write tool to create file X at path Y" |
| Discussion = deliverable confusion | Agent thinks writing resolutions doc is the final step | Always specify concrete file outputs expected after discussion |
| Cross-doc inconsistencies | Header size 14B in one doc, 16B in another | Plan a consistency check pass; agents cross-review each other's docs |
| Terminology drift | "Tab" means different things in different docs | Establish a mapping table and broadcast it before writing starts |
| Idle agents need nudging | Agent goes idle repeatedly without output | Send direct message with explicit step-by-step instructions |
| Agents proxy through lead | All messages go lead→agent instead of agent→agent | Instruct agents to talk to each other directly in spawn prompt |
| Zombie agents after session loss | `TeamDelete` fails: "Cannot cleanup team with N active member(s)" | Force-remove: `rm -rf ~/.claude/teams/<name>` then `TeamDelete`. Agents from dead sessions can't respond to shutdown requests. |
| Agent uses wrong approach/API | Agent implements with wrong technology (e.g., simulated instead of real dependency) or wrong API function (e.g., `ghostty_surface_text()` instead of `ghostty_surface_key()`) | Specify the exact technology/API in the task description; assign domain experts to cross-review before committing. Lead should verify critical API choices against reference docs. |

### Team Lead Role: Facilitate, Don't Micromanage

> **CRITICAL LESSON**: The team lead must NEVER directly command agents with
> specific instructions like "change line 43 from X to Y" or "use value A
> instead of B." This applies to ALL phases — design, architecture, protocol
> debate, cross-review, implementation, and bug fixing. The lead is a
> facilitator, not a dispatcher. Micromanaging makes the lead a bottleneck,
> prevents agents from understanding each other's work, and produces worse
> outcomes than peer collaboration.

**Team lead responsibilities:**
- Set the goal and scope for each round (what to design, review, or implement)
- Relay owner/reviewer decisions that agents cannot make on their own
- Break ties when agents genuinely deadlock
- Verify final output before committing

**What the team lead must NOT do:**
- Dictate specific changes — let the agent who found the issue negotiate with the agent who owns the file
- Proxy messages between agents — they must talk to each other directly
- Decide technical conflicts (unless it's an owner decision) — let agents debate and converge
- Give step-by-step instructions for how to resolve an issue — state the problem, let agents figure out the solution

**This applies to every phase:**
- **Design/architecture**: Set the topic, let agents propose and debate approaches with each other
- **Protocol debate**: Present the question, let agents argue positions peer-to-peer
- **Cross-review**: Instruct agents to review each other's work and message each other with findings
- **Implementation**: Assign areas of ownership, let agents coordinate interfaces between their modules
- **Bug fixing**: Report the symptom, let the responsible agent diagnose and fix

**Correct flow (any phase):**
1. Team lead sets the objective and any owner constraints
2. Agents work, communicate directly with each other as needed
3. Agents report outcomes to team lead
4. Team lead verifies and commits

### Team Communication Patterns
- Use `broadcast` sparingly — only for project-owner decisions or universal context
- Use direct `message` for peer-to-peer technical debate
- The team lead should NOT proxy all communication — instruct agents to talk
  to each other directly
- During cross-review, let agents report findings to each other and negotiate
  fixes directly. Team lead only steps in to break ties or enforce owner decisions.
- When an agent reports consensus, verify by checking if ALL agents confirmed
- Idle notifications with `[to <name>]` summaries indicate peer DMs are flowing — this is healthy
