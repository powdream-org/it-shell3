# Team Collaboration

## 1. Overview

We work as agent teams. The team leader (Claude Code main agent) facilitates; teammates (sub-agents) do the actual work; the owner (human) provides requirements, reviews output, and makes binding decisions.

This document defines how teams are structured, how members communicate, and what rules govern collaboration. These rules apply to ALL team activities — design, PoC, review, verification, and implementation. The specific workflows for each activity type are documented separately in [Design Workflow](./03-design-workflow.md) and [PoC Workflow](./04-poc-workflow.md).

---

## 2. Team Composition

### 2.1 Core Members (opus)

Core members are domain experts who participate in discussion, debate, write specifications, and verify documents. They are the intellectual backbone of every team.

| Aspect | Detail |
|--------|--------|
| **Model** | Always `opus`. Never `sonnet` or `haiku` for core work. |
| **Tools** | Full set: Read, Grep, Glob, Write, Edit, Bash |
| **Typical roles** | Protocol Architect, Systems Engineer, CJK Specialist, IME Expert, Principal Architect, ghostty Expert |
| **Responsibilities** | Design debate, document drafting, cross-document consistency verification, consensus building, resolution writing |

Each core member owns specific documents and brings deep domain expertise. Ownership means the member is the primary author, defender, and maintainer of those documents within the team.

**Core members MUST be used for:**
- Design debate and architectural decision-making
- Document writing (initial drafts, revisions, applying resolutions)
- Cross-document consistency verification (Revision Cycle step 3.5)
- Cross-component review

**Why opus for all document writing:** Previously, the project tried using `sonnet` "spec-writers" for mechanical document updates (applying agreed resolutions to produce a new version). This produced serious quality problems: spec-writers lacked design context and generated incorrect content, shallow descriptions, and subtle semantic errors that only surfaced during later verification rounds — wasting significant effort. All document writing is now done by opus core members who understand the design intent behind every section.

### 2.2 Researchers (opus, read-only)

Researchers are spawned on demand when a design debate requires evidence from reference codebases. They investigate, report findings, and then shut down.

| Aspect | Detail |
|--------|--------|
| **Model** | `opus` |
| **Tools** | Read-only: Read, Grep, Glob, Bash |
| **Reference codebases** | `~/dev/git/references/` — ghostty, tmux, zellij, iTerm2 |
| **Scope** | Each researcher targets one reference codebase |

**What researchers produce:** Findings reports containing source file paths, code references, relevant struct/function signatures, and trade-offs observed in the reference implementation.

**What researchers do NOT do:**
- Write or edit design documents
- Make design recommendations or advocate for specific approaches
- Participate in consensus decisions

Researchers provide raw material. Core members read the findings and incorporate them into the design. The separation is strict: researchers report facts; core members make judgments.

### 2.3 Teams Registry

| Team | Directory | Purpose |
|------|-----------|---------|
| `protocol-team` | `.claude/agents/protocol-team/` | Server-client binary protocol design: wire format, message framing, session/pane management, flow control, CJK preedit protocol, handshake/capability negotiation |
| `ime-team` | `.claude/agents/ime-team/` | IME interface contract design: ImeEngine vtable, Korean Hangul composition via libhangul, ImeResult semantics, ghostty integration layer |
| `references-expert` | `.claude/agents/references-expert/` | Source-level analysis of reference codebases. Read-only. Spawned on demand when debates need implementation evidence. |

---

## 3. Custom Agent Registration

### 3.1 File Location and Structure

Agent definitions live under `.claude/agents/<team-name>/`. Each agent is a Markdown file named after its role.

```
.claude/agents/protocol-team/
    protocol-architect.md
    systems-engineer.md
    cjk-specialist.md

.claude/agents/ime-team/
    principal-architect.md
    ime-expert.md

.claude/agents/references-expert/
    ghostty-expert.md
    tmux-expert.md
    zellij-expert.md
    iterm2-expert.md
```

### 3.2 File Format

Each file has YAML frontmatter followed by a system prompt body:

```yaml
---
name: agent-name
description: >
  When Claude should delegate to this agent. Lists the specific topics,
  documents, and trigger conditions.
model: opus
tools:
  - Read
  - Grep
  - Glob
  - Write
  - Edit
  - Bash
---

System prompt body: role identity, owned documents, domain expertise,
settled decisions (do NOT re-debate), output format, reference codebases.
```

