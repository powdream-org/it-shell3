# 00001. Use Architecture Decision Records for Design Decisions

Date: 2026-03-15

## Context

The it-shell3 project is in the design/planning phase and produces significant
architectural decisions across multiple domains: protocol wire format, IME
engine architecture, session/pane model, daemon lifecycle, and more. These
decisions emerge during revision cycles and are captured in handover documents,
design-resolutions, and insights docs — but those artifacts are embedded in
versioned revision directories tied to specific cycles. Navigating them to
reconstruct rationale requires knowing which revision introduced a decision and
then digging through versioned subdirectories.

There is no dedicated, permanent, sequential log of architectural decisions that
a future maintainer can browse as a coherent decision trail. Without such a log,
contributors must reverse-engineer rationale from scattered artifacts or commit
history, and insights risk being lost when revision artifacts are archived.

The npryce/adr-tools format provides a lightweight, proven convention: short
numbered documents with Context, Decision, and Consequences sections — cheap to
write, easy to browse, and permanently stable.

## Decision

Adopt Architecture Decision Records (ADRs) as the canonical mechanism for
recording significant design and implementation decisions. ADRs are stored in
`docs/adr/`, numbered sequentially with 5-digit zero-padded identifiers
(`NNNNN-<slug>.md`), and follow the npryce/adr-tools format with Context,
Decision, and Consequences sections (no Status section — supersession is handled
by writing a new ADR that references the old one).

The `/adr <topic>` skill is used to create them: the agent researches existing
project docs, drafts the full ADR autonomously, and writes the file with the
correct number and date. No manual templating is required.

The convention is enforced in `AGENTS.md`: any meaningful owner decision
(technology selection, protocol tradeoffs, architectural patterns,
implementation strategy) must be accompanied by an ADR.

## Consequences

- Any significant design choice now has a permanent, findable home in
  `docs/adr/` independent of revision cycle artifacts.
- Future maintainers can browse the ADR index to understand the project's
  architectural history without navigating versioned draft directories.
- The cost of recording a decision is low: invoke `/adr <topic>` and the agent
  does the research and writing.
- Requires discipline to invoke `/adr` at decision time. Retroactive ADRs are
  allowed but lose some value (context may be harder to reconstruct).
- ADRs are append-only: old records are never edited. Corrections or reversals
  require a new ADR that references the superseded one.
