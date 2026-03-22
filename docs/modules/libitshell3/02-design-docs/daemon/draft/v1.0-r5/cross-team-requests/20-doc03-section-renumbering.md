# Doc 03 Section Renumbering: §9 becomes §8

- **Date**: 2026-03-22
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During the v1.0-r12 owner review cleanup, protocol doc 03 (Session and Pane
Management) Section 8 "Multi-Client Behavior" is being deleted entirely. Its
content is either duplicate of individual message definitions (already in
Sections 1-4) or covered by doc 06 (Flow Control and Auxiliary). As a result,
the current Section 9 "Readonly Client Permissions" is renumbered to Section 8.

The daemon lifecycle doc (`03-lifecycle-and-connections.md`, line 583) contains
a cross-reference to `protocol doc 03 Section 9`. This reference must be updated
to reflect the renumbering.

## Required Changes

1. In `03-lifecycle-and-connections.md`, line 583, update the cross-reference
   from `per protocol doc 03 Section 9` to `per protocol doc 03 Section 8`.

## Summary Table

| Target Doc                   | Section/Line | Change Type | Source Resolution               |
| ---------------------------- | ------------ | ----------- | ------------------------------- |
| 03-lifecycle-and-connections | Line 583     | Fix ref     | owner review (v1.0-r12 cleanup) |
