# Document Artifact Conventions

This directory contains conventions for all document artifacts produced during the
design workflow. Each artifact type has its own file.

---

## Directory Structure

Each version directory contains subdirectories for review and design artifacts:

```
v<X>/
├── TODO.md
├── 01-spec-doc.md
├── 02-spec-doc.md
├── ...
├── design-resolutions/
│   ├── 01-{topic}.md
│   └── ...
├── research/
│   ├── 01-{source}-{topic}.md
│   └── ...
├── review-notes/
│   ├── 01-{topic}.md
│   └── ...
├── cross-team-requests/
│   ├── 01-{source-team}-{topic}.md
│   └── ...
├── verification/
│   ├── round-1-issues.md
│   ├── round-2-issues.md
│   └── ...
└── handover/
    └── handover-to-v<next>.md
```

---

## Artifact Index

| Artifact | Convention File |
|----------|----------------|
| Review Notes | [02-review-notes.md](./02-review-notes.md) |
| Handover Documents | [03-handover.md](./03-handover.md) |
| Design Resolutions | [04-design-resolutions.md](./04-design-resolutions.md) |
| Research Reports | [05-research-reports.md](./05-research-reports.md) |
| Review Resolutions | [06-review-resolutions.md](./06-review-resolutions.md) |
| Cross-Team Requests | [07-cross-team-requests.md](./07-cross-team-requests.md) |
| Verification Issues | [08-verification-issues.md](./08-verification-issues.md) |
| TODO | [09-todo.md](./09-todo.md) |

---

## Anti-Patterns

| Anti-pattern | Problem | Correct approach |
|-------------|---------|-----------------|
| One giant review-notes file with 20+ issues | Hard to track, hard to resolve individually | One file per topic |
| Handover that repeats review notes content | Duplication, divergence risk | Handover captures insights only; reader reads review notes separately |
| Review notes without severity | No prioritization | Always assign severity |
| Review notes without status | Can't tell what's resolved | Always maintain status field |
| Agent team review producing review-notes files | Confuses tracking — team resolves issues inline | Team produces design-resolutions or review-resolutions, not review-notes |
| Mixing multiple unrelated topics in one review note | Hard to track resolution independently | One topic per file, even if both are LOW severity |

---

For the workflow that produces these artifacts, see [Design Workflow](../../../work-styles/03-design-workflow.md).
