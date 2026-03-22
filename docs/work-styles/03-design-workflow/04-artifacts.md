# Design Workflow — Artifacts

## Artifact Matrix

| Artifact                              | Created During      | Created By                   | Location                                                                     | Convention                                                                                |
| ------------------------------------- | ------------------- | ---------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `design-resolutions-{topic}.md`       | Revision 3.3        | Core member (representative) | `draft/vX.Y-rN/design-resolutions/`                                          | [design-resolutions.md](../../conventions/artifacts/documents/04-design-resolutions.md)   |
| `research-{source}-{topic}.md`        | Revision 3.2        | Researcher                   | `draft/vX.Y-rN/research/`                                                    | [research-reports.md](../../conventions/artifacts/documents/05-research-reports.md)       |
| Spec documents (`01-xx.md`, etc.)     | Revision 3.5        | Core members                 | `draft/vX.Y-rN/`                                                             | --                                                                                        |
| `review-notes/{NN}-{topic}.md`        | Review 4.2          | Team leader                  | `draft/vX.Y-rN/review-notes/`                                                | [review-notes.md](../../conventions/artifacts/documents/02-review-notes.md)               |
| `handover-to-r(N+1).md`               | Review 4.3          | Team leader                  | `draft/vX.Y-rN/handover/`                                                    | [handover.md](../../conventions/artifacts/documents/03-handover.md)                       |
| `handover-for-vX.Y.md`                | Review 4.3 (stable) | Team leader                  | `{topic}/inbox/handover/`                                                    | [handover.md](../../conventions/artifacts/documents/03-handover.md)                       |
| `cross-team-requests/{NN}-{topic}.md` | Revision 3.5        | Core member                  | Target team's `draft/vX.Y-rN/cross-team-requests/` or `{team}/inbox/` (idle) | [cross-team-requests.md](../../conventions/artifacts/documents/07-cross-team-requests.md) |
| `round-{N}-issues.md`                 | Revision 3.8        | Team leader                  | `draft/vX.Y-rN/verification/`                                                | [verification-issues.md](../../conventions/artifacts/documents/08-verification-issues.md) |
| `TODO.md`                             | Revision 3.1        | Team leader                  | `draft/vX.Y-rN/TODO.md`                                                      | [TODO Convention](../../conventions/artifacts/documents/09-todo.md)                       |

## Version Directory Structure

See
[Document Artifact Conventions — Directory Structure](../../conventions/artifacts/documents/01-overview.md#directory-structure)
for the canonical directory layout with examples.
