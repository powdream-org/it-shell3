---
name: triage
description: >
  Use when issues are discovered that require owner disposition — during
  implementation verification, design-doc-revision, spec compliance review,
  over-engineering review, or retrospective. Invoke BEFORE presenting any
  individual issue to the owner.
---

# Issue Triage Skill

## 1. Procedure

1. **Group issues by component or area.** Do NOT group by severity — severity
   groups pre-bias triage order and hide relationships between issues in the
   same area. Do NOT start presenting issues before grouping is complete.

2. **Present the group index.** Show the owner a compact table with one-line
   titles per issue. This gives the owner a birds-eye view before diving in.

3. **Owner picks the next group.** The owner chooses which group to discuss
   first. Never choose for them. If the owner says "go in order," follow the
   table order.

4. **Present one issue at a time** using the 5W1H priority order defined below.
   The presentation must be self-contained — the owner decides WITHOUT opening
   any files.

5. **Wait for the owner's disposition.** Do not prompt, suggest, or nudge. The
   owner may ask clarifying questions — answer them, then wait again.

6. **Record the disposition verbatim.** Write down exactly what the owner
   decided, using their words. Do not paraphrase into a different action.

7. **Return to the group.** Present the next issue in the group. When a group is
   exhausted, let the owner pick the next group.

8. **After all issues are dispositioned, collect and apply.** Summarize all
   dispositions in a single list, confirm with the owner, then execute. Never
   execute partial dispositions mid-triage.

The set of valid dispositions is **caller-provided** — each workflow step
defines its own set. This skill does NOT hardcode any disposition set.

## 2. 5W1H Presentation Priority

Present every issue in this exact order. Each element serves a specific purpose.

### 1st — What (Headline)

A single sentence stating the conflict. This anchors the owner's attention.

### 2nd — Why (Background / Motivation / Conflict)

Explain WHY this is a conflict, not just THAT it is one. Provide the
motivational context: what design goal or requirement created the tension? What
were the competing concerns? This helps the owner understand whether the issue
is a bug, a design gap, or an intentional tradeoff that was never documented.

### 3rd — Who (Parties in Conflict)

Identify which artifacts, teams, or decisions are in tension. The conflict can
be between any combination: spec ↔ code, spec ↔ spec, code ↔ code, opinion ↔
opinion, spec ↔ library limitation, or any other pairing. The owner needs to
know whose authority clashes.

### 4th — When (Timeline)

State whether this is pre-existing (carried from a previous revision or plan) or
newly introduced. If pre-existing, say when it was introduced and why it was not
caught earlier. Timeline affects urgency and blame-free disposition.

### 5th — Where (FULL Evidence)

This is the longest and most critical section. Provide ALL evidence the owner
needs: full spec quotes with file paths and line numbers, full code blocks with
file paths, full table rows, call-site inventories, state machine transitions.
The owner must be able to make a decision WITHOUT opening any files. Summarized
evidence is worthless — it forces the owner to investigate, which is the
triager's job.

### 6th — How (Decision Required)

State what the owner needs to decide. Frame it as an open question, not a binary
"fix or dismiss." The owner may choose options you did not anticipate: defer,
split, rewrite the spec, add an ADR, escalate, or declare it intentional. Never
constrain the decision space.

## 3. Quality Examples

See `examples/` directory for detailed examples showing the quality bar:

| File                           | Conflict type                 |
| ------------------------------ | ----------------------------- |
| `examples/01-spec-vs-code.md`  | Spec ↔ Code                   |
| `examples/02-spec-vs-spec.md`  | Spec ↔ Spec                   |
| `examples/03-process-issue.md` | Process issue (SIP)           |
| `examples/04-code-vs-code.md`  | Code ↔ Code                   |
| `examples/05-spec-vs-os.md`    | Spec ↔ OS behavior            |
| `examples/06-os-vs-os.md`      | OS ↔ OS (platform divergence) |

**Read the example closest to your conflict type before presenting.** The
examples ARE the teaching mechanism — they show the depth expected.

## 4. Anti-patterns

**Batch triage.** Presenting all issues in a single wall of text. The owner
cannot track decisions across 10+ issues simultaneously. Always present one at a
time after showing the index.

**Compressed summaries.** Writing a one-line description instead of showing the
full function, the spec quote, and all call sites. Compressed summaries force
the owner to investigate, which is the triager's job.

**Self-triage.** Deciding that an issue is "minor" or "obvious" and pre-deciding
the disposition. Every issue that requires judgment goes through triage. Only
mechanical fixes (typos, formatting) skip triage.

**Fixing during triage.** Starting to write code or edit specs while triage is
in progress. Triage is a decision-making phase, not an execution phase.

**Pressuring the owner.** Adding urgency markers, severity opinions, or
recommendations to the presentation. Present evidence, not opinions.

**Fixed template.** Using a rigid "Spec says / Code does" form that forces every
issue into the same shape. The 5W1H order is fixed, but the content adapts to
the conflict type.

**Skipping the group index.** Jumping straight to the first issue without
showing the full landscape. The index lets the owner prioritize and may reveal
that two issues are actually one.
