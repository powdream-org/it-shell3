# Zig Documentation Conventions

Documentation rules for all Zig source code in the it-shell3 project.

## Doc Comments (`///`)

Use `///` for public functions, types, and fields that need explanation. Do NOT
add doc comments to self-explanatory code — well-named identifiers are
documentation.

## Spec References in Code

**Do NOT embed spec section numbers in doc comments or inline comments.**

Section numbers change on every spec revision. Hardcoded references like
`Section 8.1` or `§5.2` become stale and misleading.

```zig
// BAD — section number will change on spec revision
/// Section 8.1: Ownership transfer (reference procedure).

// BAD — section number embedded in inline comment
// Step 4 per §8.1: Clear preedit

// GOOD — describes what, references spec by topic name
/// Ownership transfer: flush-and-transfer sequence.
/// See ime-procedures spec for the canonical step sequence.

// GOOD — references spec by document name, not section number
// See daemon-behavior impl-constraints/ime-procedures for step details.
```

**Allowed**: referencing a spec document by name (e.g., "ime-procedures spec",
"daemon-architecture integration-boundaries"). These are stable across
revisions.

**Not allowed**: referencing a spec section by number (e.g., "§8.1", "Section
5.2", "doc 03 §4"). These break on every revision.

## TODO Comments

TODO comments MUST include a plan reference indicating when the work will be
done:

```zig
// TODO(Plan 6): Add silence detection timer
// TODO(Plan 7): Implement daemon shortcut keybinding system
```

Bare `// TODO:` without a plan reference is not allowed — it creates unbounded
technical debt with no tracking.

## Implementation Learnings References

When code implements a workaround or non-obvious pattern documented in
`docs/insights/implementation-learnings.md`, reference it by lesson ID:

```zig
/// Persistent ghostty VT parser stream. Held for the pane's lifetime so
/// that split escape sequences spanning multiple PTY reads are parsed
/// correctly. (See implementation-learnings.md G3.)
```
