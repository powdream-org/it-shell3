# Design Document Metadata

Spec documents (numbered `01-*.md` through `99-*.md`) use bullet-item metadata
immediately after the `# Title` heading. Only these two properties are allowed:

```markdown
# Document Title

- **Date**: YYYY-MM-DD
- **Scope**: one-line description of what this document covers
```

Do NOT add Status, Version, Author, Depends on, Changes from, or any other
metadata. Status and version are encoded in the directory path
(`draft/v1.0-rN/`). Author and dependency info belong in changelogs or
resolution docs, not in the spec header.

Process artifacts (review notes, design resolutions, verification issues,
cross-team requests) have their own metadata conventions defined in
`docs/conventions/artifacts/documents/`.
