# SplitNodeData File Annotation: split_node.zig → split_tree.zig

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-5)
- **Target docs**: daemon-architecture 02-state-and-types.md
- **Status**: open

---

## Context

Plan 8 verification found the spec annotates SplitNodeData at
`core/split_node.zig` but the code defines it in `core/split_tree.zig`. The file
was named `split_tree.zig` because it contains both the SplitNodeData union type
and tree operation types (TreeFull, MaxDepthExceeded).

## Required Changes

1. **02-state-and-types.md**: Update SplitNodeData annotation from
   `<<core/split_node.zig>>` to `<<core/split_tree.zig>>`.

## Summary Table

| Target Doc            | Section/Message          | Change Type | Source Resolution |
| --------------------- | ------------------------ | ----------- | ----------------- |
| 02-state-and-types.md | SplitNodeData annotation | Path update | SC-5 triage       |
