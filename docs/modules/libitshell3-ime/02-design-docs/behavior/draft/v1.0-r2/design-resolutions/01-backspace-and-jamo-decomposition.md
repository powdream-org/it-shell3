# Design Resolutions: Backspace and Jamo Decomposition

**Date**: 2026-03-22 **Team**: ime-expert, principal-architect, sw-architect,
system-sw-engineer (4 members) **Scope**: R4-sem-1 fix (Backspace flush path
misclassification), CTR-01 (protocol team — Backspace role in Jamo
decomposition) **Execution order**: Resolution 1 (fix Step 2 note) -> Resolution
2 (add Section 2.3) -> Resolution 3 (add Section 6 in doc 10)

**Source materials**:

- R4-sem-1: `draft/v1.0-r1/review-notes/01-backspace-flush-path-grouping.md`
- CTR-01: `draft/v1.0-r1/cross-team-requests/01-protocol-jamo-decomposition.md`

---

## Resolution 1: R4-sem-1 Fix -- Partition Step 2 Note (4/4 unanimous)

**Source**: R4-sem-1 (verification Round 4, deferred from v1.0-r1) **Affected
docs**: `01-processkey-algorithm.md` Section 2.1 Step 2

### Decision

In the Step 2 note of `01-processkey-algorithm.md` Section 2.1, partition the
five HID keycodes in the `isPrintablePosition()` gap (0x28-0x2C) into two
groups:

1. **Flush/forward keys**: Enter (0x28), Escape (0x29), Tab (0x2B), Space (0x2C)
   -- routed to the flush/forward path per Step 2.
2. **Backspace (0x2A)**: Routed to the IME undo handler, NOT the flush/forward
   path. Cross-reference `03-modifier-flush-policy.md` Section 2.3.

The note's original purpose (warning against using `isPrintablePosition()` as
the printability gate) is preserved. The correction changes only the behavioral
claim about Backspace -- it is no longer grouped with the flush/forward keys.

The flowchart in Section 2 does not need to change. Backspace already bypasses
the `print_check` branch; the error was solely in the note's prose.

Add a forward reference to the new Section 2.3 (see Resolution 2) so readers are
pointed to the detailed Backspace documentation.

### Rationale

The v1.0-r1 Round 3 fix (R3-sem-1) correctly narrowed the printable range but
introduced a cascade: the note listed all five gap keycodes under a single
"flush/forward" label. This was correct for four of them but wrong for
Backspace. `03-modifier-flush-policy.md` Section 2 correctly classifies
Backspace as "IME handles" -- the Step 2 note must be consistent.

The composing-mode decision tree has three non-printable paths, not two:

1. Modifier keys (Ctrl/Alt/Cmd) -> flush + forward
2. Flush-trigger special keys (Enter, Escape, Tab, Space, Arrow keys) -> flush +
   forward
3. Backspace -> IME undo handler; forward only if composition empty

---

## Resolution 2: CTR-01 -- New Section 2.3 in `01-processkey-algorithm.md` (4/4 unanimous)

**Source**: CTR-01 (protocol team, from protocol v1.0-r12 Doc 04 Section 2.1)
**Affected docs**: `01-processkey-algorithm.md`

### Decision

