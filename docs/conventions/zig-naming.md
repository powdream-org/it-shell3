# Zig Naming Conventions

Naming rules for all Zig source code in the it-shell3 project. These conventions
complement the
[Zig style guide](https://ziglang.org/documentation/master/#Naming-Conventions)
and add project-specific rules.

## General Rules

- **No abbreviations in identifiers.** Use full words: `name_length` not
  `name_len`, `active_input_method_length` not `aim_len`. Abbreviations save a
  few keystrokes but cost readability for every future reader.
- **Exception — widely recognized domain abbreviations**: `fd` (file
  descriptor), `pid` (process ID), `pty` (pseudoterminal), `cwd` (current
  working directory), `utf8`, `hid` (Human Interface Device). These are more
  recognizable than their expansions.

## Naming Patterns

### Types

| Kind                   | Convention | Example                                 |
| ---------------------- | ---------- | --------------------------------------- |
| Structs, Enums, Unions | PascalCase | `SessionEntry`, `PaneSlot`, `ImeResult` |
| Error sets             | PascalCase | `error{UnsupportedInputMethod}`         |
| Type aliases           | PascalCase | `pub const FreeMask = u16;`             |

### Values

| Kind                 | Convention | Example                                        |
| -------------------- | ---------- | ---------------------------------------------- |
| Variables, fields    | snake_case | `session_id`, `name_length`, `focused_pane`    |
| Constants (comptime) | snake_case | `max_panes`, `max_session_name`                |
| Functions            | camelCase  | `processKey()`, `allocPaneSlot()`, `getName()` |

### Constants for Buffer Sizes

Fixed-size buffer fields (per ADR 00058) use paired constants:

```zig
pub const MAX_SESSION_NAME: u8 = 64;

// In Session struct:
name: [MAX_SESSION_NAME]u8,
name_length: u8,
```

The constant name uses the pattern `MAX_` + field name in SCREAMING_SNAKE_CASE.
The length field uses the buffer field name + `_length` suffix.

### Getter Methods

Getter methods for inline buffer fields return `[]const u8` slices:

```zig
pub fn getName(self: *const Session) []const u8 {
    return self.name[0..self.name_length];
}
```

The getter name uses `get` + PascalCase field name. No `get_` prefix
(snake_case) — Zig convention is camelCase for functions.

## Module Names

- Named sub-modules use snake_case: `itshell3_core`, `itshell3_os`,
  `itshell3_protocol`.
- File names use snake_case: `session_manager.zig`, `key_encoder.zig`.
- Directory names use snake_case: `server/handlers/`.

## Test Names

Test names are descriptive strings in lowercase:

```zig
test "allocPaneSlot: returns first free slot" { ... }
test "Session.init: defaults to direct input method" { ... }
```

Pattern: `function_or_type: description of what is being tested`.
