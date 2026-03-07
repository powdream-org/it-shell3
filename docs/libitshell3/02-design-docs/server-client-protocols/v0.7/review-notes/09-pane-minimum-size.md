# Pane Minimum Size

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 03 Open Question #2)
**Severity**: LOW
**Affected docs**: Doc 03 (Session/Pane Management)
**Status**: confirm-and-close

---

## Problem

The spec does not define the minimum pane size below which splits are rejected.

## Proposed Change

Minimum pane size: 2 columns x 1 row, matching tmux's minimum. `SplitPaneRequest` MUST return an error if the resulting pane dimensions would fall below this threshold.

## Owner Decision

Accepted. 2 columns x 1 row. tmux precedent.

## Resolution

{To be applied in v0.8 writing phase. Add normative statement to Doc 03.}