Add a new subsection **2.3 "Backspace Handling in Composing Mode"** to
`01-processkey-algorithm.md`. The content must be **language-agnostic**
(matching the document's stated scope: "Language-agnostic `processKey()` general
decision tree").

Content of Section 2.3:

1. Backspace during active composition is delegated to the engine's undo
   handler, not flushed. This is the third non-printable path in the
   `processKey()` decision tree.
2. The undo handler returns true (key consumed -- read updated preedit from
   engine) or false (composition was already empty -- forward key to terminal).
3. ImeResult construction follows from the return value:
   - Consumed: `ImeResult` with updated `preedit_text`, `preedit_changed = true`
   - Not consumed: `ImeResult` with `forward_key = Backspace`
4. Cross-reference to `10-hangul-engine-internals.md` for language-specific
   decomposition mechanics (Korean jamo stack behavior).

**Editorial constraint**: The following MUST NOT appear in Section 2.3:

- Jamo decomposition order (jongseong -> jungseong -> choseong)
- Double-tail consonant handling
- `hangul_ic_backspace()` or any libhangul API name
- Any Korean-specific detail

All Korean-specific content belongs in `10-hangul-engine-internals.md` (see
Resolution 3).

### Rationale

The three-path model (modifier flush, special-key flush, Backspace undo) is a
property of the `processKey()` algorithm, not of any particular language. Any
composition engine (Korean, Japanese, Chinese) would have the same three paths.
A subsection (rather than an inline callout) makes this third path discoverable
from the table of contents -- important given that R4-sem-1 arose precisely
because Backspace was invisible as a distinct path.

The section structure 2.1 (composing mode steps), 2.2 (flush semantics), 2.3
(Backspace handling) makes the three-path model visible in the document
structure.

---

## Resolution 3: CTR-01 -- New Section 6 in `10-hangul-engine-internals.md` (4/4 unanimous)

**Source**: CTR-01 (protocol team, from protocol v1.0-r12 Doc 04 Section 2.1)
**Affected docs**: `10-hangul-engine-internals.md`

### Decision

Add a new **Section 6 "Backspace and Jamo Decomposition"** to
`10-hangul-engine-internals.md`, after the existing Section 5 (processKeyImpl
Note). The current Section 6 (Session Persistence) is renumbered to Section 7.

Content of Section 6:

1. **`hangul_ic_backspace()` return value semantics**: Call
   `hangul_ic_backspace()` directly and use its return value as the dispatch
   signal. Returns `true` if a jamo was popped (key consumed), `false` if
   composition was already empty (forward key to terminal). No pre-check with
   `hangul_ic_is_empty()` -- the return value is sufficient.

2. **Jamo stack pop order**: libhangul's `HangulBuffer` maintains jamo positions
   (choseong, jungseong, jongseong) with length counters.
   `hangul_ic_backspace()` decrements the most recently filled position in
   reverse input order: jongseong (tail consonant) -> jungseong (vowel) ->
   choseong (leading consonant). This is a literal stack pop, not reconstruction
   from the composed syllable code point.

3. **Double-tail consonant decomposition**: Double-tail consonants (e.g., ㅂㅅ
   in "없") are stored as two jongseong entries. Backspace removes the second
   component first (e.g., "없" -> "업" removes ㅅ, leaving ㅂ). Mention this
   exists without over-specifying libhangul internals.

4. **ImeResult patterns**: Document the two cases:
   - `hangul_ic_backspace()` returns `true`: read updated preedit from
     `hangul_ic_get_preedit_string()`, return `ImeResult` with modified preedit,
     `preedit_changed = true`, no `forward_key`, no `committed_text`.
   - `hangul_ic_backspace()` returns `false`: composition was empty, return
     `ImeResult` with `forward_key = Backspace`, no `committed_text`, no
     `preedit_text`.

5. **Concrete example**: Include a step-by-step decomposition sequence (e.g.,
   "한" -> Backspace -> "하" -> Backspace -> "ㅎ" -> Backspace -> empty -> next
   Backspace forwarded to terminal).

### Rationale

This content was previously an inline note in the protocol spec (Doc 04 Section
2.1, marking Backspace as "Critical for Jamo decomposition"). The protocol team
removed it as a non-wire-protocol concern and filed CTR-01 to ensure the
knowledge is preserved in the IME behavior docs.

Placement as Section 6 (after the processKeyImpl Note in Section 5) groups
Backspace handling with other processKeyImpl-related content. Session
Persistence (current Section 6, now Section 7) is independent of Backspace
handling -- no logical ordering requirement between them.

The return-value dispatch approach (call `hangul_ic_backspace()` directly, check
return) is preferred over pre-checking `hangul_ic_is_empty()` because it is
simpler, avoids a redundant call, and does not imply that calling
`hangul_ic_backspace()` on an empty context is unsafe (it is safe -- it returns
`false` and does nothing).
