# Commit Message Conventions

All commit messages **MUST** be written in **English only**.

## Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

## Rules

1. **Subject line** must be under 72 characters.
2. **Do not** capitalize the first letter of the description.
3. **Do not** end the subject line with a period.
4. Use **imperative mood** in the description (e.g., "add", not "added" or "adds").
5. Separate subject from body with a blank line.
6. Body should explain **why**, not what (the diff shows what).

## Types

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Build, CI, tooling, or maintenance |
| `style` | Formatting, whitespace (no logic change) |
| `perf` | Performance improvement |

## Scopes

Use the component or module the change belongs to:

| Scope | Area |
|-------|------|
| `daemon` | Server/daemon process |
| `client` | Client-side logic |
| `protocol` | Wire protocol, message types |
| `ime` | libitshell3-ime (input method engine) |
| `pty` | PTY management layer |
| `layout` | Window/pane/tab layout tree |
| `session` | Session persistence |
| `docs` | Design documents and specs |
| `build` | Build system (build.zig) |

Omit scope when the change spans multiple areas.

## Examples

```
feat(ime): implement Korean 2-set Jamo composition
fix(daemon): handle SIGTERM gracefully on socket cleanup
docs(protocol): add CJK preedit message spec
refactor(client): extract RenderState decoder into module
chore(build): add libhangul as git submodule dependency
test(pty): add spawn and I/O roundtrip tests
perf(protocol): use delta encoding for RenderState updates
```

## Commit Granularity

**One logical change per commit.** Split work into multiple commits when changes serve different purposes.

> **⚠️ AI agents: Always read the actual `git diff` output to decide how to split commits. Do NOT rely solely on changed file names — a single file may contain multiple unrelated changes, and multiple files may belong to one logical change.**

**Split when:**
- Implementation and its tests are separate concerns (e.g., `feat(ime): ...` then `test(ime): ...`)
- A refactor is needed before a feature (e.g., `refactor(client): ...` then `feat(client): ...`)
- Docs are updated alongside code (e.g., `feat(protocol): ...` then `docs(protocol): ...`)
- Multiple independent fixes are done in one session

**Do NOT split:**
- A single feature into arbitrary chunks — if it only works when all pieces are together, it's one commit
- Formatting/style changes mixed into a logical commit — make a separate `style` commit before or after

**Example — adding preedit support:**
```
refactor(protocol): extract message encoder into reusable module
feat(protocol): add CJK preedit message types
test(protocol): add preedit message roundtrip tests
docs(protocol): document preedit message wire format
```

## Multi-line Example

```
fix(ime): prevent Korean doubling on rapid backspace

The composition state machine was not clearing the pending Jamo buffer
when backspace arrived during an active preedit session. This caused
the previous syllable to be re-emitted on the next keystroke.
```
