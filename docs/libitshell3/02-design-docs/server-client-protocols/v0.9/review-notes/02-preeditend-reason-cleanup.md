# PreeditEnd Reason Cleanup for InputMethodSwitch

**Date**: 2026-03-06
**Raised by**: verification team (V3-02) + owner design review
**Severity**: HIGH
**Affected docs**: Doc 05 (CJK Preedit Protocol) Sections 4.1, 7.9
**Status**: open

---

## Problem

Doc 05 §4.1 server behavior for `InputMethodSwitch` with `commit_current=false` lists two contradictory PreeditEnd reasons in the same code path:

- Step 2: `reason="cancelled"` (cancel current preedit)
- Step 3: `reason="input_method_changed"` (unconditional PreeditEnd)

These are two different reason values for the same operation. Additionally, §7.9 wire trace uses `reason=input_method_changed` for both `commit_current=true` and `commit_current=false` paths.

## Analysis

The `"input_method_changed"` reason was introduced to distinguish "preedit ended because the input method switched" from "preedit ended because the user cancelled." However, from the client's perspective, there is no behavioral difference — in both cases the preedit is dismissed and the client clears its preedit display. The distinction adds complexity without semantic value.

The `commit_current=false` path explicitly means "cancel the composition." Using `"cancelled"` is semantically accurate and consistent with the existing `"cancelled"` reason used elsewhere in the protocol.

## Proposed Change

1. **§4.1 server behavior**: Use `reason="cancelled"` for `commit_current=false`. Remove step 3's unconditional `reason="input_method_changed"`.
2. **§7.9 wire trace**: Update `commit_current=true` path to use `reason="committed"` (text was committed) and `commit_current=false` path to use `reason="cancelled"`.
3. **Remove `"input_method_changed"`** as a PreeditEnd reason constant entirely — it no longer exists in the protocol.

## Owner Decision

Use `"cancelled"` for `commit_current=false` path. The `"input_method_changed"` reason carries no distinct semantic from the client's perspective. Remove `"input_method_changed"` as a PreeditEnd reason constant entirely.

## Resolution

{To be resolved in v0.9.}
