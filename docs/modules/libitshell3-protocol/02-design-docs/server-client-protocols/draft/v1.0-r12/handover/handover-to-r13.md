# Handover: Server-Client Protocols v1.0-r12 to v1.0-r13

- **Date**: 2026-03-22
- **Author**: owner

---

## Insights and New Perspectives

The v1.0-r12 owner review (completed 2026-03-22) cleaned all 6 protocol docs.
The cleanup revealed several recurring patterns worth naming:

- **Design rationale** (why a decision was made) was embedded inline instead of
  living in ADRs. The "Design Decisions Needing Validation" tables in Doc 01 and
  Doc 02 mixed already-decided items with genuinely proposed items, creating
  false urgency.
- **Daemon implementation details** (how the server processes input, routes
  KeyEvents, handles resize, manages preedit during mouse events) had leaked
  into protocol docs. The protocol should define _what goes on the wire_, not
  _how the server internally handles it_.
- **Cross-doc duplication** (header format, JSON conventions, readonly
  permissions, cursor blink rules) was widespread. Each copy diverges over time.
  The fix is single-source-of-truth with cross-references.
- **CJK capability flags** were an entire negotiation subsystem for features
  that are always supported and never negotiable. The server always has native
  IME, always supports preedit, always handles jamo decomposition. Removing
  these simplified Doc 02 substantially.
- **Summary/aggregation sections** that restate what individual message
  definitions already say create divergence risk. Doc 03 §8 (Multi-Client
  Behavior) was a pure restatement of per-message behavior visible in each
  message's own section. It had already drifted from the originals. The entire
  section was deleted; individual message definitions remain the authoritative
  record.

A critical gap was discovered: daemon docs say "mouse events bypass IME
entirely" but the protocol had a normative rule that MouseButton commits
preedit. This contradiction is tracked in daemon CTR-04 (daemon team's
responsibility to resolve).

## Design Philosophy

**Protocol docs define wire format, not server behavior.** If a paragraph
describes what the server does internally (routing logic, processing priority,
IME state management), it belongs in daemon design docs or IME contract docs,
not in the protocol spec. The test: "Would a protocol-only implementor (someone
writing a compatible client without access to our server source) need this
information?" If no, it doesn't belong here.

**Single source of truth for each concept.** Readonly permissions live in Doc 03
§8 (Readonly Client Permissions) only. Header format lives in Doc 01 §3.1 only.
JSON conventions live in Doc 01 §3.6 only. Other docs cross-reference, never
duplicate.

**ADRs are the permanent record of design decisions.** Spec docs should not
contain "Rationale" blocks or "Design Decisions Needing Validation" tables. If a
decision is significant, write an ADR. If it's not significant, it doesn't need
a rationale paragraph.

**Individual message definitions are authoritative; do not add summary
sections.** A "multi-client behavior" or "error handling overview" section that
aggregates behavior across messages will drift from the originals. Delete it
when found; add cross-references to individual definitions instead.

## Owner Priorities

The r12 owner review cleanup is fully complete (all 6 docs, ~125 items). The
main open items for r13:

- **Section renumbering pass**: Doc 01 had §8 and §11 deleted — sections now
  number 1–7, 9, 10, 12. Doc 05 has a §5.1 deletion gap (§5.2 remains alone) and
  a §12 deletion gap (§11→§13). Apply sequential renumbering with a cross-doc
  grep for stale references before committing.
- **Deferred protocol items**: S4-02 (AttachOrCreateRequest merge, ADR 00003)
  and S4-03 (ClipboardWrite encoding symmetry, ADR 00004) were deferred from
  Round 4 verification. Pick up when ready.
- **ADR numbering discipline**: When ADRs are cancelled, fill gaps from higher-
  numbered ADRs (as done for 00027-00029). Do not leave numbered gaps.

## New Conventions and Procedures

Established in r12 owner review cleanup:

- **AGENTS.md**: Design Document Metadata convention — only `Date` and `Scope`
  are allowed in spec doc headers. No Status, Version, Author, Depends on, or
  Changes from.
- **Version naming**: `v1.0-rN` format everywhere (not `v0.N`).
- **Metadata bullet format**: `- **Key**: value` instead of `**Key**: value` to
  survive deno fmt.
- **Notification-only CTRs**: A CTR that only notifies a target team of a
  section renumbering (no protocol text was removed) requires no "Reference:
  Original Protocol Text" section. Established by CTR-20 (consistent with CTR-10
  precedent).
- **ADR gap filling**: When ADRs are cancelled, renumber later ADRs to fill the
  gaps. Update all cross-references in the same commit.

## Pre-Discussion Research Tasks

1. **Section renumbering audit**: Before r13 editing begins, grep all 6 docs
   plus ADRs, CTRs, and insights files for section references (e.g., `§8`,
   `§11`, `§5.1`) that will be affected by the Doc 01 and Doc 05 renumbering.
   Map old numbers to new numbers before touching any file.
