# Implementation Learnings

Cross-cutting lessons from implementation work. Updated as new modules are implemented.

---

## Zig Toolchain

| # | Lesson | Origin | Impact |
|---|--------|--------|--------|
| Z1 | **Vendored C must compile with ReleaseSafe** | libitshell3-ime | Zig applies UBSan instrumentation to C code in Debug mode. This conflicts with ptrace-based tools (kcov, debuggers), causing segfaults. Compile vendored C libraries with `.ReleaseSafe` to disable UBSan while keeping safety checks. Applies to any module wrapping vendored C. |
| Z2 | **Zig linker Mach-O blocks instrumented coverage on macOS** | libitshell3-ime | Zig's self-hosted linker leaves insufficient headroom between load commands and `__text` section offset. DWARF-dependent tools (nm, dsymutil, kcov) fail on the resulting binary. [ziglang/zig#31428](https://codeberg.org/ziglang/zig/issues/31428). Monitor upstream for fix before enabling coverage on other Zig modules. |
| Z3 | **`= undefined` is real UB** | libitshell3-ime | Unlike C's indeterminate value, Zig's `= undefined` is genuine UB that can cause crashes under instrumentation. Use `@splat(0)` for buffers that may be read before full initialization. |

## Testing

| # | Lesson | Origin | Impact |
|---|--------|--------|--------|
| T1 | **Scenario-matrix tests are a viable coverage substitute** | libitshell3-ime | When instrumented coverage is blocked by toolchain issues, a named-test-per-spec-path approach provides equivalent confidence. Each spec scenario maps to a uniquely named test, making coverage auditable. Validated with 136 tests across 17 categories. |
