# Snapshot Format Versioning

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #2)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

How to handle snapshot format evolution across server versions.

## Proposed Change

Include a format version number in the JSON snapshot. Newer servers can read older formats (backward compatible) but not vice versa. Forward compatibility is not guaranteed.

## Owner Decision

Accepted. Standard versioning practice.

## Resolution

{To be applied in v0.8 writing phase. Add format version field to snapshot schema in Doc 06, close Q2.}
