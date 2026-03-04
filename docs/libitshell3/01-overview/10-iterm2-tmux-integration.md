# iTerm2 tmux -CC Integration Analysis

## Overview

iTerm2 has the deepest tmux integration of any terminal emulator. Its `tmux -CC` (control mode) integration maps tmux windows/panes to native macOS tabs/splits, creating a seamless experience where the user doesn't see tmux's UI at all. This is the gold standard for what it-shell3 should achieve with its own protocol.

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                         iTerm2                            │
│                                                          │
│  ┌────────────┐   ┌──────────────┐   ┌───────────────┐  │
│  │ PTYSession  │   │ TmuxGateway  │   │TmuxController │  │
│  │ (Gateway)   │──>│ (Protocol    │──>│ (Orchestrator)│  │
│  │ runs tmux   │   │  Parser)     │   │               │  │
│  │ -CC process │   │              │   │ Maps tmux     │  │
│  └──────┬──────┘   └──────────────┘   │ objects to    │  │
│         │                              │ native UI     │  │
│         │ PTY fd                       │               │  │
│         │                              └──────┬────────┘  │
│         │                                     │           │
│  ┌──────┴──────┐                     ┌────────┴────────┐ │
│  │ FileDesc    │                     │ PTYSession(s)   │ │
│  │ Server      │                     │ (Client panes)  │ │
│  │ (daemon)    │                     │ Native tabs/    │ │
│  │ Survives    │                     │ splits          │ │
│  │ crashes     │                     │                 │ │
│  └─────────────┘                     └─────────────────┘ │
│                                                          │
└──────────────────────────────────────────────────────────┘
              │                              │
              │ Unix socket                  │ (no local PTY)
              ▼                              │
        ┌───────────┐                        │
        │ tmux      │ ◄─ sends %output ──────┘
        │ server    │    %layout-change
        │ (daemon)  │    %window-add
        │           │    etc.
        └───────────┘
```

### Key Insight

iTerm2 has **two types of sessions** in tmux mode:

1. **Gateway Session** (`TMUX_GATEWAY`): The single session running the `tmux -CC` process. It receives all control mode output and dispatches it. Its PTY runs under a FileDescriptorServer daemon that survives app crashes.

2. **Client Sessions** (`TMUX_CLIENT`): One per tmux pane. These have **no local PTY** — they use a pipe instead. Terminal output from `%output` notifications is written to the pipe. Keyboard input is sent back via `send-keys` commands through the gateway.

---

## 2. Entry into tmux Control Mode

### DCS Sequence Detection

When `tmux -CC` starts, it sends a DCS (Device Control String) sequence:
```
\033P1000p
```

The VT100 parser (`VT100DCSParser.m`) detects parameter `1000` with character `p` and installs a `VT100TmuxParser` as a hook. From this point, all input bypasses the normal VT100 state machine and is parsed line-by-line as tmux control mode output.

```objc
// VT100DCSParser.m, line 516-526
case MAKE_COMPACT_SEQUENCE(0, 0, 'p'):
    if ([[self parameters] isEqual:@[ @"1000" ]]) {
        token->type = DCS_TMUX_HOOK;
        _hook = [[VT100TmuxParser alloc] init];
    }
```

### PTYSession Mode Transition

```objc
// PTYSession.m, line 8796
- (void)startTmuxMode:(NSString *)dcsID {
    // 1. Send ^C to break any pending shell prompt
    // 2. Set mode to TMUX_GATEWAY
    _tmuxMode = TMUX_GATEWAY;
    // 3. Create gateway and controller
    _tmuxGateway = [[TmuxGateway alloc] initWithDelegate:self dcsID:dcsID];
    _tmuxController = [[TmuxController alloc] initWithGateway:_tmuxGateway
                                                  clientName:clientName
                                                     profile:profile];
}
```

---

## 3. Command Queue Protocol

TmuxGateway implements a strict **request-response** model using tmux's `%begin`/`%end` framing.

### Command Flow

```
iTerm2 (Client)              tmux server
     │                           │
     ├── "list-windows -F ..." ─>│
     │                           │
     │<── %begin <id> <num> ─────│
     │<── @0: vim [80x24] ... ───│  (response lines)
     │<── @1: shell [80x24] ... ─│
     │<── %end <id> <num> ───────│
     │                           │
     │  → callback invoked       │
     │    with response text     │
