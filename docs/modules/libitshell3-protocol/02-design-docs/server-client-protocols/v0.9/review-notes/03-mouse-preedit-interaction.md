# Mouse Event and Preedit Interaction

**Date**: 2026-03-07
**Raised by**: owner
**Severity**: MEDIUM
**Affected docs**: Doc 05 (CJK Preedit Protocol) Section 7, Doc 04 (Input and RenderState) Section 2
**Status**: open

---

## Problem

Doc 05 Section 7 (Preedit Lifecycle) does not specify how mouse events interact with active preedit. ghostty's core surface does NOT auto-flush preedit on mouse events — the embedder (daemon) is fully responsible for calling `preeditCallback(null)` to clear preedit when appropriate.

Two mouse event types require different treatment:

- **MouseButton (0x0202)**: A click changes the cursor position and editing context. Preedit must be committed before the click is processed.
- **MouseScroll (0x0204)**: Scroll only moves the viewport. The editing context (cursor position, active pane) is unchanged. Preedit must NOT be committed.

Viewport restoration after scroll is handled automatically by libghostty's `scroll-to-bottom` default behavior (`keystroke=true`) — when the user types after scrolling, the viewport returns to the bottom. No daemon logic or protocol support needed.

## Proposed Changes

### 1. Add normative rules to Doc 05 Section 7 (Preedit Lifecycle)

Add a subsection for mouse event interaction:

> **Mouse events during active preedit:**
>
> - When the server receives a **MouseButton** (0x0202) event while preedit is active, the server **MUST** commit the current preedit by calling `preeditCallback(null)` before forwarding the mouse event to libghostty.
> - When the server receives a **MouseScroll** (0x0204) event while preedit is active, the server **MUST NOT** commit preedit. Scroll is a viewport-only operation and does not change the editing context.

### 2. Add cross-reference note to Doc 04 Section 2 (Mouse Input Messages)

Add a normative note after the MouseButton (0x0202) message definition:

> **Preedit interaction**: If preedit is active when a MouseButton event arrives, the server MUST commit preedit before processing the mouse event. See Doc 05 Section 7.

### 3. No protocol changes needed for viewport restoration

libghostty's `scroll-to-bottom` config (default: `keystroke=true, output=false`) automatically scrolls the viewport to bottom on keystroke. This is an implementation detail of the terminal engine, not a protocol concern. Do not add protocol messages or fields for this behavior.

## Owner Decision

Owner confirmed: MouseButton commits preedit, MouseScroll does not. Viewport restoration is libghostty's responsibility.

## Resolution

{Pending -- to be applied in the next revision.}
