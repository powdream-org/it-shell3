# Step 5: Scaffold & Build Verification

## Anti-Patterns

- **Don't spawn the team yet.** The scaffold must compile before any agent
  writes production code. Spawning early wastes agent time waiting.
- **Don't write production logic.** Create only the minimal files needed to
  verify the build chain works (directory structure, `build.zig`, trivial
  `root.zig` with one test).
- **Don't skip vendored C compilation.** If the target wraps a C library, verify
  the C build step works before proceeding. Build system issues found
  mid-implementation are expensive.
- **Vendored C must use ReleaseSafe.** Zig applies UBSan to C code in Debug
  mode, which conflicts with ptrace-based tools (kcov, debuggers). Always
  compile vendored C with `.ReleaseSafe`. (Lesson Z1 from
  `docs/insights/implementation-learnings.md`)

## Action

### 5a. Check cycle type

Read TODO.md's `Cycle Type` field:

- **If modification cycle** (spec-update or bug-fix): The target already has
  source code and a build system. Verify the existing build still works:

  ```bash
  mise run test:macos
  mise run test:macos:release-safe
  ```

  - If both pass → scaffold gate is already satisfied. Skip to Step 6.
  - If it fails → diagnose and fix before proceeding (the existing code is
    broken, which is a separate problem from the new work).

- **If greenfield cycle** → Continue with 5b below.

### 5b. Create directory structure

Follow the implementation plan's directory layout. Typical structure:

```
<target>/
├── build.zig
├── build.zig.zon
├── src/
│   └── root.zig      (minimal: pub export + one trivial test)
└── TODO.md            (already created in Step 1)
```

If the plan specifies vendored C dependencies, add the build step for them in
`build.zig`.

### 5c. Verify build chain

Run in sequence:

1. `(cd <target> && zig build)` — must compile without errors
2. If vendored C: verify the C compilation step succeeds
3. `mise run test:macos` — must pass the trivial test in `root.zig`

If any step fails, diagnose and fix before proceeding. Common issues:

- Wrong Zig version (check `build.zig.zon` engine version)
- Vendored C header paths not configured
- Missing `build.zig.zon` dependency declarations

### 5d. Signal scaffold ready

Once `mise run test:macos` passes, the scaffold gate is satisfied.

## Gate

- [ ] Directory structure created per plan
- [ ] `zig build` compiles without errors
- [ ] Vendored C compiles (if applicable) with `.ReleaseSafe`
- [ ] `mise run test:macos` passes
- [ ] No production logic written yet

## State Update

Update TODO.md:

- **Step**: 6 (Implementation Phase)
- Mark Step 5 as `[x]`

## Next

Read `steps/06-implementation.md`.
