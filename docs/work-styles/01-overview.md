# How We Work

## 1. Overview

This project uses Claude Code agent teams to collaboratively produce system design specifications. Three roles drive every activity:

- **Team leader** (Claude Code main agent) — Facilitates the process: spawns agents, assigns tasks, tracks progress, and reports to the owner. The team leader does NOT do research, writing, or implementation directly.
- **Owner** (human) — Provides requirements, reviews output, and makes final decisions.
- **Teammates** (sub-agents) — Do the actual work: research, drafting, reviewing, and implementing.

All work follows two recurring cycles: a **revision cycle** where the team produces or updates documents, and a **review cycle** where the owner evaluates them and decides what happens next.

## 2. Documents

| Document | Description |
|----------|-------------|
| [Team Collaboration](./02-team-collaboration.md) | How we organize teams, define roles, and communicate. Rules that apply to all team activities (design, PoC, etc.). |
| [Design Workflow](./03-design-workflow.md) | The revision/review cycle for producing and evolving design specification documents. |
| [PoC Workflow](./04-poc-workflow.md) | When, why, and how we run Proof-of-Concept experiments to validate design assumptions. |

## 3. Related Conventions

| Document | Description |
|----------|-------------|
| [Commit Messages](../conventions/commit-messages.md) | Conventional commits format. English only. |
| [Review and Handover Docs](../conventions/artifacts/documents/01-overview.md) | Artifact conventions: review notes, handover documents, design resolutions, research reports, cross-team requests. |
