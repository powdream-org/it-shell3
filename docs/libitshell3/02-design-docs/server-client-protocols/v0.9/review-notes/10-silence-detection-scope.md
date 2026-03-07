# Silence Detection Scope

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #8)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

Should `SilenceDetected` fire for any pane that has been silent, or only for panes with recent activity (activity-then-silence pattern)?

## Proposed Change

Activity-then-silence pattern only. `SilenceDetected` fires only after at least one byte of output has been seen since the last silence notification. This matches the primary use case: build completion notification.

## Owner Decision

Accepted. Activity-then-silence.

## Resolution

{To be applied in v0.9 writing phase. Add normative statement to Doc 06, close Q8.}
