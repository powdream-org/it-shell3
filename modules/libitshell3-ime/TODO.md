# libitshell3-ime Implementation TODO

**Spec**: IME Interface Contract v0.7
**Plan**: `.claude/plan/ime-implementation-plan.md`
**Team**: `.claude/agents/ime-impl-team/`

## Phase 1: Scaffold & Build Verification (3.2)

- [x] Create module directory structure
- [x] Create `build.zig` with libhangul C compilation
- [x] Create `build.zig.zon`
- [x] Create `config.h` for libhangul
- [x] Create minimal `src/root.zig`
- [x] Verify `zig build test` passes

## Phase 2: Implementation (3.3)

Note: `ENABLE_NLS` uses `#ifdef` (not `#if`), so `-UENABLE_NLS` is needed instead of `-DENABLE_NLS=0`.

- [ ] `src/types.zig` — KeyEvent, ImeResult + unit tests
- [ ] `src/hid_to_ascii.zig` — HID→ASCII lookup tables + unit tests
- [ ] `src/ucs4.zig` — UCS-4→UTF-8 conversion + unit tests
- [ ] `src/engine.zig` — ImeEngine vtable interface + unit tests
- [ ] `src/c.zig` — @cImport wrapper for libhangul
- [ ] `src/hangul_engine.zig` — HangulImeEngine + unit tests
- [ ] `src/mock_engine.zig` — MockImeEngine + unit tests
- [ ] `src/root.zig` — Public re-exports + test aggregation

## Phase 3: Integration Tests (3.3, parallel)

- [ ] 56 integration tests from scenario matrix (see plan §3.1)

## Phase 4: Spec Compliance Review (3.4)

- [ ] QA reviewer verifies all code against v0.7 spec

## Phase 5: Coverage Audit (3.6)

- [ ] Install kcov (`brew install kcov`)
- [ ] Run coverage, identify gaps
- [ ] Add tests to meet targets (line ≥95%, branch ≥90%, function 100%)

## Phase 6: Over-Engineering Review (3.7)

- [ ] Principal architect reviews all code for KISS/YAGNI violations
- [ ] Fix findings
- [ ] Re-run 3.4→3.6→3.7 if code changed

## Phase 7: Commit & Report (3.8)

- [ ] All gate conditions met
- [ ] Commit
- [ ] Report to owner

## Spec Gaps Discovered

(None yet)
