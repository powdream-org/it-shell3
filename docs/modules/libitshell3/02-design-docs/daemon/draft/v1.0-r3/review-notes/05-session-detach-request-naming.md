# SessionDetachRequest vs DetachSessionRequest Naming

**Date**: 2026-03-10
**Raised by**: verification team
**Severity**: CRITICAL
**Affected docs**: daemon v0.3 docs, protocol v0.11 doc 03
**Status**: open

---

## Problem

Daemon docs use "SessionDetachRequest" while protocol docs define "DetachSessionRequest (0x0106)". The naming is inconsistent across module boundaries.

## Analysis

This predates v0.3 — daemon docs have used "SessionDetachRequest" since v0.1. The protocol docs are the normative source for message type names. This inconsistency could cause confusion during implementation.

## Proposed Change

Align daemon docs to match protocol docs: rename all "SessionDetachRequest" occurrences to "DetachSessionRequest".

## Owner Decision

Left to designers for resolution.

## Resolution

