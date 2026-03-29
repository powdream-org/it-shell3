# Cross-Document References

The deciding factor is **whether two documents share a revision cycle** (move
together), not whether they are in the same module.

- **Same revision cycle** (e.g., files within
  `interface-contract/draft/v1.0-r9/`): relative paths are fine — they always
  move together.
- **Independent revision cycles** (e.g., `interface-contract/draft/v1.0-r9/` →
  `behavior/draft/v1.0-r1/`, or any cross-module reference): **do NOT use exact
  file path links**. Exact paths encode revision numbers that break every time
  the target is revised.

Instead, use a loose prose reference:

```markdown
<!-- Avoid: exact path, breaks on every revision -->

See
[behavior/draft/v1.0-r1/02-scenario-matrix.md](../../../behavior/draft/v1.0-r1/02-scenario-matrix.md).
See
[daemon design doc 02 §4.2](../../../../../libitshell3/.../v1.0-r3/02-integration-boundaries.md#42-...).

<!-- Prefer: name the doc without the path; omit section numbers (they change too) -->

See `02-scenario-matrix.md` in the behavior docs for the complete scenario
matrix. See the `libitshell3` daemon design docs for details. See the
`libitshell3-protocol` server-client-protocols docs for details.
```
