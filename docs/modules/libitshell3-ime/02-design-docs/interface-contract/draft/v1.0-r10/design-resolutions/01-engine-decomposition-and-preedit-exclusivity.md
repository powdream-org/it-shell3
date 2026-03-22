# Design Resolutions: Engine Decomposition and Preedit Exclusivity

**Date**: 2026-03-22 **Team**: ime-expert, principal-architect, sw-architect,
system-sw-engineer (4 members) **Scope**: CTR-01 (protocol team -- engine
decomposition responsibility boundary and preedit exclusivity invariant)
**Execution order**: Resolution 1 (decomposition boundary in Section 2) ->
Resolution 2 (new Section 3 for preedit exclusivity) -> Resolution 3 (registry
location)

**Source materials**:

- CTR-01:
  `draft/v1.0-r9/cross-team-requests/01-protocol-engine-decomposition.md`

---

## Resolution 1: Decomposition Responsibility -- Add to Existing Section 2 (4/4 unanimous)

**Source**: CTR-01 item 1 (protocol team, from protocol v1.0-r12 Doc 04 Section
2.1) **Affected docs**: `03-engine-interface.md` Section 2 (setActiveInputMethod
Behavior)

### Decision

Add a paragraph at the end of the existing Section 2 ("setActiveInputMethod
Behavior") in `03-engine-interface.md` documenting the `input_method` string
decomposition boundary. The paragraph states:

1. The `input_method` string flows unchanged from client to server to the
   engine.
2. Only the engine constructor (`init()`) and `setActiveInputMethod()` decompose
   the `input_method` string into engine-specific types (e.g., libhangul
   keyboard IDs).
3. No code outside the engine examines or transforms the `input_method` string
   for engine routing purposes.
4. The canonical registry of valid `input_method` strings is defined in the
   behavior docs (see the Canonical Input Method Registry in
   `10-hangul-engine-internals.md`).

No new section is created. No renumbering.

### Rationale

Three placement options were considered:

- **(A)** New Section 2 "Engine Constructor" (renumbers Section 2 -> 3, Section
  3 -> 4): Rejected. Renumbering creates churn and cross-reference updates. The
  constructor is not a vtable method -- giving it a top-level section in the
  interface contract is disproportionate.
- **(B)** Add paragraph to existing Section 2 (setActiveInputMethod):
  **Chosen.** Both `init()` and `setActiveInputMethod()` decompose the
  `input_method` string. Section 2 already discusses `input_method` string
  semantics extensively (Cases 1-3, string parameter ownership). The
  decomposition boundary is a natural addition to this section.
- **(C)** Subsection 1.1 under the vtable section: Rejected. Section 1 is the
  vtable definition (code block + summary table). Adding constructor semantics
  there mixes vtable shape with instantiation semantics.

A standalone Engine Instantiation section was also considered and rejected: it
would either duplicate `10-hangul-engine-internals.md` Section 1 (which already
documents the `HangulImeEngine` constructor) or be too thin to justify its own
heading. The CTR-01 requirement is fully satisfied by the decomposition boundary
paragraph in Section 2.

### Additional Impact

**1.1 Vtable-to-setActiveInputMethod reading flow preserved (4/4 unanimous)**

The existing Section 1 (ImeEngine vtable) -> Section 2 (setActiveInputMethod
behavior) reading flow is preserved. A reader encountering the vtable
immediately sees the most complex method's behavior documented next. Inserting a
section between them would break this flow.

---

## Resolution 2: Preedit Exclusivity -- New Standalone Section 3 (4/4 unanimous)

**Source**: CTR-01 item 2 (protocol team, from protocol v1.0-r12 Doc 05 Section
1.1) **Affected docs**: `03-engine-interface.md`

### Decision

Add a new **Section 3 "Per-Session Engine Architecture"** to
`03-engine-interface.md`, before MockImeEngine (which is renumbered from current
Section 3 to Section 4).

The resulting document structure:

1. ImeEngine (Interface for Dependency Injection) -- existing, unchanged
2. setActiveInputMethod Behavior -- existing + decomposition boundary paragraph
   (Resolution 1)
3. **Per-Session Engine Architecture** -- new
4. MockImeEngine (For Testing) -- existing, renumbered from current Section 3

Content of Section 3:

1. Each session has one engine instance, shared across all panes in that
   session.
2. The engine has a single composition context. At most one pane per session can
   have active preedit at any time.
3. This is a structural property of the single-engine-per-session architecture
   -- a consequence of the engine having one composition context (e.g., one
   `HangulInputContext` with one jamo stack), not something the engine actively
   enforces.
4. Clients MAY rely on this invariant for rendering optimization: when a preedit
   starts on one pane, any active preedit on another pane within the same
   session has already been cleared.

**Editorial constraints**:

- Frame the invariant from the engine's perspective ("the engine has a single
  composition context"), NOT as a daemon obligation.
- Do NOT prescribe daemon behavior (e.g., "the daemon MUST call deactivate
  before switching panes"). Daemon enforcement rules belong in daemon design
  docs.
- The wording should use "a consequence of" (not "enforced by" or "naturally
  enforced by"). The invariant is a structural property, not something the
  engine actively polices.
- The engine is pane-agnostic (documented in the behavior docs,
  `01-processkey-algorithm.md` Section 4: "No pane/session awareness"). The
  invariant exists because of the architecture, not because the engine knows
  about panes.
- Keep the section brief (4-5 sentences). Daemon enforcement details
  (flush-on-focus-change, lock ordering, deactivate semantics) are
  cross-referenced to daemon design docs.

### Rationale

The preedit exclusivity invariant was previously documented in the protocol spec
(Doc 05 Section 1.1). The protocol team removed it as an IME architecture
concern and filed CTR-01 to ensure the interface contract owns it.

A standalone section (rather than a vtable comment near `activate`/`deactivate`)
is warranted because:

- The invariant is not about `activate`/`deactivate` specifically -- it is a
  structural property that would hold even if those methods did not exist (there
  is still only one composition context).
- It is architecturally significant: clients can rely on it for rendering
  optimization.
- The system-sw-engineer framing applies: this is a "usage contract" analogous
  to documenting that a type is not thread-safe. The engine does not enforce it,
  but callers must understand the constraint.

Placement before MockImeEngine (rather than between vtable and
setActiveInputMethod) preserves the Section 1 -> 2 reading flow.

---

## Resolution 3: Registry Canonical Location Stays in Behavior Docs (4/4 unanimous)

**Source**: Raised during discussion (cross-document consistency question)
**Affected docs**: `03-engine-interface.md` Section 2 (reference text only)

### Decision

The canonical `input_method` registry (the table of all valid input method
strings and their libhangul keyboard ID mappings) stays in
`10-hangul-engine-internals.md` Section 2.1 (Canonical Input Method Registry).
The interface contract cross-references it without duplicating the table.

The decomposition boundary paragraph added in Resolution 1 references the
registry as: "see the Canonical Input Method Registry in
`10-hangul-engine-internals.md`" -- the same pattern already used in
`03-engine-interface.md` Case 3.

No `input_method` string list is added to the interface contract.

### Rationale

Three factors support keeping the registry in the behavior docs:

1. **DRY**: Maintaining a "valid strings" list in the interface contract AND the
   full table with libhangul keyboard IDs in the behavior docs creates two lists
   that can diverge. This is the exact bug class eliminated when the mapping
   table was moved out of the protocol spec (the `"korean_3set_390" -> "3f"` bug
   -- should have been `"39"`).

2. **Engine-specific coupling**: What strings are valid depends on which engines
   exist. `"korean_2set"` is valid because `HangulImeEngine` exists. A future
   `"japanese_romaji"` would be valid when `JapaneseImeEngine` exists. The
   registry is inherently coupled to concrete engine implementations -- behavior
   docs territory.

3. **Established pattern**: The registry was moved into the behavior docs as
   part of the v1.0-r9 cleanup (CTR-02). Appendix changelog D.4 records the
   original design decision from v0.4 that the IME contract owns the registry.
   The v1.0-r9 CTR-02 refined this: the interface contract owns the cross-
   reference, the behavior docs own the table.
