# Document Artifact Conventions

This directory contains conventions for all document artifacts produced during
the design workflow. Each artifact type has its own file.

---

## Directory Structure

Full path: `docs/{component}/02-design-docs/{topic}/`

Draft version directories contain all working artifacts. Stable version
directories contain only the final spec documents. The `inbox/` directory is the
input tray for the next revision cycle — it holds the stable handover and any
incoming cross-team requests received while the team is idle (stable declared,
no new draft started yet). **If the target team has an active draft, cross-team
requests go directly into that draft's `cross-team-requests/` directory — NOT
into `inbox/`.** See [07-cross-team-requests.md](./07-cross-team-requests.md)
for full placement rules.

**Example 1 — active work on v1.0-r3 (v1.0 not yet stable):**

```
{topic}/
├── inbox/
│   ├── handover/             ← empty until stable declared
│   └── cross-team-requests/
│       └── 01-{source-team}-{topic}-from-v{X.Y}.md   ← ONLY when team is idle
├── draft/
│   ├── v1.0-r1/              ← historical; all possible subdirectories shown here
│   │   ├── TODO.md
│   │   ├── 01-spec-doc.md
│   │   ├── 02-spec-doc.md
│   │   ├── design-resolutions/
│   │   │   ├── 01-{topic}.md
│   │   │   └── ...
│   │   ├── research/
│   │   │   ├── 01-{source}-{topic}.md
│   │   │   └── ...
│   │   ├── review-notes/
│   │   │   ├── 01-{topic}.md
│   │   │   └── ...
│   │   ├── cross-team-requests/
│   │   │   ├── 01-{source-team}-{topic}.md   ← requests targeting active draft
│   │   │   └── ...
│   │   ├── verification/
│   │   │   ├── round-1-issues.md
│   │   │   ├── round-2-issues.md
│   │   │   └── ...
│   │   └── handover/
│   │       └── handover-to-r2.md
│   ├── v1.0-r2/              ← historical
│   │   └── ...
│   └── v1.0-r3/              ← current working version
│       ├── TODO.md
│       ├── 01-spec-doc.md    (updated)
│       └── ...
└── (vX.Y/ does not exist until stable declared)
```

**Example 2 — new topic bootstrapped via seed round (r0):**

A seed round (`r0`) is used when a cross-team request targets a topic that has
no prior drafts. The `r0` directory contains only cross-team requests and a
handover — no spec documents or other process artifacts.

```
{topic}/
├── draft/
│   └── v1.0-r0/              ← seed round (no spec docs); no inbox/ for new topics
│       ├── cross-team-requests/
│       │   └── 01-{source-team}-{topic}.md
│       └── handover/
│           └── handover-to-r1.md
└── (vX.Y/ does not exist until stable declared)
```

**Example 3 — v1.0 stable declared, v1.1 work in progress:**

```
{topic}/
├── inbox/
│   ├── handover/
│   │   └── handover-for-v1.0.md              ← consumed at v1.1-r1 Requirements Intake
│   └── cross-team-requests/
│       └── 01-protocol-team-keyframe-model-from-v0.7.md  ← team was idle when received
├── draft/
│   ├── v1.0-r1/              ← historical
│   ├── v1.0-r2/              ← historical
│   ├── v1.0-r3/              ← historical
│   └── v1.1-r1/              ← current working version
│       ├── TODO.md
│       ├── 01-spec-doc.md
│       └── ...
└── v1.0/                     ← stable; spec docs only
    ├── 01-spec-doc.md
    └── 02-spec-doc.md
```

---

## Artifact Index

| Artifact                      | Convention File                                          |
| ----------------------------- | -------------------------------------------------------- |
| Review Notes                  | [02-review-notes.md](./02-review-notes.md)               |
| Handover Documents            | [03-handover.md](./03-handover.md)                       |
| Design Resolutions            | [04-design-resolutions.md](./04-design-resolutions.md)   |
| Research Reports              | [05-research-reports.md](./05-research-reports.md)       |
| Review Resolutions            | [06-review-resolutions.md](./06-review-resolutions.md)   |
| Cross-Team Requests           | [07-cross-team-requests.md](./07-cross-team-requests.md) |
| Verification Issues           | [08-verification-issues.md](./08-verification-issues.md) |
| TODO                          | [09-todo.md](./09-todo.md)                               |
| Architecture Decision Records | [10-adr.md](./10-adr.md)                                 |

---

## Anti-Patterns

| Anti-pattern                                                                                                                        | Problem                                                                                                            | Correct approach                                                                                                                                                                            |
| ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One giant review-notes file with 20+ issues                                                                                         | Hard to track, hard to resolve individually                                                                        | One file per topic                                                                                                                                                                          |
| Handover that repeats review notes content                                                                                          | Duplication, divergence risk                                                                                       | Handover captures insights only; reader reads review notes separately                                                                                                                       |
| Review notes without severity                                                                                                       | No prioritization                                                                                                  | Always assign severity                                                                                                                                                                      |
| Review notes without status                                                                                                         | Can't tell what's resolved                                                                                         | Always maintain status field                                                                                                                                                                |
| Agent team review producing review-notes files                                                                                      | Confuses tracking — team resolves issues inline                                                                    | Team produces design-resolutions or review-resolutions, not review-notes                                                                                                                    |
| Mixing multiple unrelated topics in one review note                                                                                 | Hard to track resolution independently                                                                             | One topic per file, even if both are LOW severity                                                                                                                                           |
| Placing process artifacts (review-notes, design-resolutions, verification, research, cross-team-requests, handover) in stable vX.Y/ | Stable dirs are spec-only. Process artifacts live in draft/vX.Y-rN/; the stable handover lives in inbox/handover/. | All process artifacts stay in draft/vX.Y-rN/. Write handover-for-vX.Y.md to inbox/handover/ at stable declaration.                                                                          |
| Placing cross-team requests in `inbox/` when target team has an active draft                                                        | Bypasses current revision cycle; request gets orphaned until next intake                                           | Check if `draft/vX.Y-rN/` exists; if yes, place in `draft/vX.Y-rN/cross-team-requests/` (no `-from-v{X.Y}` suffix). Use `inbox/` only when team is idle (stable declared, no active draft). |
| Placing cross-team requests in `inbox/` for a brand-new topic with no prior drafts                                                  | No intake process exists to consume inbox; request is orphaned                                                     | Create a seed round `draft/v1.0-r0/` with the CTR and a `handover-to-r1.md`.                                                                                                                |

---

For the workflow that produces these artifacts, see
[Design Workflow](../../../work-styles/03-design-workflow.md).
