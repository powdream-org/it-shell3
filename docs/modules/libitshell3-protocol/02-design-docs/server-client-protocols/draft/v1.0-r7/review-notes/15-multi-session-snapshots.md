# Multi-Session Snapshots

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #4)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

Should one snapshot file contain multiple sessions, or one file per session?

## Proposed Change

Per-session snapshot files with a manifest. The manifest lists all sessions and their snapshot file paths. This enables partial restore (restore a single session without loading the entire state).

## Owner Decision

Accepted. Per-session files + manifest. More flexible than cmux's single-file approach.

## Resolution

{To be applied in v0.8 writing phase. Define snapshot file structure in Doc 06, close Q4.}
