# Hyperlink CellData Encoding

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 04 Open Question #4)
**Severity**: MEDIUM
**Affected docs**: Doc 04 (Input and RenderState)
**Status**: open

---

## Problem

OSC 8 hyperlinks are not encoded in CellData. Terminal programs (gcc, systemd, GNU coreutils, etc.) emit OSC 8 sequences to create clickable links. ghostty supports OSC 8 rendering. The current 20-byte fixed-size CellData has no field for hyperlink information, and URI strings are variable-length (tens to hundreds of bytes) — they cannot be inlined per cell.

## Context

ghostty internally manages hyperlinks via ID-based lookup. Multiple cells sharing the same link reference the same hyperlink ID.

## Possible Approaches

1. **Hyperlink table**: Add a `{hyperlink_id -> uri}` table to FrameUpdate. Add a `hyperlink_id` field (2 bytes) to CellData (20B -> 22B).
2. **JSON metadata**: Include hyperlink mappings in the FrameUpdate JSON metadata blob. CellData gains only an ID reference.

Open discussion — no pre-selected direction.

## Owner Decision

Open discussion in v0.8.

## Resolution

{To be resolved in v0.8.}