The `description` field tells the team leader when to spawn this agent. The system prompt body gives the agent its working context.

### 3.3 Core vs Researcher Differences

| Aspect | Core Member | Researcher |
|--------|-------------|------------|
| Model | `opus` | `opus` |
| Tools | All (Read, Grep, Glob, Write, Edit, Bash) | Read-only (Read, Grep, Glob, Bash) |
| Writes docs? | Yes | No |
| Makes decisions? | Yes, within team consensus | No — reports findings only |
| Lifespan | Active for entire workflow phase | Spawned on demand, shut down after report |
| System prompt | Includes owned docs, settled decisions, output format | Includes reference codebase paths, investigation scope, output format |

### 3.4 When to Update Agent Files

**Update when:**
- A new version introduces key decisions that should not be re-debated (add to "Settled Decisions")
- A new reference codebase is added to `~/dev/git/references/`
- A new role is needed for the team
- Tool requirements change

**Do NOT update with:**
- Session-specific context (current task, in-progress work)
- Temporary information (current review round number, open issue lists)
- Content that changes every session

Agent files contain stable, reusable knowledge only. Session context is provided via spawn prompts.

---

## 4. Team Leader: Role and Constraints

The team leader is the Claude Code main agent. It orchestrates team activities but does not perform substantive work. This is the single most important rule in the entire collaboration model.

### 4.1 MUST Do

| Responsibility | Detail |
|----------------|--------|
| **Facilitate** | Set goals and scope for each round. Define what the team should produce, not how to produce it. |
| **Relay owner instructions** | When the owner makes a binding decision, broadcast it to the team with clear attribution: "Owner decision: ..." |
| **Report to owner** | Provide progress, status, and opinion summaries. Summarize ALL positions fairly — do not filter or editorialize. |
| **Write review notes** | ONLY when the owner explicitly instructs. Follow the format in `docs/conventions/artifacts/documents/01-overview.md`. |
| **Write handover** | At the end of a review cycle, capture insights and new knowledge for the next revision. Follow handover conventions. |
| **Write verification issues** | After a verification round finds issues, collect all verifier reports and record the issues verbatim in `v<X>/verification/round-{N}-issues.md`. This file is passed to the next 3.4 fix team as input. |
| **Manage team lifecycle** | Create teams, spawn agents, shut down agents, clean up resources. |

### 4.2 MUST NOT Do

| Prohibition | Why |
|-------------|-----|
| **Micromanage** | Never give specific instructions like "change line 43 from X to Y" or "use value A instead of B." State the goal, let teammates figure out the approach. Micromanaging makes the team leader a bottleneck, prevents agents from understanding each other's work, and produces worse outcomes than peer collaboration. |
| **Proxy messages** | Teammates must talk to each other directly. The team leader must NOT relay messages between agents. If Agent A has feedback for Agent B, Agent A messages Agent B. |
| **Judge disputes** | The team leader does NOT break ties or decide who is right. Teammates must convince each other through logical argument. Only the owner can break genuine deadlocks. |
| **Write specs or design docs** | All document writing is done by core team members. The team leader writes only review notes (when owner instructs) and handover documents. |
| **Do research** | Delegate to researchers or core members. Even trivial investigations should be assigned. |
| **Make design decisions** | Design decisions belong to the team through consensus, or to the owner for binding directives. |
| **Choose team size** | When spawning a team, the team leader MUST spawn ALL core members listed in the team's agent directory. The team leader does NOT decide "3 is enough" or "we only need these roles." Team composition is defined by the agent directory, not by the team leader's efficiency judgment. |
| **Assign internal roles** | When teammates need to negotiate (e.g., who verifies which doc, who writes the resolution), the team leader does NOT designate a coordinator or leader among them. All members are peers — they self-organize through peer-to-peer messages. The team leader states the goal and provides materials; the team figures out the rest. |

**Example of correct vs incorrect team leader behavior:**

