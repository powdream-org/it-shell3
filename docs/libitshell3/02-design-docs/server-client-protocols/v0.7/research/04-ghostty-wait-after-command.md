# ghostty / libghostty: wait-after-command Option

**Reference**: ghostty @ `2502ca2`

## Summary

ghostty provides a `wait-after-command` config option that controls whether the terminal surface remains open after the child process exits. This research documents the option's mechanics and how libghostty exposes it to embedders.

## Config Definition

**File**: `src/config/Config.zig` line 1349-1355

```zig
/// If true, keep the terminal open after the command exits. Normally, the
/// terminal window closes when the running command (such as a shell) exits.
/// With this true, the terminal window will stay open until any keypress is
/// received.
///
/// This is primarily useful for scripts or debugging.
@"wait-after-command": bool = false,
```

Default: `false` (auto-close on process exit).

## Related Config

**File**: `src/config/Config.zig` line 1357-1364

```zig
@"abnormal-command-exit-runtime": u32 = 250,
```

If the process exits within this many milliseconds of launch, ghostty treats it as an abnormal exit and shows an error message regardless of `wait-after-command`. On macOS, any exit code triggers this; on Linux, only non-zero exit codes.

## Surface Internal State

**File**: `src/Surface.zig` line 322

The config value is stored as `wait_after_command: bool` in the Surface's DerivedConfig struct (line 322). It is read from the config at Surface init time (line 400):

```zig
.wait_after_command = config.@"wait-after-command",
```

The Surface also tracks whether the child has exited via `child_exited: bool` (line 1200).

## Process Exit Flow

**File**: `src/Surface.zig` lines 1198-1276, function `childExited`

The full flow when a child process exits:

1. `self.child_exited = true` — mark exit state
2. **Abnormal exit check** (lines 1204-1231): If runtime < `abnormal_command_exit_runtime_ms`, show error GUI or terminal message. Return early (do not auto-close).
3. **Exit message** (lines 1234-1267): Unconditionally writes "Process exited. Press any key to close the terminal." to the terminal buffer. This message is shown even when `wait_after_command = false`, because ghostty supports `undo` to restore a closed surface — the message tells the user the process already exited.
4. **Wait-after-command gate** (lines 1269-1271):
   ```zig
   if (self.config.wait_after_command) return;
   ```
   If `true`, stop here. The surface stays open. The user presses any key to close.
5. **Auto-close** (lines 1273-1275):
   ```zig
   self.close();
   ```
   If `false`, close immediately with no confirmation.

## libghostty Embedder Interface

**File**: `src/apprt/embedded.zig` lines 455-565

libghostty does NOT read config files directly. The embedder passes the option via `Surface.Options`:

```zig
pub const Options = struct {
    // ...
    wait_after_command: bool = false,
    // ...
};
```

During Surface init, the embedder's option overrides the config:

```zig
if (opts.wait_after_command) {
    config.@"wait-after-command" = true;
}
```

Default is `false`. If the embedder does not set this field, the Surface will auto-close on process exit.

## C API Exposure

**File**: `include/ghostty.h` line 451

```c
bool wait_after_command;
```

The option is exposed in the C header as part of the surface configuration struct, accessible to Swift/C consumers.

## Key Observations

1. **Embedder-driven**: libghostty does not read ghostty's config file. The embedder (our daemon) must explicitly pass `wait_after_command` when creating each Surface.
2. **Default is auto-close**: If the embedder does nothing, surfaces auto-close on process exit.
3. **Exit message always written**: Even with auto-close, ghostty writes "Process exited..." to the terminal buffer before closing. In a daemon context where the Surface may not be immediately destroyed, this text could appear in the terminal grid.
4. **Abnormal exit bypass**: Short-lived processes get special handling regardless of `wait-after-command`. The daemon needs to account for this if it wants consistent auto-close behavior.
