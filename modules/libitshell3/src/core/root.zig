pub const types = @import("types.zig");
pub const preedit_state = @import("preedit_state.zig");
pub const split_tree = @import("split_tree.zig");
pub const pane = @import("pane.zig");
pub const session = @import("session.zig");
pub const session_manager = @import("session_manager.zig");
pub const navigation = @import("navigation.zig");

// Convenience re-exports for commonly used types
pub const PaneId = types.PaneId;
pub const PaneSlot = types.PaneSlot;
pub const SessionId = types.SessionId;
pub const ClientId = types.ClientId;
pub const Direction = types.Direction;
pub const Orientation = types.Orientation;
pub const FreeMask = types.FreeMask;
pub const DirtyMask = types.DirtyMask;
pub const MAX_PANES = types.MAX_PANES;
pub const MAX_TREE_NODES = types.MAX_TREE_NODES;
pub const MAX_SESSIONS = types.MAX_SESSIONS;
pub const MAX_CLIENTS = types.MAX_CLIENTS;

pub const Pane = pane.Pane;
pub const Session = session.Session;
pub const SessionEntry = session.SessionEntry;
pub const SessionManager = session_manager.SessionManager;
pub const PreeditState = preedit_state.PreeditState;
pub const SplitNodeData = split_tree.SplitNodeData;