| Situation | Incorrect (micromanaging) | Correct (facilitating) |
|-----------|--------------------------|------------------------|
| Verification found "16B" vs "14B" header size mismatch | "Agent A, change line 47 of doc 01 to say 16B" | "There is a header size inconsistency between doc 01 and doc 03. The relevant document owners should coordinate and fix it." |
| Two agents disagree on encoding strategy | "Agent B is right, use JSON for this message" | "You both have strong arguments. Keep debating — if you cannot converge, I will escalate to the owner for a binding decision." |
| A resolution needs to be applied to a spec | Leader opens the file and applies the edit directly | "Agent C, apply resolution #7 to your doc. The resolution file is at path X." |
| Team needs to negotiate doc assignments | "Agent A, you coordinate. Others, wait for Agent A's instructions." | "Here are the docs and the goal. Negotiate among yourselves who handles what." |

---

## 5. Team Member Conduct

### 5.1 Peer-to-Peer Communication

- Teammates MUST communicate directly with each other, not through the team leader.
- Use `broadcast` sparingly — only for owner decisions or universal context that all agents need simultaneously.
- Use direct `message` for peer-to-peer technical debate.
- When working on cross-cutting issues, the relevant specialists must discuss directly. For example, if a CJK encoding question affects both the protocol wire format and the IME contract, the Protocol Architect and IME Expert must message each other — the team leader does not relay.
- Idle notifications with `[to <name>]` summaries indicate that peer direct messages are flowing. This is healthy and expected.

### 5.2 Consensus Rules

**Unanimous consensus only. Majority vote is strictly prohibited.**

- All core team members must genuinely agree on a decision. "Reluctant acceptance" or "going along to avoid conflict" does not count as consensus.
- When opinions conflict, team members MUST:
  1. Argue their position with logical reasoning and evidence
  2. Genuinely evaluate the opposing argument — if it is more logical, acknowledge it and change position
  3. Seek evidence to resolve the dispute (spawn a researcher, run a PoC, cite documentation)
- Persuasion through evidence is strongly preferred over theoretical argument alone. Concrete reference codebase analysis, PoC results, or quantitative measurements carry more weight than abstract reasoning.
- If genuine deadlock persists after thorough debate (not after one round of disagreement — after sustained, evidence-backed debate), escalate to the owner for a binding decision. Do NOT manufacture a false consensus to avoid escalation.

**Why not majority vote:** A 2-vs-1 "decision" where the dissenter was never actually convinced often means the dissenter saw a real problem that the majority overlooked. Forcing majority vote suppresses this signal. Unanimous consensus forces the team to fully understand and address every concern.

### 5.3 Research Prior Art Before Designing

When tackling infrastructure or architecture problems, the team MUST research how reference codebases handle the same problem BEFORE designing a solution. This applies to initial design, new problems surfaced during review, and architectural questions raised by the owner.

**Workflow:**

1. Identify the architectural problem (e.g., multi-client resize policy, client health detection, flow control, session persistence)
2. Spawn researcher agents targeting relevant reference codebases at `~/dev/git/references/`
3. Each researcher produces a findings report with:
   - How the reference codebase solves the problem
   - Source file paths and relevant code references
   - Trade-offs observed (what works well, what does not)
4. Core members read all findings reports and use them as input for design — they do NOT design in a vacuum
5. Researchers do NOT write design docs and do NOT make design recommendations; they report findings to core members who incorporate them

**Rationale:** Designing without prior-art research leads to reinventing solved problems or missing known pitfalls. Reference codebases (ghostty, tmux, zellij, iTerm2) have years of production experience with the same problems this project faces.

### 5.4 Designating a Consensus Reporter

In every discussion phase, the team leader MUST explicitly designate one agent (typically the architecture lead or principal architect) as the consensus reporter. This agent's responsibilities are:

- Synthesize all peer-agreed positions into a single coherent report
- Report the final consensus to the team leader — not piecemeal per-agent summaries
- Clearly distinguish between unanimously agreed items, items with noted caveats, and unresolved items

Without a designated reporter, the team leader receives fragmented, potentially contradictory summaries from multiple agents and must reconstruct the consensus — which violates the "do not do research" constraint.

---

## 6. Operational Tips

### 6.1 Context Carry-Forward (Session Loss Recovery)

