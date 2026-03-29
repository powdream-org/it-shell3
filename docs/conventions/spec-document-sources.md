# Spec Document Sources

The design spec spans three sources. All are normative. This is the shared
reference for all agents that read or verify against the spec.

## Precedence (highest first)

1. **Architecture Decision Records (ADRs)** — `docs/adr/`. Binding design
   decisions that override all other sources.

2. **Cross-Team Requests (CTRs)** —
   `docs/**/02-design-docs/<topic>/**/v<LATEST>/cross-team-requests/`. Approved
   spec amendments not yet incorporated into the design docs. On the same topic,
   a CTR supersedes the design doc (it is a more recent decision).

3. **Design docs** — `docs/**/02-design-docs/<topic>/**/v<LATEST>/`. Numbered
   files (`01-*.md` through `99-*.md`) plus `impl-constraints/` subdirectory.
   The highest version directory is the current revision.

Other files in the version directory (review-notes/, handover/, verification/)
are process artifacts, not spec.

## How to Find the Latest Version

```bash
ls -d docs/modules/<module>/02-design-docs/<topic>/draft/v*/ | sort -V | tail -1
```

If a `stable/` version exists alongside `draft/`, `draft/` is the working copy
and may contain updates not yet in `stable/`.

## Cross-Module References

When verifying code in module A against specs that reference module B's types,
check module B's latest spec version. Cross-module type names must be consistent
across all specs.