```

### Command Dictionary Structure

```objc
{
    kCommandTarget: id,              // Callback target
    kCommandSelector: SEL,           // Callback selector
    kCommandString: @"list-windows", // The command text
    kCommandObject: id,              // Optional context object
    kCommandFlags: NSNumber,         // Flags (e.g., kCommandIsInitial)
    kCommandIsInList: @YES,          // Part of a command list?
    kCommandTimestamp: NSDate,       // For latency tracking
}
```

### Write Deferral

The gateway defers all writes until confirmed connected:
- `_canWrite` starts as `NO`
- Set to `YES` when `%session-changed` is received
- Before that, commands are buffered in `_writeQueue`

---

## 4. Notification Dispatch

Once `acceptNotifications_` is enabled (after initial command list completes), the gateway processes these control mode notifications:

### Terminal Output
```
%output %<pane-id> <octal-escaped-data>
%extended-output %<pane-id> <latency-us> : <octal-escaped-data>
```

The `%output` payload uses **octal escaping** (`\NNN` for non-printable bytes). The gateway decodes this and calls `tmuxReadTask:` which writes the decoded data into the client session's pipe.

### Layout Changes
```
%layout-change @<window-id> <layout-string> <visible-layout-string>
```

Layout strings are parsed by `TmuxLayoutParser` (see below) and applied to the native view hierarchy.

### Window Lifecycle
```
%window-add @<id>
%window-close @<id>
%window-renamed @<id> <name>
```

### Session Events
```
%session-changed $<session-id> <name>
%session-renamed $<session-id> <name>
%sessions-changed
```

### Flow Control (tmux 3.2+)
```
%pause %<pane-id>
%continue %<pane-id>
```

### Clipboard
```
%paste-buffer-changed <buffer-name>
```

---

## 5. Layout Parsing and Native View Creation

### Layout String Format

tmux layout strings encode the split tree:

```
# Syntax:
# <checksum>,<WxH,X,Y>                          → Leaf pane
# <checksum>,<WxH,X,Y>{child1,child2,...}        → Horizontal split
# <checksum>,<WxH,X,Y>[child1,child2,...]        → Vertical split

# Example: Two panes side by side
ab34,159x48,0,0{79x48,0,0,1,79x48,80,0,2}
```

### TmuxLayoutParser

Parses the layout string into a nested dictionary tree:

```objc
// Result structure:
@{
    kLayoutDictNodeType: @(kHSplitLayoutNode),  // or kVSplit, kLeaf
    kLayoutDictWidthKey: @159,
    kLayoutDictHeightKey: @48,
    kLayoutDictXOffsetKey: @0,
    kLayoutDictYOffsetKey: @0,
    kLayoutDictChildrenKey: @[
        @{
            kLayoutDictNodeType: @(kLeafLayoutNode),
            kLayoutDictWindowPaneKey: @1,
            kLayoutDictWidthKey: @79,
            ...
        },
        @{
            kLayoutDictNodeType: @(kLeafLayoutNode),
            kLayoutDictWindowPaneKey: @2,
            kLayoutDictWidthKey: @79,
            ...
        }
    ]
}
```

### Mapping to Native Views

`PTYTab` converts the parse tree to native `NSSplitView` hierarchy:

1. **Cell sizes → pixel sizes**: `setSizesInTmuxParseTree:` converts terminal cell dimensions to pixel dimensions using the font metrics.
2. **Inject root split**: Ensures the tree has a root split node (even for single-pane windows).
3. **Create arrangement**: Converts to iTerm2's internal "arrangement" format.
4. **Build views**: `tabWithArrangement:` recursively creates `NSSplitView`s (for splits) and `SessionView`s (for panes).

### Layout Change Handling

When `%layout-change` arrives:

1. Parse new layout string
2. Compare with current view hierarchy
3. If structure matches (same tree topology): **resize in place** — just adjust divider positions
4. If structure differs: **replace entire view hierarchy** — tear down old views, build new ones, reconnect sessions to new views

---

## 6. Keyboard Input Path (iTerm2 → tmux)

### Client Session Key Flow

```
User presses key
    │
    ▼
PTYSession.writeTask (TMUX_CLIENT mode)
    │
    ▼
TmuxGateway.sendKeys:toWindowPane:
    │
    ├── If tmux supports UTF-8:
    │   sendCodePoints (actual Unicode codepoints)
    │
    └── If tmux is old:
        Send individual UTF-8 bytes as separate "keystrokes"
    │
    ▼
Run-length encode into tmux commands:
    │
    ├── Literal chars (a-z, 0-9, +, /, etc.):
    │   "send -lt %<pane> <chars>"
    │
    └── Non-literal chars:
        "send -t %<pane> 0xNN 0xMM ..."
    │
    ▼
Commands batched (max 1000 bytes each)
    │
    ▼
Written to gateway PTY fd → tmux -CC stdin
```

### Key Encoding Details

```objc
// TmuxGateway.m, line 899-941
- (void)sendCodePoints:(NSArray<NSNumber *> *)codePoints
          toWindowPane:(int)windowPane {
    // Group characters:
    // - 'literal' chars (alphanumeric, safe punctuation) → send -lt
    // - 'non-literal' chars → send -t 0xHH 0xHH
    //
    // Batch into commands ≤ 1000 bytes
    // Send as command list via gateway write
}
```

---

## 7. Copy/Paste Through tmux Control Mode

### Outbound (tmux → macOS clipboard)

```
tmux server notifies: %paste-buffer-changed <name>
    │
    ▼
TmuxGateway parses notification
    │
    ▼
TmuxController.copyBufferToLocalPasteboard:
    │
    ▼
Sends: "show-buffer -b <name>" via control mode
    │
    ▼
Response arrives between %begin/%end
    │
    ▼
