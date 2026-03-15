---
name: adr
description: Research and write a new Architecture Decision Record
argument-hint: <topic>
tools: [Bash, Glob, Grep, Read, Write, Edit]
---

# Architecture Decision Record

Write an ADR for: **$ARGUMENTS**

If `$ARGUMENTS` is empty, print the following and stop:

```
Usage: /adr <topic>
Example: /adr native IME over OS IME
```

## Step 1: Research the Decision

Read relevant project documentation to fully understand the decision, its
motivation, and its consequences. Start from the most likely sources and broaden
as needed:

- `AGENTS.md` — project overview, key design decisions summary
- `docs/insights/design-principles.md` — validated design principles
- `docs/insights/reference-codebase-learnings.md` — reference patterns
- Design docs under `docs/modules/` relevant to the topic
- Handover docs and design-resolutions under `draft/` dirs — these often contain
  the most concentrated rationale

The `<topic>` is a loose hint. Interpret broadly and search for the full context
of the decision.

## Step 2: Compute the Next ADR Number

```bash
ls docs/adr/*.md 2>/dev/null | sort
```

Extract the highest 5-digit prefix found. Next number = highest + 1. If no ADRs
exist, start at `00001`. Format as zero-padded 5 digits.

## Step 3: Get Today's Date

```bash
date +%Y-%m-%d
```

## Step 4: Draft the Full ADR

From your research, compose:

- **Title** — concise and specific (not just the topic hint). Phrase as a noun
  phrase describing the decision, e.g. "Native IME Engine over OS IME".
- **Context** — the situation, problem, or forces that made this decision
  necessary. Include relevant constraints and alternatives considered.
- **Decision** — the specific, unambiguous choice made.
- **Consequences** — concrete outcomes: what gets easier, what gets harder, what
  new obligations or risks arise.

## Step 5: Compute the Filename Slug

Derive the slug from the **drafted title** (not the topic hint):

- Lowercase
- Replace spaces and non-alphanumeric characters with `-`
- Collapse repeated `-` into one
- Strip leading/trailing `-`

Example: `"Native IME Engine over OS IME"` → `native-ime-engine-over-os-ime`

## Step 6: Copy the Template

```bash
cp docs/conventions/artifacts/documents/11-adr_template.md \
   docs/adr/NNNNN-<slug>.md
```

(Replace `NNNNN` with the zero-padded number and `<slug>` with the slug from
Step 5.)

## Step 7: Fill In the File

Use the Edit tool to replace the placeholders in the copied file:

- `NNNNN` → zero-padded number
- `Title` → drafted title
- `YYYY-MM-DD` → today's date
- Empty `## Context`, `## Decision`, `## Consequences` sections → drafted
  content

## Step 8: Report

Show the user the created file path and the full content of the new ADR.
