# Round 1 Verification Issues — IME Interface Contract v1.0-r9

**Date**: 2026-03-15
**Round**: 1
**Phase 1 agents**: consistency-verifier-r1, semantic-verifier-r1
**Phase 2 agents**: history-guardian-r1, issue-reviewer-r1
**Outcome**: 2 confirmed issues (both agents confirmed both issues)

---

## Confirmed Issues

### C-MINOR-01 — Unlinked plain-text external cross-reference

- **Severity**: minor
- **File**: `02-types.md`
- **Location**: Section 4 (Input Method Identifiers), line 164
- **Description**: `"See protocol doc 05, Section 4.1 for details."` is an unlinked
  plain-text cross-reference using informal naming ("protocol doc 05") and a section
  number that is not hyperlinked or verifiable against the current protocol v1.0-r12
  structure. Broken references in normative text are within the consistency-verifier's
  scope.
- **Fix**: Convert to a hyperlink with the actual file path and anchor. Protocol doc 05
  is `05-cjk-preedit-protocol.md` at
  `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r12/`.
  Verify the `4.1 InputMethodSwitch` heading exists before linking.

### S-MINOR-01 — Implementation details in interface contract violate editorial policy

- **Severity**: minor
- **File**: `03-engine-interface.md`
- **Location**: Section 2 (setActiveInputMethod Behavior), `**libhangul cleanup**` note (line ~151)
- **Description**: The `libhangul cleanup` note contains libhangul-specific API call
  sequences (`hangul_ic_flush()`, `hangul_buffer_clear()`), internal buffer field names
  (`choseong`, `jungseong`, `jongseong`), and internal function behavior. This is
  exactly the category of content the editorial policy in `01-overview.md` prohibits:
  "libhangul API call sequences, concrete struct fields, buffer layouts" belong in
  behavior docs. The policy contradiction is between two pieces of current normative
  text in docs this team owns.
- **Fix**: Remove the `libhangul cleanup` note (the libhangul-level justification).
  Retain only the caller-facing atomicity guarantee: `setActiveInputMethod()` performs
  flush + switch atomically; the caller does not need to call `flush()` separately.

---

## Dismissed Issues

None.

---

## Dismissed Issues Summary (for Round 2 Phase 1 agents)

No issues were dismissed in Round 1.
