# Clipboard Size Limit

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #1)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

Should there be a maximum clipboard data size? Large clipboard contents (e.g., megabytes of text) could cause issues.

## Proposed Change

Maximum clipboard payload: 10 MB. Contents exceeding this limit use chunked transfer. Server MUST reject single clipboard messages exceeding the protocol's 16 MiB max payload.

## Owner Decision

Accepted. 10 MB + chunked.

## Resolution

{To be applied in v0.8 writing phase. Add normative limit to Doc 06 clipboard section, close Q1.}
