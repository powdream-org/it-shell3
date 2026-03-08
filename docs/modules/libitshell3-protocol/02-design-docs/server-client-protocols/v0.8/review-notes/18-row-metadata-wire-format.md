# Row Metadata Missing from Wire Format (wrap, semantic_prompt)

**Date**: 2026-03-08
**Raised by**: owner (based on PoC 08 + ghostty renderer source analysis)
**Severity**: MEDIUM
**Affected docs**: 04-input-and-renderstate.md (Section 4.3 DirtyRows)
**Status**: open

---

## Problem

The RowData wire format (doc 04 §4.3) carries `y`, `selection_flags`, `selection_start`, `selection_end`, and `num_cells`. It does NOT carry ghostty's `page.Row` metadata:

- **`semantic_prompt`**: Values `none`, `prompt`, `prompt_continuation`. Used by `renderer/row.zig:neverExtendBg()` to prevent background color extension on prompt lines (important for Powerline-style prompts).
- **`wrap`**: Whether the row wraps to the next line. Used for copy/paste semantics and text reflow.

### Evidence from ghostty source

`src/renderer/row.zig:neverExtendBg()`:
```zig
switch (row.semantic_prompt) {
    .prompt, .prompt_continuation => return true,
    .none => {},
}
```

When `semantic_prompt` is `.prompt`, the renderer prevents padding background extension. Without this flag on the wire, the client's `rebuildCells()` will use the default `semantic_prompt = .none`, potentially extending background color into padding where it should not be extended.

### Visual impact

Terminals with Powerline prompts or custom PS1 with background colors will render incorrectly: the prompt's background color will bleed into the right padding, creating a visible rendering artifact.

## Analysis

### RowData size impact

Adding row metadata requires 1-2 bytes per row:

| Approach | Additional bytes per row | Total for 80×24 I-frame |
|----------|------------------------|-----------------------|
| 1 byte packed (semantic_prompt 2 bits + wrap 1 bit) | 1 | 24 bytes |
| 2 bytes (1 for semantic_prompt, 1 for wrap + future flags) | 2 | 48 bytes |

This is negligible compared to the cell data (~1,600 bytes per row).

### Fields to consider

| Field | Bits needed | Rendering impact | Priority |
|-------|-------------|------------------|----------|
| `semantic_prompt` | 2 bits | Background extension (visual correctness) | HIGH |
| `wrap` | 1 bit | Copy/paste, text reflow | MEDIUM |
| `dirty` (row-level) | 1 bit | Already implicit in DirtyRows membership | N/A |

## Proposed Change

Add a `row_flags` byte to RowData header:

```
RowData (revised):
Offset  Size  Field               Description
------  ----  -----               -----------
 0       2    y                    Row index (u16 LE)
 1       1    row_flags            Bit 0: has_selection
                                   Bit 1: rle_encoded
                                   Bit 2: wrap (row wraps to next line)
                                   Bits 3-4: semantic_prompt (0=none, 1=prompt, 2=prompt_continuation)
                                   Bits 5-7: reserved
 3       2    selection_start      Start column (present if bit 0)
 5       2    selection_end        End column (present if bit 0)
 ?       2    num_cells            Number of cell entries (u16 LE)
```

This merges the existing `selection_flags` byte with the new row metadata into a single `row_flags` byte. No additional bytes needed — just repurpose reserved bits in the existing byte.

## Owner Decision

{Pending}

## Resolution

{Pending}
