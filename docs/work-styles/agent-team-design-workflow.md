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

### Research Prior Art Before Designing

When tackling infrastructure or architecture problems (e.g., multi-client resize
policy, client health detection, flow control/backpressure, session persistence),
the team MUST research how reference codebases handle the same problem BEFORE
designing a solution. This applies to both initial design (Phase 1) and new
problems surfaced during review (Phase 2).

**Workflow:**
1. Identify the architectural problem to be solved
2. Spawn research agents (e.g., `tmux-expert`, `zellij-expert`, `ghostty-expert`)
   targeting the relevant reference codebases at `~/dev/git/references/`
3. Each researcher produces a findings report with:
   - How the reference codebase solves the problem
   - Source file paths and relevant code references
   - Trade-offs observed (what works well, what doesn't)
4. Core team members read the findings reports and use them as input for their
   design — they do NOT design in a vacuum
5. Researchers do NOT write design docs; they report findings to core members
   who incorporate them

**Rationale:** Designing without prior-art research leads to reinventing solved
problems or missing known pitfalls. Reference codebases (tmux, zellij, iTerm2,
ghostty) have years of production experience with the same problems we face.

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
- **All review artifacts (review notes, resolutions, research reports, handovers) MUST
  follow the naming and format conventions in
  [Review Notes & Handover Docs](../conventions/review-and-handover-docs.md).**

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

### Handover on Review Completion

When the owner signals that review is done on a specific document (or all docs
being tackled in the current session), the relevant expert agents MUST
autonomously produce handover documents for the next revision. This is a
**standard workflow step** — it should not require explicit instructions each
time.

**Who writes:** The expert agent(s) who own the reviewed documents, not the team
lead. Each expert writes the handover for their area of ownership.

**When to trigger:** Immediately after the owner confirms that the review round
is complete and no further discussion is needed for the current session.

**Required content:**

| Section | Content |
|---------|---------|
| **What was accomplished** | Summary of the review round — issues raised, resolutions reached, docs revised |
| **Open items for next revision** | Numbered list of unresolved issues, deferred decisions, or items explicitly punted to the next version |
| **Pre-discussion research tasks** | Any research (reference codebase analysis, PoC experiments) that should happen before the next design round begins |
| **File locations** | Paths to all relevant artifacts — review notes, resolution files, updated spec versions, PoC code |

**Location:** `docs/design/topic/v<X>/handover/handover-to-v<next>.md`
(see [Review Notes & Handover Docs](../conventions/review-and-handover-docs.md))

This convention complements Phase 4 (session-end handover written by the team
lead). Phase 4 covers the overall session state; this convention ensures that
domain-specific context is captured by the experts who understand it best,
immediately when a review round closes rather than waiting for session end.

---

## Phase 2b: Cross-Component Consistency Review

Phase 2 reviews issues **within** a single spec set (e.g., protocol docs reviewing
each other). Phase 2b addresses a different need: checking consistency **between**
two separate spec areas that must interoperate.

### When to Use

Use this when two independently-authored spec sets share an interface boundary. For
example, reviewing the IME interface contract against the server-client protocol docs
to verify that wire-to-IME field mapping, modifier key encoding, composition state
encoding, and preedit message flow are consistent across both.

### Team Composition

Members from **both** spec areas must participate. The team shifts from Phase 2's
single-domain roles to a mixed group:

| Pattern | Example members |
|---------|----------------|
| Component A expert(s) | Protocol architect, systems engineer |
| Component B expert(s) | IME engine expert, CJK specialist |
| Shared-concern specialist | Rendering & CJK specialist (bridges both areas) |

The key difference from Phase 2 is that no single agent owns the full picture — each
brings knowledge of their component and discovers mismatches at the boundary.

### Execution

1. **Review phase** — All agents read both spec sets, then raise issues where the
   two components disagree or leave gaps. Issues are numbered and discussed freely
   by all reviewers. Do NOT pre-assign issues to specific reviewers; any reviewer
   may raise or respond to any issue.

   > **Strict separation**: Do NOT modify design documents during the review phase.
   > The review phase produces review notes only. Document changes happen in the
   > revision cycle (Phase 3).

2. **Two review-notes files** — Each component side gets its own review-notes file.
   For example, an IME-vs-protocol cross-review produces:
   - `docs/design/protocol/vN/review-notes-XX-cross-ime.md`
   - `docs/design/ime/vN/review-notes-XX-cross-protocol.md`

   This separation matters because each component applies its own changes in its
   own revision cycle, potentially at different times and by different teams.

3. **Revision** — After the review phase completes, each component applies its own
   changes independently using the normal Phase 3 process. The two revision cycles
   need not be synchronous — one component may revise immediately while the other
   waits for a future session.

### Differences from Phase 2

| Aspect | Phase 2 (intra-component) | Phase 2b (cross-component) |
|--------|--------------------------|---------------------------|
| Scope | Issues within one spec set | Consistency between two spec sets |
| Team | Single-domain specialists | Mixed members from both domains |
| Review output | One review-notes file | Two files (one per component side) |
| Revision | One revision cycle | Two independent revision cycles |
| Typical issues | Internal contradictions, missing details | Field mapping mismatches, encoding disagreements, missing cross-references |

---

## Phase 3: Applying Revisions (Versioned)

### Directory Structure
```
docs/design/topic/
├── v0.1/                      # Initial drafts
│   ├── 01-xxx.md
│   ├── ...
│   ├── review-resolutions-01.md
│   ├── review-notes/
│   │   ├── 01-{topic}.md
│   │   └── 02-{topic}.md
│   └── handover/
│       └── handover-to-v0.2.md
├── v0.2/                      # After first review round
│   ├── 01-xxx.md              # Updated with resolutions applied
│   └── ...
└── v1/                        # Final consensus version (bumped when stable)
```

### Task Dependencies for Write-After-Discuss

Use `TaskCreate` with `addBlockedBy` to enforce the correct ordering:

```
Task #1: Discuss and reach consensus          (no blockers)
Task #2: Write review-resolutions.md          (blocked by #1)
Task #3: Write v<next> docs with revisions      (blocked by #2)
```

This prevents agents from starting to write before consensus is reached.
Assign different agents to each task — the consensus reporter writes
resolutions, another agent applies them to produce the updated spec.

### Execution
- Move current docs to versioned directory **before** revision starts
- Each agent reads their v<X> doc, applies resolutions, writes to v<next>
- **Important**: Be VERY explicit with agents about creating new files
  (they may think the resolutions doc IS the deliverable — tell them to
  produce updated spec files with changes applied inline)
- After writing, agents cross-check each other's docs for consistency

### Spec Writer Role Pattern

Design decisions and mechanical spec production are separable concerns. Core team
members (architects, domain experts) make the decisions; a dedicated spec-writer
agent can handle the mechanical work of applying those decisions to produce the
next version.

#### Division of Responsibility

| Concern | Who | Model |
|---------|-----|-------|
| Design decisions, review, debate | Core team members | `opus` |
| Applying resolutions to produce vN+1 docs | Spec-writer agent | `sonnet` |

The spec-writer does NOT make design decisions. Its responsibilities are strictly
mechanical:

- Apply resolutions from `review-resolutions.md` in order
- Update cross-references between documents
- Maintain a "Changes from vN" appendix in each updated document
- Verify self-consistency (e.g., field sizes, message type numbers match across docs)

If a resolution is ambiguous or requires a judgment call, the spec-writer escalates
to the team lead or the relevant core member rather than guessing.

#### Why This Works

The `sonnet` model is sufficient for copy-editing, search-and-replace across
sections, and structural consistency checks. Using it for spec production reduces
cost while reserving `opus` capacity for the intellectually demanding work (design
debate, trade-off analysis, cross-component review). This is an exception to the
general "use `opus` by default" policy stated in [Custom Agent Registration](#custom-agent-registration)
— it applies specifically to the spec-writer role because the task is well-defined
and non-creative.

---

## Phase 3b: Cross-Document Consistency Verification (MANDATORY)

> **⚠️ This phase is MANDATORY after every revision that modifies documents.**
> The team lead MUST NOT skip this phase, even if the changes appear trivial.
> Skipping verification has historically introduced regressions that were only
> caught in subsequent sessions, wasting significant effort.

### Purpose

When multiple agents apply changes to different documents in parallel (Phase 3),
each agent sees only their own docs. Cross-document inconsistencies — field name
mismatches, stale cross-references, conflicting terminology, missing registry
entries — are invisible to individual agents and can only be caught by a dedicated
verification pass where agents read ALL docs.

### Rules

1. **Verification is a separate phase, not part of Phase 3.** Agents who wrote
   the changes are too close to them to catch their own mistakes. Verification
   requires fresh reads of the full document set.

2. **Minimum two verification rounds.** The first round finds issues. If fixes
   are applied, those fixes are themselves unverified changes. A second round
   with fresh agents confirms the fixes are correct, complete, and did not
   introduce new inconsistencies. If the second round finds no issues,
   verification is complete. If the second round finds NEW issues, fix them
   and run a third round. Repeat until a clean round is achieved — there is
   no maximum. In practice, a third round is rare if fixes are careful.

3. **Each round MUST use fresh agents.** Shut down agents from the previous round
   and spawn new ones. Agents who applied fixes or verified in a prior round carry
   confirmation bias — they remember what they wrote and tend to assume their own
   work is correct rather than reading the document cold. Fresh agents read the
   docs without preconceptions, which is the entire point of verification. Do NOT
   reuse running agents by broadcasting "verify again" — this is explicitly
   prohibited.

4. **All document owners participate.** Each agent reads ALL docs (not just their
   own) and raises issues where cross-document references, field names, message
   types, or terminology disagree. Agents message each other directly to resolve
   findings.

5. **One file per issue.** Verification findings are written as individual
   review-note files in `v<X>/review-notes/`, following the naming and format
   conventions in [Review Notes & Handover Docs](../conventions/review-and-handover-docs.md).

6. **Verification must complete before commit.** The team lead MUST NOT commit
   revised documents until at least one clean verification round (no issues
   found) is achieved.

### Verification Checklist

Agents should check at minimum:

- [ ] Message type registry (doc 01 or equivalent) lists every message type
  defined in all other docs
- [ ] Error codes cover all error references across all docs
- [ ] Field names are consistent (e.g., `num_dirty_rows` not `dirty_row_count`)
- [ ] Message names are consistent (e.g., `KeyEvent` not `KeyInput`)
- [ ] Cross-references point to correct doc/section and the target exists
- [ ] Capability flags match their usage descriptions
- [ ] State enums/constants match between protocol docs and any external contracts
- [ ] Terminology is uniform (e.g., "4-tier" vs "5-tier", "stale" vs "degraded")
- [ ] Version headers are updated in all modified docs
- [ ] Changelog/appendix entries accurately describe what changed

### Task Dependencies

```
Task: Apply revisions to docs          (Phase 3)
Task: Verification round 1             (blocked by revisions)
Task: Fix issues from round 1          (blocked by round 1, if issues found)
Task: Verification round 2             (blocked by fixes, if fixes were needed)
```

### Workflow

1. Create a new team (or reuse if agents are still alive)
2. Each agent reads ALL docs in the current version directory
3. Each agent raises issues via direct messages to the doc owner
4. Doc owners fix issues in their docs
5. Repeat until a clean round is achieved
6. Write findings as individual files in `v<X>/review-notes/`
7. Team lead commits

---

## Phase 4: Handover Document

When a session ends (context exhaustion, natural completion, or explicit stop), the
team lead MUST write a handover document before closing. This enables the next session
to continue without re-reading all review notes and re-discovering context.

### Purpose

The handover captures **what is NOT in the review notes** — context, perspective,
and judgment that would otherwise be lost between sessions. The reader is expected
to read all review notes in `v<X>/review-notes/` independently; the handover does
not repeat their content.

### Location

```
docs/design/topic/v<X>/handover/handover-to-v<next>.md
```

### Content and Format

See [Review Notes & Handover Docs](../conventions/review-and-handover-docs.md)
Section 3 for the full format specification.

**Key principle**: Handovers record insights, design philosophy, owner priorities,
and new conventions — NOT per-issue checklists or file location indexes.

---

## Custom Agent Registration

Protocol team members can be registered as Claude Code custom agents for consistent
role assignment across sessions. This eliminates the need to re-describe each role's
domain, owned documents, and key decisions in every spawn prompt.

### Location

Agent definitions are organized by team under `.claude/agents/`. Each team has its
own directory containing Markdown files for its members.

> For a list of all available teams and their purposes, see [Agent Team Definitions](agent-team-definition.md).

Example structure:
```
.claude/agents/<team-name>/
├── role-a.md          # Core member: owns specific docs
├── role-b.md          # Core member: owns specific docs
└── researcher.md      # Optional: reference codebase analysis
```

### File Format

Each agent is a Markdown file with YAML frontmatter:

```yaml
---
name: agent-name
description: >
  When Claude should delegate to this agent
model: opus
tools:
  - Read
  - Grep
  - Glob
  - Write
  - Edit
  - Bash
---

System prompt body: role identity, domain, key decisions, output format.
```

### Core vs. Expert Agents

| Type | Model | Tools | Writes docs? | Purpose |
|------|-------|-------|-------------|---------|
| Core | `opus` | All including Write/Edit | Yes | Design, review, write spec docs |
| Expert | `opus` | Read-only (Read, Grep, Glob, Bash) | No | Investigate reference codebases, report findings |

> **Model policy**: Use `opus` by default for all agents. Only use `sonnet` for
> trivially mechanical tasks (e.g., file listing, simple string extraction). Never
> use `haiku`.

### Usage in Team Workflow

Custom agents are invoked as slash commands. For example, typing `/protocol-architect`
runs the agent with its predefined system prompt, model, and tool restrictions.

When spawning agents via the Agent tool (e.g., for team workflows), use
`subagent_type: "general-purpose"` and include the role-specific context from the
custom agent file in the spawn prompt. The custom agent files serve as canonical
role definitions — the team lead reads them to construct consistent spawn prompts.

Researchers are spawned on-demand when a debate requires evidence from reference
codebases. They report findings to core members who incorporate them into design docs.

### Maintaining Agent Files

Update agent files when:
- A new protocol version introduces key decisions that should not be re-debated
- A new reference codebase is added to `~/dev/git/references/`
- A new core role or researcher type is needed
- Tool requirements change (e.g., a researcher needs Write access for a special task)

Do NOT update agent files with session-specific context (current task, in-progress
work). Agent files should contain stable, reusable knowledge only.

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
| Single-pass verification misses fix regressions | Cross-doc verification finds issues, fixes are applied, but fixes themselves are not verified | **Always run a second verification round after fixes.** The first round finds issues; fixes applied during the first round are themselves unverified changes. A second round with fresh agents confirms the fixes are correct, complete, and did not introduce new inconsistencies. Both spec areas (e.g., IME + protocol) must participate in each round. |

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
