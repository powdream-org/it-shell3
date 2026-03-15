# Pane Minimum Size

- **Date**: 2026-03-16
- **Raised by**: owner
- **Severity**: LOW
- **Affected docs**: Doc 03 (session/pane management, Open Question #2)
- **Status**: resolved in draft/v1.0-r12

---

## Problem

Doc 03 Open Question #2 asked: "What is the minimum pane size below which splits
are rejected?" No value was defined.

## Analysis

tmux uses 2 columns x 1 row as its minimum. Note: Doc 04 §4.1 defines a separate
but related threshold — the server suppresses FrameUpdate for panes with
`cols < 2` or `rows < 1` (rendering suppression for already-existing panes that
become too small via resize). The split rejection threshold defined here
prevents creating panes below that size in the first place. Using the same value
(2x1) for both ensures no pane can be created that is immediately
unsuppressed-but-unrenderable.

## Proposed Change

Define pane minimum size as 2 columns x 1 row. Close Open Question #2.

## Owner Decision

Accepted. See ADR 00017.

## Resolution

ADR 00017 created. Open Questions section removed from Doc 03 (no remaining open
items).
