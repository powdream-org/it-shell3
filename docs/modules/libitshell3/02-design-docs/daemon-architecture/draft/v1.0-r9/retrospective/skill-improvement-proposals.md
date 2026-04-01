# Skill Improvement Proposals

## SIP-1: Round 3+ verification should escalate to owner after Phase 1

**Discovered during**: Step 5 (Verification Round 2) / Step 6 (Fix Round
Decision)

**What happened**: After Round 2 fix (1 mechanical issue — header size in offset
table), the team lead asked the owner whether to proceed with Round 3 or declare
clean. The skill's Step 6 says Rounds 1-3 are automatic fix rounds, but
empirically Round 3+ issues are few and mostly minor. The owner directed: run
Phase 1, then `/triage` for owner decision. The "should I proceed?" question
itself was unnecessary friction.

**Root cause**: Step 6's threshold (Round 4+ for owner escalation) is too late.
By Round 3, issues have declined to minor/pre-existing severity and diminishing
returns are evident (consistent with L2 in design-principles.md). The automatic
fix round for Rounds 1-3 doesn't account for this convergence pattern. The team
lead also asked "should I proceed?" after Round 2, which the owner explicitly
said not to do.

**Affected steps**:

- `steps/06-fix-round.md` — Section 6c decision table

**Proposed changes**:

1. Change the decision table threshold from Round 4+ to Round 3+:

   | Condition              | Action                                          |
   | ---------------------- | ----------------------------------------------- |
   | **Round 1-2**          | Automatic fix round. Go to Step 4.              |
   | **Round 3+ non-CLEAN** | Run Phase 1 only. `/triage` for owner decision. |

2. Add anti-pattern to Step 6: "Do NOT ask 'should I proceed?' after a fix
   round. Round 1-2: auto-proceed. Round 3+: run Phase 1 and `/triage`
   automatically."

## SIP-2: Team leader must read triage quality examples before presenting

**Discovered during**: Step 6 (Fix Round Decision) — `/triage` for Round 3 Phase
1 results

**What happened**: The team leader presented a triage issue (Group B: Doc 04
pre-existing cross-ref) with a compressed 5-line summary instead of the full
5W1H quality bar. The owner could not understand the issue from the presentation
alone and had to ask "조금더 자세히. /triage의 quality bar example들을 본거야?"
— forcing the team leader to re-read the examples and re-present with proper
depth (flow explanation, conflict point marking, minimal citation).

**Root cause**: The `/triage` skill says "Read the example closest to your
conflict type before presenting" but this instruction is buried in Section 3
under "Quality Examples." The team leader skipped it, treating the 5W1H
structure as sufficient without calibrating depth against the examples. The
examples ARE the teaching mechanism — the 5W1H headings alone do not convey the
expected depth.

**Affected steps**:

- `.claude/skills/triage/SKILL.md` — Section 1 (Procedure) and Section 4
  (Anti-patterns)

**Proposed changes**:

1. Add to Section 1, Step 4 (after "Present one issue at a time"): "**Before
   presenting the first issue, read the quality example closest to your conflict
   type** (Section 3). The examples define the depth expected — the 5W1H
   headings alone are insufficient."
2. Add anti-pattern to Section 4: **"Skipping quality examples.** Presenting
   issues using only the 5W1H headings without reading the examples first. The
   headings define structure; the examples define depth. Without calibrating
   against examples, presentations are too shallow for owner decision-making."

## SIP-3: Phase 1 CLEAN = auto-declare clean, no owner confirmation needed

**Discovered during**: Step 5 (Verification Round 4) / Step 6 (Fix Round
Decision)

**What happened**: Round 4 Phase 1 returned CLEAN from both verifiers. The team
leader asked "Declare clean?" and then asked again — twice — waiting for owner
confirmation on something that required no decision. If Phase 1 finds zero
issues, there is nothing to triage and nothing to decide. The clean state is a
fact, not a judgment call.

**Root cause**: SIP-1 changed the Round 3+ flow to "run Phase 1, then `/triage`
for owner decision." But `/triage` only applies when there ARE issues to
disposition. When Phase 1 is CLEAN, there are no issues — the triage step is
vacuous. The team leader treated "owner decision" as always required for Round
3+, even when the decision is predetermined by the CLEAN result.

**Affected steps**:

- `steps/06-fix-round.md` — Section 6c decision table (SIP-1 proposed changes)

**Proposed changes**:

1. Refine the SIP-1 proposed decision table:

   | Condition              | Action                                          |
   | ---------------------- | ----------------------------------------------- |
   | **Round 1-2**          | Automatic fix round. Go to Step 4.              |
   | **Round 3+ CLEAN**     | Auto-declare clean. Go to Step 7.               |
   | **Round 3+ non-CLEAN** | Run Phase 1 only. `/triage` for owner decision. |

2. Add anti-pattern: "Do NOT ask the owner to confirm a CLEAN result. CLEAN is a
   fact reported by verifiers, not a judgment requiring owner approval."