If a session ends mid-discussion (context window exhaustion, crash, etc.), the previous team's agents become unreachable. To resume:

1. **Force-clean the stale team:** `rm -rf ~/.claude/teams/<name>` then `TeamDelete`
2. **Create a new team** with fresh agents (same roles)
3. **Feed prior discussion as structured context** in each agent's spawn prompt:
   - Prior proposals and agreed positions (extracted from inbox JSON files)
   - Specific unresolved questions with each agent's last position
   - Which tasks were completed vs. still open
4. This avoids re-discussing settled points and lets agents pick up mid-debate

Inbox files from the dead team persist at `~/.claude/teams/<old-name>/inboxes/*.json` until manually cleaned up. Read them to reconstruct context before spawning the new team.

### 6.2 Zombie Agent Cleanup

When `TeamDelete` fails with "Cannot cleanup team with N active member(s)":

- Force-remove: `rm -rf ~/.claude/teams/<name>` then `TeamDelete`
- Agents from dead sessions cannot respond to shutdown requests — they are orphaned processes that no longer exist. The only recourse is filesystem cleanup.

### 6.3 Explicit File Creation Instructions

Agents sometimes complete their reasoning but fail to actually create files on disk. When assigning a task that requires a file output, always be explicit:

- Bad: "Write up the analysis"
- Good: "Use the Write tool to create the analysis at `docs/.../v0.7/research-tmux-resize.md`"

This is especially important for resolution documents, research reports, and new spec versions where the agent might confuse the discussion itself with the deliverable.

### 6.4 Cross-References Between Workflow Documents

| If you need to know... | See |
|------------------------|-----|
| How revision and review cycles work | [Design Workflow](./03-design-workflow.md) |
| When and how to run PoC experiments | [PoC Workflow](./04-poc-workflow.md) |
| File naming for review notes, handovers, resolutions | [Review and Handover Docs](../conventions/artifacts/documents/01-overview.md) |
| Commit message format | [Commit Messages](../conventions/commit-messages.md) |
| Available teams and their directories | Section 2.3 of this document |

---

## 7. Lessons Learned and Anti-Patterns

| Anti-Pattern | Symptom | Correct Approach |
|--------------|---------|------------------|
| **Agents don't create files** | Agent says "done" but no file exists on disk | Be explicit: "Use the Write tool to create file X at path Y." Specify the concrete file output expected after every task. |
| **Discussion = deliverable confusion** | Agent treats the resolution document as the final step and never produces updated spec files | Always specify concrete file outputs expected after discussion. A resolution document is an intermediate artifact, not the end product. |
| **Cross-doc inconsistencies** | Header size says "14B" in one doc and "16B" in another; field names differ across docs | Cross-document consistency verification is mandatory after every revision. See [Design Workflow](./03-design-workflow.md). |
| **Terminology drift** | "Tab" means different things in different documents; "stale" vs "degraded" used interchangeably | Establish a terminology mapping table and broadcast it to all agents before writing starts. |
| **Agents proxy through leader** | All messages flow leader-to-agent instead of agent-to-agent; leader becomes a bottleneck | Instruct agents in their spawn prompt to talk to each other directly. Use direct `message`, not `broadcast`, for peer debate. |
| **Agent uses wrong approach/API** | Wrong technology or API function used (e.g., `ghostty_surface_text()` instead of `ghostty_surface_key()` for raw keys) | Specify the exact technology/API in the task description. Assign domain experts to cross-review before committing. |
| **Sonnet spec-writers produce quality issues** | Spec-writers lack design context and produce incorrect, shallow, or subtly wrong content that wastes verification rounds | Use opus core members for ALL document writing. The spec-writer role pattern (sonnet for mechanical application) has been retired. |
| **Majority vote produces false consensus** | 2-vs-1 "decision" where the dissenter was never actually convinced; the real problem they identified resurfaces later | Require unanimous consensus through logical persuasion. Escalate genuine deadlocks to the owner. Do NOT manufacture false agreement. |
| **Team leader micromanages** | Leader gives step-by-step instructions ("change line 43 from X to Y") instead of stating goals; agents become passive executors | State the objective and constraints. Let the team figure out the approach. If Agent A found the issue, let Agent A negotiate with the doc owner directly. |
