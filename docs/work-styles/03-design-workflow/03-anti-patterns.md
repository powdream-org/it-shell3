# Design Workflow — Anti-Patterns Reference

This is the consolidated reference table. Individual anti-patterns are also
placed inline within the relevant skill step files for just-in-time visibility.

---

## Revision Cycle Anti-Patterns

| Anti-pattern                                                                          | Why it is wrong                                                                                                       | Correct behavior                                                                                                                                    |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Team leader writes review notes after committing, without owner instruction           | Review notes record the **owner's** concerns. A team leader's self-assessment is not a review note.                   | STOP after 3.9. Write review notes only when the owner explicitly instructs in 4.2.                                                                 |
| Team leader writes handover after committing, without owner declaring review complete | Handover summarizes what the **owner** learned during review. No review happened.                                     | Write handover only after the owner explicitly declares the review cycle complete in 4.3.                                                           |
| Team leader commits review notes or handover in the same commit as spec docs          | Conflates Revision and Review cycles, making git history unreadable.                                                  | Spec docs are committed in 3.9. Review notes and handover are committed separately in 4.2/4.3.                                                      |
| Team leader self-declares "review complete" and proceeds to next revision             | Only the owner can declare a review complete.                                                                         | Wait for the owner. Do not advance the cycle without an explicit owner declaration.                                                                 |
| Agents edit files before writing gate (3.5)                                           | Fastest agent applies all fixes; others find nothing to do — duplicate edits, merge conflicts, wasted work.           | No editing until the team leader signals "begin writing" in 3.5.                                                                                    |
| Team leader prompts consensus reporter to deliver (3.2→3.3)                           | Pre-empts the reporter's autonomous judgment; may cut off a team member who had more to say.                          | The consensus reporter decides when consensus is reached and delivers unprompted. The team leader waits.                                            |
| Team stops at resolution document and skips document writing                          | Resolution document is an intermediate artifact, not the deliverable. Spec documents are never updated.               | After the resolution is verified, assigned agents must produce updated spec files in 3.5.                                                           |
| Team leader writes verification issues to `review-notes/`                             | Conflates verification artifacts with owner feedback.                                                                 | Write issues to `draft/vX.Y-rN/verification/round-{N}-issues.md`. Review notes are only created at owner instruction in 4.2.                        |
| Team leader leaves Phase 1 or Phase 2 agents alive after they report                  | Agents accumulate, consuming tokens and creating confusion.                                                           | Disband immediately after collecting reports.                                                                                                       |
| Team leader tells verification agents to "read files" or "analyze documents directly" | Overrides the Gemini-delegation workflow, defeating the token-saving architecture.                                    | Provide file paths only. Agents follow their agent-definition workflow (invoke-agent to Gemini).                                                    |
| Team leader spawns Phase 1 agents in Round 2+ without Dismissed Issues Registry       | Phase 1 agents have no memory of prior rounds and re-raise settled findings.                                          | Pass structured Dismissed Issues Registry to Phase 1 spawn prompt from Round 2 onward.                                                              |
| Fix round uses sonnet for document writing                                            | Sonnet lacks design context and produces incorrect, shallow, or subtly wrong content that wastes verification rounds. | Use opus for ALL document writing regardless of round number. Token savings come from reducing rounds (cascade analysis), not from model downgrade. |

## Team Collaboration Anti-Patterns

See
[Team Collaboration §7](../02-team-collaboration.md#7-lessons-learned-and-anti-patterns)
for the full list covering:

- Agent file creation failures
- Discussion = deliverable confusion
- Terminology drift
- Message proxying through leader
- Wrong approach/API usage
- Majority vote producing false consensus
- Team leader micromanaging
- Agent starting work before team assembles
- Zombie cleanup without verification
- Glob for team member discovery (use `ls -la` instead)