Callback places text on NSPasteboard.generalPasteboard
```

### Security

Buffer names are validated with regex `buffer[0-9]+` to prevent command injection.

### Modes

1. **Auto-sync** (`kPreferenceKeyTmuxSyncClipboard` = YES): Automatically copies to macOS clipboard
2. **Ask mode**: Prompts user with "Mirror tmux paste buffer?" dialog

---

## 8. Session Restoration (Crash Recovery)

### FileDescriptorServer Architecture

Each shell process runs under a persistent daemon:

```
┌─────────────┐          ┌──────────────────┐
│  iTerm2 App │ ◄──fd──► │  FileDesc Server │
│  (may crash)│          │  (daemon, lives  │
│             │          │   in per-user    │
└─────────────┘          │   namespace)     │
                         │        │         │
                         │  ┌─────┴──────┐  │
                         │  │ tmux -CC   │  │
                         │  │ (child)    │  │
                         │  └────────────┘  │
                         └──────────────────┘
```

**Critical trick**: `MoveOutOfAquaSession()` moves the server process from the macOS per-session (Aqua) namespace to the per-user namespace using Mach bootstrap ports. This ensures the server survives if the Aqua session (and iTerm2 with it) dies.

### Recovery Sequence

1. iTerm2 crashes
2. tmux -CC process continues running (parented to the FileDescriptorServer)
3. tmux server keeps all sessions alive
4. iTerm2 restarts
5. Scans for orphan FileDescriptorServer processes
6. Reconnects to the gateway's server via Unix socket
7. Receives PTY master fd via `sendmsg()` FD passing
8. VT100 parser enters **recovery mode**: `startTmuxRecoveryModeWithID:`
   - Installs VT100TmuxParser in recovery mode
   - Recovery parser ignores first line (may be mid-notification)
   - Only processes `%begin` or `%exit` immediately
9. Creates fresh TmuxGateway and TmuxController
10. Re-enumerates windows/panes from tmux server
11. Restores native tab/split layout

### Multi-Server Architecture

The newer multi-server variant uses a single daemon managing multiple children:
- Pre-assigned FDs (0-4): accept socket, write connection, dead-man's pipe, read pipe, advisory lock
- Structured protocol (`iTermMultiServerProtocol`) for child lifecycle management
- More efficient than one server per shell process

---

## 9. Advanced Features

### Window Affinity System

tmux windows are grouped into "equivalence classes" to determine which native macOS window they appear in as tabs:

```objc
// TmuxController.m
// Affinities stored as tmux server user option: @affinities
// Format: "a_windowId1_windowId2_..." groups windows together

// Also encodes terminal GUIDs: "pty-<GUID>" for reconnection
```

When a user drags tabs between windows, affinities are updated on the tmux server.

### Pause Mode (Flow Control, tmux 3.2+)

```
%pause %<pane-id>     // Pane buffer is full, stop reading
%continue %<pane-id>  // Buffer drained, resume reading
```

iTerm2 monitors per-pane latency via `iTermTmuxBufferSizeMonitor`. When latency is too high, it adjusts behavior to prevent the tmux server from buffering excessive data.

### Subscription System (tmux 3.2+)

Instead of polling for changes:
```
refresh-client -B '<id>:<target>:<format>'
```

Subscribes to tmux variable changes. The `%subscription-changed` notification delivers updates. Used by `iTermTmuxOptionMonitor` for:
- Pane titles
- Foreground process names
- Window flags

### Client Tracker (tmux 3.6+)

`iTermTmuxClientTracker` tracks all clients attached to the same session to determine which iTerm2 instance should respond to OSC queries (e.g., OSC 52 clipboard). The lexicographically first control-mode client wins.

---

## 10. Lessons for libitshell3

### What to Adopt

1. **Control mode protocol**: The `%`-prefixed notification system is simple, human-readable, and debuggable. libitshell3 should have a similar text-based control mode for programmatic clients.

2. **Command queue with %begin/%end framing**: Reliable request-response over a streaming protocol. Essential for avoiding lost/mangled responses.

3. **Octal/hex-escaped output**: Safe encoding for binary terminal data over a text protocol.

4. **FD passing for crash recovery**: The FileDescriptorServer pattern allows session survival across app crashes.

5. **Layout string serialization**: Compact representation of the split tree that can be transmitted and parsed efficiently.

6. **Affinity system**: Grouping related panes/tabs into native windows is a great UX pattern.

7. **Pause/continue flow control**: Essential for preventing buffer bloat when the client is slow.

### What to Improve

1. **No CJK preedit**: tmux has no concept of IME composition state. libitshell3 adds `%preedit-*` notifications.

2. **Key sending is inefficient**: tmux's `send-keys` approach sends keystrokes one-by-one via commands. libitshell3 should have a dedicated input channel for low-latency key forwarding.

3. **No structured data**: tmux's control mode is text-only. libitshell3 can use a hybrid: text-based control mode for debugging/scripting + binary channel for performance-critical data (terminal output, key input).

4. **Version guessing**: tmux requires complex version detection. libitshell3 should use explicit capability negotiation during handshake.

5. **Paste buffer sync is reactive**: tmux only notifies on buffer change. libitshell3 should support bidirectional clipboard sync with the client OS clipboard.
