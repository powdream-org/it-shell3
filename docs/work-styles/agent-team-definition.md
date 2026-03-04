# Agent Team Definitions

This document defines the agent teams available for design and development work.
For individual team members and their roles, see each team's directory under `.claude/agents/`.

## Teams

### protocol-team

**Directory**: `.claude/agents/protocol-team/`

**Purpose**: Owns the libitshell3 server-client binary protocol design. Covers wire format,
message framing, session/pane management, flow control, CJK preedit protocol, and
handshake/capability negotiation.

### ime-team

**Directory**: `.claude/agents/ime-team/`

**Purpose**: Owns the libitshell3-ime interface contract design. Covers ImeEngine vtable,
Korean Hangul composition via libhangul, ImeResult semantics, and ghostty integration layer.

### references-expert

**Directory**: `.claude/agents/references-expert/`

**Purpose**: Provides source-level analysis of reference codebases (ghostty, tmux, zellij,
iTerm2). These agents read and report findings only — they do NOT write design documents.
Spawned on-demand when a design debate needs concrete implementation evidence to resolve.
