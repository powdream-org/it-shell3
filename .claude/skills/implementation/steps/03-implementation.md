# Step 3: Implementation Phase

## Anti-Patterns

- **Don't proxy messages between implementer and QA.** They talk peer-to-peer.
  See `02-team-collaboration.md` Section 5.
- **Don't micromanage.** Tell agents WHAT to build (spec references, file
  assignments), not HOW to write each line. "Change line 43 to X" is
  micromanagement — "implement the processKey pipeline per spec §2" is
  delegation.
- **Don't reuse agent names from a previous context without checking for stale
  shutdown requests.** Stale requests from pre-compaction context can cause
  premature exit. Use fresh names or verify clean state.
- **Don't use `= undefined` for buffers.** Zig's `= undefined` is genuine UB
  (unlike C's indeterminate value). Use `@splat(0)` or zero-initialization for
  buffers that may be read before full initialization. (Lesson Z3)
- **Don't let the QA reviewer wait for all files.** They can test completed
  files as they become available.

## Action

### 3a. Check context budget

If context window ≤ 25%, ask the owner to `/compact` before spawning agents.

### 3b. Prepare spawn context

Gather these for each agent:

**For the implementer:**

- Spec document paths (from TODO.md)
- Implementation plan path
- PoC reference paths (if any)
- File assignments from the plan
- `docs/insights/implementation-learnings.md` (Zig toolchain lessons)

**For the QA reviewer:**

- Same spec document paths
- Integration test matrix from the plan (or spec scenario matrix)
- Coverage approach (instrumented or scenario-matrix)
- Module source path: `<target>/src/`

### 3c. Spawn both agents

Use two-phase spawn to prevent first-agent-starts-alone:

**Phase 1 — Registration:**

Spawn both agents from `.claude/agents/impl-team/`:

```
Implementer: "You are implementing module <module>. Wait for my signal before
writing any code. Spec: <paths>. Plan: <path>. PoC: <paths or 'none'>.
Source dir: <target>/src/. Read the spec and plan, then confirm ready."

QA Reviewer: "You are QA for module <module>. Wait for my signal before writing
any tests. Spec: <paths>. Test matrix: <path or inline>. Coverage approach:
<instrumented/scenario-matrix>. Source dir: <target>/src/.
Read the spec and test matrix, then confirm ready."
```

Wait for both to confirm ready.

**Phase 2 — Begin:**

Send to both: "Begin implementation. Communicate directly with each other as
needed."

### 3d. Monitor progress

Wait for both agents to report completion. During this time:

- Answer questions from either agent (relay to owner if beyond your scope)
- Log any spec gaps discovered to TODO.md's "Spec Gap Log" section
- Do NOT intervene unless asked or unless you observe clear spec violations

### 3e. Verify tests and formatting

Once both report complete:

```bash
(cd <target> && zig build test)
(cd <target> && zig build test -Doptimize=ReleaseSafe)
(cd <target> && zig fmt --check src/)
```

Running tests in both Debug (default) and ReleaseSafe catches
optimization-sensitive bugs that only manifest under optimization.

If any check fails, send results to the relevant agent for fixing. Do NOT
proceed until all pass.

### 3f. Keep team alive

Do NOT disband the team. The implementer and QA reviewer continue into Steps 4–7
(the verification chain). They are disbanded in Step 8.

## Gate

- [ ] Implementer reports all source files complete with inline unit tests
- [ ] QA reviewer reports all integration tests complete
- [ ] `zig build test` passes in Debug mode (all unit + integration tests)
- [ ] `zig build test -Doptimize=ReleaseSafe` passes (optimization-sensitive
      bugs)
- [ ] `zig fmt --check src/` passes (no formatting issues)
- [ ] Spec gaps (if any) logged in TODO.md

## State Update

Update TODO.md:

- **Step**: 4 (Spec Compliance Review)
- **Active Team**: impl-team
- **Team Directory**: `.claude/agents/impl-team/`
- Mark Step 3 as `[x]`

## Next

Read `steps/04-spec-compliance.md`.
