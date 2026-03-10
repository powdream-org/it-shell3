# AGENTS.md Line 18 "tab" Reference

**Date**: 2026-03-10
**Raised by**: verification team
**Severity**: LOW
**Affected docs**: AGENTS.md
**Status**: resolved in v0.3

---

## Problem

AGENTS.md line 18 says "session/tab/pane state" in the libitshell3 description. All current design docs establish no Tab entity — hierarchy is Session > Pane. The line 51 instance was fixed in v0.3 (V1-04), but line 18 was identified as pre-existing and deferred.

## Analysis

Cosmetic inconsistency. Line 18 is a high-level feature description that predates the Tab removal decision. Low impact since the normative hierarchy definition (line 51) is already correct.

## Proposed Change

Change "session/tab/pane state" to "session/pane state" on line 18.

## Owner Decision

Left to designers for resolution.

## Resolution

Fixed in v0.3: changed "session/tab/pane state" to "session/pane state" on AGENTS.md line 18.
