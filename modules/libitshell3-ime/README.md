# libitshell3-ime

Native IME engine in Zig wrapping libhangul for Korean Hangul composition + English QWERTY direct passthrough. No OS IME dependency.

## Documentation

- [Overview](../../docs/modules/libitshell3-ime/01-overview/)
- [Design Documents](../../docs/modules/libitshell3-ime/02-design-docs/)

## Versioning

The software version in `build.zig.zon` tracks the IME Interface Contract design version: `v<contract_version>.<patch>`. For example, version `0.7.0` implements IME Interface Contract v0.7.

## Known Issues

- **Instrumented code coverage unavailable**: Zig's self-hosted linker on macOS leaves insufficient headroom between load commands and `__text` section offset, making DWARF debug info unparseable by kcov/dsymutil. Upstream bug: [ziglang/zig#31428](https://codeberg.org/ziglang/zig/issues/31428). Coverage is verified via scenario-matrix tests (136 named tests across 17 categories) instead.
- **Vendored libhangul compiled with ReleaseSafe**: Zig's UBSan instrumentation on C code in Debug mode conflicts with ptrace-based tools (kcov, debuggers). libhangul is pinned to `.ReleaseSafe` to avoid this.
