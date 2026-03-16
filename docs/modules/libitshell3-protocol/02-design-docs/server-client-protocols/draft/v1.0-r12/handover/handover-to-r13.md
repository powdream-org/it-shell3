# Handover: Server-Client Protocols v1.0-r12 to v1.0-r13

- **Date**: 2026-03-16
- **Author**: owner

---

## Insights and New Perspectives

The v1.0-r12 owner review revealed that the protocol spec docs had accumulated
significant content that does not belong in wire protocol specifications:

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

A critical gap was discovered: daemon docs say "mouse events bypass IME
entirely" but the protocol had a normative rule that MouseButton commits
preedit. This contradiction is tracked in daemon CTR-04.

## Design Philosophy

**Protocol docs define wire format, not server behavior.** If a paragraph
describes what the server does internally (routing logic, processing priority,
IME state management), it belongs in daemon design docs or IME contract docs,
not in the protocol spec. The test: "Would a protocol-only implementor (someone
writing a compatible client without access to our server source) need this
information?" If no, it doesn't belong here.

**Single source of truth for each concept.** Readonly permissions live in Doc 03
§9 only. Header format lives in Doc 01 §3.1 only. JSON conventions live in Doc
01 §3.6 only. Other docs cross-reference, never duplicate.

**ADRs are the permanent record of design decisions.** Spec docs should not
contain "Rationale" blocks or "Design Decisions Needing Validation" tables. If a
decision is significant, write an ADR. If it's not significant, it doesn't need
a rationale paragraph.

## Owner Priorities

- Continue the cleanup for Doc 04 (from current §3 onward), Doc 05, and Doc 06
- Apply the same lens: remove daemon internals, remove duplication, move
  rationale to ADRs
- Doc 05 likely has substantial overlap with IME contract docs — verify before
  removing
- The mouse-preedit gap (CTR-04) must be resolved in the daemon docs

## New Conventions and Procedures

- **AGENTS.md**: Design Document Metadata convention added — only `Date` and
  `Scope` are allowed in spec doc headers. No Status, Version, Author, Depends
  on, or Changes from.
- **Version naming**: `v1.0-rN` format everywhere (not `v0.N`). Memory saved.
- **Metadata bullet format**: `- **Key**: value` instead of `**Key**: value` to
  survive deno fmt.

## Pre-Discussion Research Tasks

1. **Doc 05 overlap audit**: Before reviewing Doc 05, check how much content
   duplicates the IME interface contract docs. The preedit lifecycle,
   composition rules, and PreeditEnd reasons may already be authoritatively
   defined in IME docs.
2. **Doc 06 daemon overlap**: Check which parts of Doc 06 (flow control,
   coalescing, health escalation) are duplicated in daemon design docs after the
   v0.11 extraction. Some content may have been missed during that extraction.
