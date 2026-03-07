# RendererHealth Report Interval

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #6)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

How frequently should `RendererHealth` reports be sent? The subscription system allows per-client configuration, but what should the minimum interval be?

## Proposed Change

Minimum interval: 1000 ms. Clients may request longer intervals via subscription. Server MUST NOT send more frequently than 1000 ms regardless of client request.

## Owner Decision

Accepted. 1000 ms floor.

## Resolution

{To be applied in v0.9 writing phase. Add normative minimum to Doc 06, close Q6.}
