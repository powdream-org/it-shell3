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

Each ADR contains exactly four sections.

```markdown
# NNNNN. Title

- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Deprecated | Superseded by NNNNN

## Context

What situation, problem, or forces motivated this decision?

## Decision

What specific choice was made?

## Consequences

What becomes easier or harder as a result?
```

### Status Values

| Status                  | Meaning                                        |
| ----------------------- | ---------------------------------------------- |
| **Proposed**            | Under discussion, not yet confirmed            |
| **Accepted**            | Confirmed and in effect                        |
| **Deprecated**          | No longer relevant or recommended              |
| **Superseded by NNNNN** | Replaced by a newer ADR (reference its number) |

When an ADR is superseded, update its Status to `Superseded by NNNNN` and write
the new ADR that replaces it.

---

## When to Write an ADR

Write an ADR when the owner makes a meaningful decision that future maintainers
would wonder about. Typical triggers:

- Technology or library selection (e.g., "why Zig instead of Rust?")
- Protocol design choices (e.g., "why binary header instead of JSON?")
- Architectural patterns (e.g., "why daemon + client instead of in-process?")
- Implementation strategy (e.g., "why native IME instead of OS IME?")
- Deliberate tradeoffs (e.g., "why native IME instead of OS IME?")

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

---

## Anti-Patterns

Common mistakes to avoid when writing ADRs.

### Section role confusion

| Wrong                                                                                | Right                                                |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| Decision lists cleanup tasks ("delete §4.2, remove §7.5 row")                        | Decision states the architectural choice only        |
| Consequences records which document sections were deleted                            | Consequences describes architectural impact          |
| Consequences explains why the decision was made (rationale)                          | Rationale belongs in Context                         |
| Consequences contains implementation specifics (hex codes, message sequencing steps) | Implementation specifics belong in the protocol spec |

### Decision section

- **Do not list documentation cleanup tasks.** "Remove §4.2 from the spec" is a
  consequence of a decision, not the decision itself. State the architectural
  policy: "We do not reserve X for speculative future use."
- **Do not describe wire format mechanics.** Specific message types, field
  initialization sequences, and update flows belong in the protocol spec, not in
  an ADR Decision.

### Consequences section

- **Do not record document edits.** "§4.2 and §7.5 are deleted" is a
  documentation task record, not an architectural consequence.
- **Do not repeat rationale.** If a point explains _why_ the decision was made,
  it belongs in Context. Consequences answers "what becomes easier or harder?"

### Content accuracy

- **Distinguish rationale (WHY) from spec facts (HOW).** Rationale belongs in
  the ADR; spec facts belong in whichever spec doc owns that concern (protocol
  spec, daemon spec, IME spec, etc.). When removing design rationale from a spec
  doc during cleanup, verify it lands in the ADR — do not discard it.
  - Example: `layout` (singular) vs `layouts` (plural) asymmetry — the _fact_
    that ClientHello uses singular stays in the spec; the _reason_ ("a client
    preference is one choice; a server capability is a set") goes in the ADR.
- **Cardinality and scope decisions are architectural.** "The client tracks one
  `active_input_method` per session" is a design decision (cardinality), not a
  spec mechanic. Keep it in the ADR Decision.

### Cross-references

- **Always include module and revision when citing a section number.** Bare
  `§4.2` is ambiguous (multiple modules have a Doc 02) and fragile (section
  numbers change on every revision). Use:
  ```
  §4.2 (server-client-protocols Doc 02, v1.0-r12)
  ```
  The revision anchors the reference so it remains interpretable after the
  document is renumbered.

### Extensions

- **Integrate additions, do not append.** When extending an existing ADR, new
  content must flow naturally within the existing narrative — same tone, same
  abstraction level. Read the whole ADR after editing to verify coherence.
