# Verification Issues

```
v<X>/verification/round-{N}-issues.md
```

| Component | Rule |
|-----------|------|
| `{N}` | Sequential round number, starting at `1`. |

Produced by the team leader during the Revision Cycle (step 3.8) after
verification agents complete cross-validation (step 3.7). Lives inside
the `verification/` subdirectory of the version directory.

## Required Content

### Round Metadata

- Round number
- Date
- Verifier agents involved

### Issue List

Each issue must include:

| Field | Description |
|-------|-------------|
| Issue ID | Sequential within round (e.g., `V1-01`, `V1-02` for round 1) |
| Severity | `critical` or `minor` |
| Source document(s) | Which documents and sections are affected |
| Description | What the inconsistency is |
| Expected correction | What the fix should be (if identified by verifiers) |
| Consensus note | Brief summary of why all verifiers agreed this is a true alarm |

### Dismissed Issues Summary (optional)

Issues raised during step 3.6 that were unanimously dismissed during
step 3.7 cross-validation. Each entry includes a brief reason for
dismissal. Included for traceability, not for action.
