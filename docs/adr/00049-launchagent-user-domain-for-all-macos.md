# 00049. LaunchAgent user/<uid> Domain for All macOS Environments

- Date: 2026-03-24
- Status: Accepted

## Context

macOS launchd provides two per-user domains for managing LaunchAgents:

- **`gui/<uid>`** (Aqua domain) — available only when the user has an active GUI
  login session. Default target for `~/Library/LaunchAgents/` plists.
- **`user/<uid>`** (Background domain) — always available, including SSH-only
  and headless server environments. No GUI access.

The it-shell3 daemon is headless (no GUI dependency). It needs to be managed by
launchd in both scenarios:

1. **Local macOS**: Client app running on the same machine starts the daemon
2. **Remote macOS via SSH**: Client connects to a remote macOS host and needs a
   persistent daemon (survives SSH disconnect)

Using `gui/<uid>` would make remote macOS auto-start impossible — the domain
doesn't exist in SSH-only sessions. Using `user/<uid>` works in both scenarios
because the Background domain is always available.

Research confirmed:

- `launchctl bootstrap user/<uid> <plist>` works from SSH sessions
- Socket activation (`Sockets` plist key) works in the `user/<uid>` domain
- `launch_activate_socket()` correctly retrieves inherited fds in both domains
- The daemon doesn't need GUI frameworks (WindowServer, AppKit), so `gui/<uid>`
  capabilities are unnecessary

## Decision

**Use `user/<uid>` (Background domain) exclusively for all macOS LaunchAgent
registration** — both local and remote. Do not use `gui/<uid>`.

- Local: `launchctl bootstrap user/$(id -u) <plist-path>`
- Remote: `ssh user@host "launchctl bootstrap user/$(id -u) <plist-path>"`
- Unload: `launchctl bootout user/$(id -u)/<label>`

The plist does NOT need `LimitLoadToSessionType = Background` when explicitly
bootstrapped into `user/<uid>` — the domain selection is the bootstrap command's
responsibility.

The legacy `launchctl load`/`unload` commands are deprecated (since macOS 10.10)
and are NOT used. All LaunchAgent management uses the modern
`bootstrap`/`bootout` subcommands.

## Consequences

- Single code path for LaunchAgent management — no `gui/<uid>` vs `user/<uid>`
  branching.
- Remote macOS auto-start works via SSH:
  `ssh host "launchctl bootstrap
  user/$(id -u) <plist>"`. The daemon is
  managed by launchd on the remote host and survives SSH disconnect.
- Headless macOS servers (no GUI login) are fully supported.
- Socket activation works identically in both local and remote scenarios.
- The daemon has no access to GUI frameworks (WindowServer, AppKit) from the
  Background domain — this is acceptable because the daemon is headless. The
  client app (which needs GUI) runs in its own process with its own domain.
- `KeepAlive: true` in the plist ensures launchd restarts the daemon after
  crashes, regardless of whether started locally or via SSH.
