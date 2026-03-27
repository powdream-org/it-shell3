# Zig Documentation Conventions

Documentation rules for all Zig source code in the it-shell3 project.

## Table of Contents

- [1. Module-Level Documentation (`//!`)](#1-module-level-documentation-)
- [2. General Principles](#2-general-principles)
  - [2.1 Prefer brevity](#21-prefer-brevity)
  - [2.2 Do not restate the obvious](#22-do-not-restate-the-obvious)
  - [2.3 Write for the caller, not the implementer](#23-write-for-the-caller-not-the-implementer)
  - [2.4 Format comments like sentences](#24-format-comments-like-sentences)
- [3. Doc Comments (`///`)](#3-doc-comments-)
  - [3.1 Start with a single-sentence summary](#31-start-with-a-single-sentence-summary)
  - [3.2 Separate the summary from the body](#32-separate-the-summary-from-the-body)
  - [3.3 Phrasing conventions](#33-phrasing-conventions)
  - [3.4 Consider documenting private declarations](#34-consider-documenting-private-declarations)
  - [3.5 Consider including code samples](#35-consider-including-code-samples)
  - [3.6 Describe parameters and return values in prose](#36-describe-parameters-and-return-values-in-prose)
  - [3.7 Avoid unclear abbreviations and acronyms](#37-avoid-unclear-abbreviations-and-acronyms)
- [4. Inline Comments (`//`)](#4-inline-comments-)
- [5. Spec References in Code](#5-spec-references-in-code)
- [6. TODO Comments](#6-todo-comments)
- [7. Implementation Learnings References](#7-implementation-learnings-references)
- [8. Markdown in Doc Comments](#8-markdown-in-doc-comments)

---

## 1. Module-Level Documentation (`//!`)

Every `root.zig` file **MUST** have top-level doc comments (`//!`) describing
what the module is. These comments appear at the very top of the file, before
any `const`, `pub`, or other declarations.

Focus on **"what this is"** — the module's purpose and scope. Do not describe
internal implementation details or list every public symbol.

```zig
//! Ring buffer for terminal frame delivery. Manages I-frame and P-frame
//! storage with producer/consumer semantics for the daemon-to-client
//! render pipeline.

const std = @import("std");
```

Top-level doc comments are **not optional** for `root.zig` files. For other
files, consider adding `//!` when the filename alone does not convey the file's
role.

## 2. General Principles

### 2.1 Prefer brevity

Be clear and precise through conciseness. Respect the reader's time. If a name
already communicates something, do not repeat it in prose.

### 2.2 Do not restate the obvious

Avoid redundancy with surrounding context. Do not echo information already
visible in the type signature, field name, or enclosing scope. Add value beyond
what the code already says.

```zig
// BAD — restates the signature
/// Returns the number of active sessions.
pub fn activeSessionCount() usize { ... }

// GOOD — adds context beyond the name
/// Counts only sessions with at least one connected client.
pub fn activeSessionCount() usize { ... }
```

### 2.3 Write for the caller, not the implementer

Documentation should tell the reader what they need to **use** the API, not how
it works internally. Implementation notes belong in inline comments (`//`), not
doc comments (`///`).

### 2.4 Format comments like sentences

Capitalize the first word (unless it is a case-sensitive identifier) and end
with a period. This applies to doc comments, inline comments, and TODOs.

```zig
// BAD
// send the frame to all connected clients

// GOOD
// Send the frame to all connected clients.
```

## 3. Doc Comments (`///`)

Use `///` for public functions, types, and fields that need explanation. Do NOT
add doc comments to self-explanatory code — well-named identifiers are
documentation.

### 3.1 Start with a single-sentence summary

The first sentence should be a brief, self-contained description. Tools and
readers often scan only this line.

```zig
/// Flushes pending preedit state and transfers ownership to the new pane.
///
/// This is called during pane focus changes. The source pane's composition
/// buffer is committed before the transfer begins.
pub fn transferOwnership(self: *Self, target: *Pane) void { ... }
```

### 3.2 Separate the summary from the body

If more detail is needed, leave a blank `///` line after the first sentence. The
first paragraph stands alone as the short description.

### 3.3 Phrasing conventions

| What you are documenting      | Start with                                     |
| ----------------------------- | ---------------------------------------------- |
| Function with side effects    | Third-person verb ("Sends...", "Registers...") |
| Function returning a value    | Noun phrase ("The number of...", "Whether...") |
| Boolean field or function     | "Whether" + condition                          |
| Non-boolean field or variable | Noun phrase describing what the value **is**   |
| Type (struct, enum, union)    | Noun phrase describing instances of the type   |

```zig
/// Whether the session has any connected clients.
is_active: bool,

/// Maximum number of bytes the ring buffer can hold.
capacity: usize,

/// Registers a new client connection and performs capability negotiation.
pub fn registerClient(self: *Self, fd: posix.fd_t) !void { ... }
```

### 3.4 Consider documenting private declarations

When a private function or type is complex or called from multiple places, a doc
comment aids future maintainers.

### 3.5 Consider including code samples

Short usage examples inside doc comments help readers understand intended
calling patterns quickly.

### 3.6 Describe parameters and return values in prose

Integrate parameter descriptions into the doc comment's prose rather than using
a separate tag list. Mention parameter names directly so they are searchable.

```zig
/// Writes `data` into the ring buffer starting at `offset`. Returns the
/// number of bytes actually written, which may be less than `data.len` if
/// the buffer wraps or is full.
pub fn writeAt(self: *Self, offset: usize, data: []const u8) usize { ... }
```

### 3.7 Avoid unclear abbreviations and acronyms

Do not use abbreviations unless they are universally understood by the target
audience (e.g., PTY, IME, VT). Spell out anything ambiguous on first use.

## 4. Inline Comments (`//`)

Use `//` for implementation-level notes: why a particular approach was chosen,
non-obvious control flow, or workaround explanations. Do not use block comments
(`/* */`) except for temporarily commenting out code.

## 5. Spec References in Code

**Do NOT embed spec section numbers in doc comments or inline comments.**

Section numbers change on every spec revision. Hardcoded references like
`Section 8.1` or `§5.2` become stale and misleading.

```zig
// BAD — section number will change on spec revision
/// Section 8.1: Ownership transfer (reference procedure).

// BAD — section number embedded in inline comment
// Step 4 per §8.1: Clear preedit

// GOOD — describes what, references spec by topic name
/// Ownership transfer: flush-and-transfer sequence.
/// See ime-procedures spec for the canonical step sequence.

// GOOD — references spec by document name, not section number
// See daemon-behavior impl-constraints/ime-procedures for step details.
```

**Allowed**: referencing a spec document by name (e.g., "ime-procedures spec",
"daemon-architecture integration-boundaries"). These are stable across
revisions.

**Not allowed**: referencing a spec section by number (e.g., "§8.1", "Section
5.2", "doc 03 §4"). These break on every revision.

## 6. TODO Comments

TODO comments MUST include a plan reference indicating when the work will be
done:

```zig
// TODO(Plan 6): Add silence detection timer.
// TODO(Plan 7): Implement daemon shortcut keybinding system.
```

Bare `// TODO:` without a plan reference is not allowed — it creates unbounded
technical debt with no tracking.

## 7. Implementation Learnings References

When code implements a workaround or non-obvious pattern documented in
`docs/insights/implementation-learnings.md`, reference it by lesson ID:

```zig
/// Persistent ghostty VT parser stream. Held for the pane's lifetime so
/// that split escape sequences spanning multiple PTY reads are parsed
/// correctly. (See implementation-learnings.md G3.)
```

## 8. Markdown in Doc Comments

When using markdown inside `///` doc comments:

- Use backtick fences (`` ``` ``) for code blocks, not indentation.
- Keep formatting minimal — use styling to illuminate content, not replace it.
- Avoid HTML markup. If the content needs a table, consider whether the comment
  is too complex and should live in a design doc instead.
