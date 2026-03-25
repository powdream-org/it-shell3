---
name: testing
description: Use when running tests, measuring code coverage, or setting up the zig-kcov Docker image for libitshell3 modules. Also use when troubleshooting test failures or asking what test commands exist.
---

# Testing

Quick reference for all test tasks. All commands use `mise run`. See `mise.toml`
for the full task definitions and the current list of test modules.

## Prerequisites

- **Zig 0.15.2** and **Deno 2.7.5** — installed via `mise install`
- **Docker** — required for Linux tests and coverage
- **zig-kcov image** — must be built once before Linux/coverage tasks:

```bash
mise run build:docker:zig-kcov
```

Built from `Dockerfile.kcov` (base `kcov/kcov` + mise + zig + deno).
Layer-cached — rebuilds only when `mise.toml` tool versions change.

## Quick Reference

| Task                      | Command                            | Notes                       |
| ------------------------- | ---------------------------------- | --------------------------- |
| macOS tests (Debug)       | `mise run test:macos`              | Default for local dev       |
| macOS tests (ReleaseSafe) | `mise run test:macos:release-safe` | Optimized build             |
| Linux tests (Debug)       | `mise run test:linux`              | Requires zig-kcov image     |
| Linux tests (ReleaseSafe) | `mise run test:linux:release-safe` | Requires zig-kcov image     |
| Code coverage             | `mise run test:coverage`           | kcov in Docker, HTML report |

## Coverage Notes

- libitshell3 is rebuilt with `-Dghostty-simd=false -Doptimize=ReleaseSafe` for
  kcov (smaller DWARF, no C++ SIMD confusion)
- HTML report: `coverage/merged/index.html`
- Summary printed to stdout via Deno script
- Targets: line >= 95%, branch >= 90%, function 100% (per ADR-00052)
