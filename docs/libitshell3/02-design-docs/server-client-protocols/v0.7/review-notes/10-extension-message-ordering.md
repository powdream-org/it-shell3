# Extension Message Ordering

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #7)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

Whether extension messages should be ordered with respect to core messages, or can be interleaved.

## Proposed Change

All messages on a connection are strictly ordered. Extensions cannot bypass this. No out-of-order delivery.

## Owner Decision

Accepted. Strict ordering. The question already contained the answer.

## Resolution

{To be applied in v0.8 writing phase. Add normative statement to Doc 06, close Q7.}
