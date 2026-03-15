# 00002. Status Field in Architecture Decision Records

- Date: 2026-03-15
- Status: Accepted

## Context

ADR 00001 adopted npryce/adr-tools-style records with three sections (Context,
Decision, Consequences) and explicitly omitted a Status field, reasoning that
supersession could be handled by writing a new ADR referencing the old one.

In practice, having no Status means there is no way to tell at a glance whether
an ADR is still in effect, under discussion, deprecated, or replaced. A reader
must search for newer ADRs that might supersede a given record — a linear scan
that scales poorly as the ADR count grows. It also means there is no distinction
between a decision that has been confirmed and one that is merely proposed.

The npryce/adr-tools convention itself includes a Status field with values like
Proposed, Accepted, Deprecated, and Superseded. Omitting it was a deviation from
the convention that removed useful information without a clear benefit.

## Decision

Add a Status field to every ADR, displayed as a list item alongside Date:

```markdown
- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Deprecated | Superseded by NNNNN
```

The four status values are:

- **Proposed** — under discussion, not yet confirmed. This is the default for
  newly created ADRs.
- **Accepted** — confirmed and in effect.
- **Deprecated** — no longer relevant or recommended.
- **Superseded by NNNNN** — replaced by a newer ADR (reference its number).

When an ADR is superseded, its Status is updated to `Superseded by NNNNN` in
place (the only permitted mutation to an existing ADR). The ADR template
(`11-adr_template.md`) defaults new records to `Proposed`.

## Consequences

- Readers can immediately see whether an ADR is current without searching for
  superseding records.
- The `Proposed` → `Accepted` distinction enables using ADRs for decisions still
  under discussion, broadening their utility.
- ADRs are no longer fully append-only: the Status line of an existing ADR may
  be updated when it is superseded or deprecated. This is a controlled exception
  — only the Status field changes, never the body.
- The `/adr` skill creates new ADRs with `Status: Proposed` by default. The
  owner must explicitly set `Accepted` when the decision is confirmed.
