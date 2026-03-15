# Architecture Decision Records (ADR)

An Architecture Decision Record (ADR) is a short document that captures a
significant design or implementation decision — the context that led to it, the
choice made, and its consequences.

---

## Purpose

ADRs answer the question "why did we build it this way?" for decisions that
future maintainers (or future you) would otherwise have to reverse-engineer from
the code or docs.

---

## Location

All ADRs live in `docs/adr/`:

```
docs/adr/
├── 00001-native-ime-over-os-ime.md
├── 00002-binary-wire-format.md
└── ...
```

---

## Naming

```
NNNNN-<slug>.md
```

- `NNNNN` — 5-digit zero-padded sequential number (`00001`, `00002`, …)
- `<slug>` — kebab-case summary of the title (lowercase, spaces → `-`)

Example: `00003-rendertstate-instead-of-vt-reserialization.md`

---

## Format

Each ADR contains exactly three sections. No Status section.

```markdown
# NNNNN. Title

Date: YYYY-MM-DD

## Context

What situation, problem, or forces motivated this decision?

## Decision

What specific choice was made?

## Consequences

What becomes easier or harder as a result?
```

---

## When to Write an ADR

Write an ADR when the owner makes a meaningful decision that future maintainers
would wonder about. Typical triggers:

- Technology or library selection (e.g., "why Zig instead of Rust?")
- Protocol design choices (e.g., "why binary header instead of JSON?")
- Architectural patterns (e.g., "why daemon + client instead of in-process?")
- Implementation strategy (e.g., "why native IME instead of OS IME?")
- Deliberate tradeoffs (e.g., "why no Status section in ADRs?")

When in doubt, write one. ADRs are cheap; archaeological digs are not.

---

## How to Create

Use the `/adr <topic>` skill. The agent reads relevant project docs, drafts the
full ADR (title, Context, Decision, Consequences), and writes the file with the
correct number and date. No manual editing required.

```
/adr native IME over OS IME
/adr binary wire format for protocol
```

The template used is `11-adr_template.md` in this directory.
